---@mod codetyper.llm.selector Smart LLM selection with memory-based confidence
---@brief [[
--- Intelligent LLM provider selection based on brain memories.
--- Prefers local Ollama when context is rich, falls back to Copilot otherwise.
--- Implements verification pondering to reinforce Ollama accuracy over time.
---@brief ]]

local M = {}

---@class SelectionResult
---@field provider string Selected provider name
---@field confidence number Confidence score (0-1)
---@field memory_count number Number of relevant memories found
---@field reason string Human-readable reason for selection

---@class PonderResult
---@field ollama_response string Ollama's response
---@field verifier_response string Verifier's response
---@field agreement_score number How much they agree (0-1)
---@field ollama_correct boolean Whether Ollama was deemed correct
---@field feedback string Feedback for learning

--- Minimum memories required for high confidence
local MIN_MEMORIES_FOR_LOCAL = 3

--- Minimum memory relevance score for local provider
local MIN_RELEVANCE_FOR_LOCAL = 0.6

--- Agreement threshold for Ollama verification
local AGREEMENT_THRESHOLD = 0.7

--- Pondering sample rate (0-1) - how often to verify Ollama
local PONDER_SAMPLE_RATE = 0.2

--- Provider accuracy tracking (persisted in brain)
local accuracy_cache = {
	ollama = { correct = 0, total = 0 },
	copilot = { correct = 0, total = 0 },
}

--- Get the brain module safely
---@return table|nil
local function get_brain()
	local ok, brain = pcall(require, "codetyper.brain")
	if ok and brain.is_initialized and brain.is_initialized() then
		return brain
	end
	return nil
end

--- Load accuracy stats from brain
local function load_accuracy_stats()
	local brain = get_brain()
	if not brain then
		return
	end

	-- Query for accuracy tracking nodes
	pcall(function()
		local result = brain.query({
			query = "provider_accuracy_stats",
			types = { "metric" },
			limit = 1,
		})

		if result and result.nodes and #result.nodes > 0 then
			local node = result.nodes[1]
			if node.c and node.c.d then
				local ok, stats = pcall(vim.json.decode, node.c.d)
				if ok and stats then
					accuracy_cache = stats
				end
			end
		end
	end)
end

--- Save accuracy stats to brain
local function save_accuracy_stats()
	local brain = get_brain()
	if not brain then
		return
	end

	pcall(function()
		brain.learn({
			type = "metric",
			summary = "provider_accuracy_stats",
			detail = vim.json.encode(accuracy_cache),
			weight = 1.0,
		})
	end)
end

--- Calculate Ollama confidence based on historical accuracy
---@return number confidence (0-1)
local function get_ollama_historical_confidence()
	local stats = accuracy_cache.ollama
	if stats.total < 5 then
		-- Not enough data, return neutral confidence
		return 0.5
	end

	local accuracy = stats.correct / stats.total
	-- Boost confidence if accuracy is high
	return math.min(1.0, accuracy * 1.2)
end

--- Query brain for relevant context
---@param prompt string User prompt
---@param file_path string|nil Current file path
---@return table result {memories: table[], relevance: number, count: number}
local function query_brain_context(prompt, file_path)
	local result = {
		memories = {},
		relevance = 0,
		count = 0,
	}

	local brain = get_brain()
	if not brain then
		return result
	end

	-- Query brain with multiple dimensions
	local ok, query_result = pcall(function()
		return brain.query({
			query = prompt,
			file = file_path,
			limit = 10,
			types = { "pattern", "correction", "convention", "fact" },
		})
	end)

	if not ok or not query_result then
		return result
	end

	result.memories = query_result.nodes or {}
	result.count = #result.memories

	-- Calculate average relevance
	if result.count > 0 then
		local total_relevance = 0
		for _, node in ipairs(result.memories) do
			-- Use node weight and success rate as relevance indicators
			local node_relevance = (node.sc and node.sc.w or 0.5) * (node.sc and node.sc.sr or 0.5)
			total_relevance = total_relevance + node_relevance
		end
		result.relevance = total_relevance / result.count
	end

	return result
end

--- Select the best LLM provider based on context
---@param prompt string User prompt
---@param context table LLM context
---@return SelectionResult
function M.select_provider(prompt, context)
	-- Load accuracy stats on first call
	if accuracy_cache.ollama.total == 0 then
		load_accuracy_stats()
	end

	local file_path = context.file_path

	-- Query brain for relevant memories
	local brain_context = query_brain_context(prompt, file_path)

	-- Calculate base confidence from memories
	local memory_confidence = 0
	if brain_context.count >= MIN_MEMORIES_FOR_LOCAL then
		memory_confidence = math.min(1.0, brain_context.count / 10) * brain_context.relevance
	end

	-- Factor in historical Ollama accuracy
	local historical_confidence = get_ollama_historical_confidence()

	-- Combined confidence score
	local combined_confidence = (memory_confidence * 0.6) + (historical_confidence * 0.4)

	-- Decision logic
	local provider = "copilot" -- Default to more capable
	local reason = ""

	if brain_context.count >= MIN_MEMORIES_FOR_LOCAL and combined_confidence >= MIN_RELEVANCE_FOR_LOCAL then
		provider = "ollama"
		reason = string.format(
			"Rich context: %d memories (%.1f%% relevance), historical accuracy: %.1f%%",
			brain_context.count,
			brain_context.relevance * 100,
			historical_confidence * 100
		)
	elseif brain_context.count > 0 and combined_confidence >= 0.4 then
		-- Medium confidence - use Ollama but with pondering
		provider = "ollama"
		reason = string.format(
			"Moderate context: %d memories, will verify with pondering",
			brain_context.count
		)
	else
		reason = string.format(
			"Insufficient context: %d memories (need %d), using capable provider",
			brain_context.count,
			MIN_MEMORIES_FOR_LOCAL
		)
	end

	return {
		provider = provider,
		confidence = combined_confidence,
		memory_count = brain_context.count,
		reason = reason,
		memories = brain_context.memories,
	}
end

--- Check if we should ponder (verify) this Ollama response
---@param confidence number Current confidence level
---@return boolean
function M.should_ponder(confidence)
	-- Always ponder when confidence is medium
	if confidence >= 0.4 and confidence < 0.7 then
		return true
	end

	-- Random sampling for high confidence to keep learning
	if confidence >= 0.7 then
		return math.random() < PONDER_SAMPLE_RATE
	end

	-- Low confidence shouldn't reach Ollama anyway
	return false
end

--- Calculate agreement score between two responses
---@param response1 string First response
---@param response2 string Second response
---@return number Agreement score (0-1)
local function calculate_agreement(response1, response2)
	-- Normalize responses
	local norm1 = response1:lower():gsub("%s+", " "):gsub("[^%w%s]", "")
	local norm2 = response2:lower():gsub("%s+", " "):gsub("[^%w%s]", "")

	-- Extract words
	local words1 = {}
	for word in norm1:gmatch("%w+") do
		words1[word] = (words1[word] or 0) + 1
	end

	local words2 = {}
	for word in norm2:gmatch("%w+") do
		words2[word] = (words2[word] or 0) + 1
	end

	-- Calculate Jaccard similarity
	local intersection = 0
	local union = 0

	for word, count1 in pairs(words1) do
		local count2 = words2[word] or 0
		intersection = intersection + math.min(count1, count2)
		union = union + math.max(count1, count2)
	end

	for word, count2 in pairs(words2) do
		if not words1[word] then
			union = union + count2
		end
	end

	if union == 0 then
		return 1.0 -- Both empty
	end

	-- Also check structural similarity (code structure)
	local struct_score = 0
	local function_count1 = select(2, response1:gsub("function", ""))
	local function_count2 = select(2, response2:gsub("function", ""))
	if function_count1 > 0 or function_count2 > 0 then
		struct_score = 1 - math.abs(function_count1 - function_count2) / math.max(function_count1, function_count2, 1)
	else
		struct_score = 1.0
	end

	-- Combined score
	local jaccard = intersection / union
	return (jaccard * 0.7) + (struct_score * 0.3)
end

--- Ponder (verify) Ollama's response with another LLM
---@param prompt string Original prompt
---@param context table LLM context
---@param ollama_response string Ollama's response
---@param callback fun(result: PonderResult) Callback with pondering result
function M.ponder(prompt, context, ollama_response, callback)
	-- Use Copilot as verifier
	local copilot = require("codetyper.llm.copilot")

	-- Build verification prompt
	local verify_prompt = prompt

	copilot.generate(verify_prompt, context, function(verifier_response, error)
		if error or not verifier_response then
			-- Verification failed, assume Ollama is correct
			callback({
				ollama_response = ollama_response,
				verifier_response = "",
				agreement_score = 1.0,
				ollama_correct = true,
				feedback = "Verification unavailable, trusting Ollama",
			})
			return
		end

		-- Calculate agreement
		local agreement = calculate_agreement(ollama_response, verifier_response)

		-- Determine if Ollama was correct
		local ollama_correct = agreement >= AGREEMENT_THRESHOLD

		-- Generate feedback
		local feedback
		if ollama_correct then
			feedback = string.format("Agreement: %.1f%% - Ollama response validated", agreement * 100)
		else
			feedback = string.format(
				"Disagreement: %.1f%% - Ollama may need correction",
				(1 - agreement) * 100
			)
		end

		-- Update accuracy tracking
		accuracy_cache.ollama.total = accuracy_cache.ollama.total + 1
		if ollama_correct then
			accuracy_cache.ollama.correct = accuracy_cache.ollama.correct + 1
		end
		save_accuracy_stats()

		-- Learn from this verification
		local brain = get_brain()
		if brain then
			pcall(function()
				if ollama_correct then
					-- Reinforce the pattern
					brain.learn({
						type = "correction",
						summary = "Ollama verified correct",
						detail = string.format(
							"Prompt: %s\nAgreement: %.1f%%",
							prompt:sub(1, 100),
							agreement * 100
						),
						weight = 0.8,
						file = context.file_path,
					})
				else
					-- Learn the correction
					brain.learn({
						type = "correction",
						summary = "Ollama needed correction",
						detail = string.format(
							"Prompt: %s\nOllama: %s\nCorrect: %s",
							prompt:sub(1, 100),
							ollama_response:sub(1, 200),
							verifier_response:sub(1, 200)
						),
						weight = 0.9,
						file = context.file_path,
					})
				end
			end)
		end

		callback({
			ollama_response = ollama_response,
			verifier_response = verifier_response,
			agreement_score = agreement,
			ollama_correct = ollama_correct,
			feedback = feedback,
		})
	end)
end

--- Smart generate with automatic provider selection and pondering
---@param prompt string User prompt
---@param context table LLM context
---@param callback fun(response: string|nil, error: string|nil, metadata: table|nil) Callback
function M.smart_generate(prompt, context, callback)
	-- Select provider
	local selection = M.select_provider(prompt, context)

	-- Log selection
	pcall(function()
		local logs = require("codetyper.agent.logs")
		logs.add({
			type = "info",
			message = string.format(
				"LLM: %s (confidence: %.1f%%, %s)",
				selection.provider,
				selection.confidence * 100,
				selection.reason
			),
		})
	end)

	-- Get the selected client
	local client
	if selection.provider == "ollama" then
		client = require("codetyper.llm.ollama")
	else
		client = require("codetyper.llm.copilot")
	end

	-- Generate response
	client.generate(prompt, context, function(response, error)
		if error then
			-- Fallback on error
			if selection.provider == "ollama" then
				-- Try Copilot as fallback
				local copilot = require("codetyper.llm.copilot")
				copilot.generate(prompt, context, function(fallback_response, fallback_error)
					callback(fallback_response, fallback_error, {
						provider = "copilot",
						fallback = true,
						original_provider = "ollama",
						original_error = error,
					})
				end)
				return
			end
			callback(nil, error, { provider = selection.provider })
			return
		end

		-- Check if we should ponder
		if selection.provider == "ollama" and M.should_ponder(selection.confidence) then
			M.ponder(prompt, context, response, function(ponder_result)
				if ponder_result.ollama_correct then
					-- Ollama was correct, use its response
					callback(response, nil, {
						provider = "ollama",
						pondered = true,
						agreement = ponder_result.agreement_score,
						confidence = selection.confidence,
					})
				else
					-- Use verifier's response instead
					callback(ponder_result.verifier_response, nil, {
						provider = "copilot",
						pondered = true,
						agreement = ponder_result.agreement_score,
						original_provider = "ollama",
						corrected = true,
					})
				end
			end)
		else
			-- No pondering needed
			callback(response, nil, {
				provider = selection.provider,
				pondered = false,
				confidence = selection.confidence,
			})
		end
	end)
end

--- Get current accuracy statistics
---@return table {ollama: {correct, total, accuracy}, copilot: {correct, total, accuracy}}
function M.get_accuracy_stats()
	local stats = {
		ollama = {
			correct = accuracy_cache.ollama.correct,
			total = accuracy_cache.ollama.total,
			accuracy = accuracy_cache.ollama.total > 0
				and (accuracy_cache.ollama.correct / accuracy_cache.ollama.total)
				or 0,
		},
		copilot = {
			correct = accuracy_cache.copilot.correct,
			total = accuracy_cache.copilot.total,
			accuracy = accuracy_cache.copilot.total > 0
				and (accuracy_cache.copilot.correct / accuracy_cache.copilot.total)
				or 0,
		},
	}
	return stats
end

--- Reset accuracy statistics
function M.reset_accuracy_stats()
	accuracy_cache = {
		ollama = { correct = 0, total = 0 },
		copilot = { correct = 0, total = 0 },
	}
	save_accuracy_stats()
end

--- Report user feedback on response quality
---@param provider string Which provider generated the response
---@param was_correct boolean Whether the response was good
function M.report_feedback(provider, was_correct)
	if accuracy_cache[provider] then
		accuracy_cache[provider].total = accuracy_cache[provider].total + 1
		if was_correct then
			accuracy_cache[provider].correct = accuracy_cache[provider].correct + 1
		end
		save_accuracy_stats()
	end
end

return M
