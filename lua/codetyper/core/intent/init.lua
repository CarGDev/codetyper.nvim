---@mod codetyper.agent.intent Intent detection from prompts
---@brief [[
--- Parses prompt content to determine user intent and target scope.
--- Intents determine how the generated code should be applied.
---@brief ]]

local M = {}

---@class Intent
---@field type string "complete"|"refactor"|"add"|"fix"|"document"|"test"|"explain"|"optimize"
---@field scope_hint string|nil "function"|"class"|"block"|"file"|"selection"|nil
---@field confidence number 0.0-1.0 how confident we are about the intent
---@field action string "replace"|"insert"|"append"|"none"
---@field keywords string[] Keywords that triggered this intent

local params = require("codetyper.params.agent.intent")
local intent_patterns = params.intent_patterns
local scope_patterns = params.scope_patterns
local prompts = require("codetyper.prompts.agent.intent")

--- Detect intent from prompt content
---@param prompt string The prompt content
---@return Intent
function M.detect(prompt)
	local lower = prompt:lower()
	local best_match = nil
	local best_priority = 999
	local matched_keywords = {}

	-- Check each intent type
	for intent_type, config in pairs(intent_patterns) do
		for _, pattern in ipairs(config.patterns) do
			if lower:find(pattern, 1, true) then
				if config.priority < best_priority then
					best_match = intent_type
					best_priority = config.priority
					matched_keywords = { pattern }
				elseif config.priority == best_priority and best_match == intent_type then
					table.insert(matched_keywords, pattern)
				end
			end
		end
	end

	-- Default to "add" if no clear intent
	if not best_match then
		best_match = "add"
		matched_keywords = {}
	end

	local config = intent_patterns[best_match]

	-- Detect scope hint from prompt
	local scope_hint = config.scope_hint
	for pattern, hint in pairs(scope_patterns) do
		if lower:find(pattern, 1, true) then
			scope_hint = hint or scope_hint
			break
		end
	end

	-- Calculate confidence based on keyword matches
	local confidence = 0.5 + (#matched_keywords * 0.15)
	confidence = math.min(confidence, 1.0)

	return {
		type = best_match,
		scope_hint = scope_hint,
		confidence = confidence,
		action = config.action,
		keywords = matched_keywords,
	}
end

--- Check if intent requires code modification
---@param intent Intent
---@return boolean
function M.modifies_code(intent)
	return intent.action ~= "none"
end

--- Check if intent should replace existing code
---@param intent Intent
---@return boolean
function M.is_replacement(intent)
	return intent.action == "replace"
end

--- Check if intent adds new code
---@param intent Intent
---@return boolean
function M.is_insertion(intent)
	return intent.action == "insert" or intent.action == "append"
end

--- Get system prompt modifier based on intent
---@param intent Intent
---@return string
function M.get_prompt_modifier(intent)
	local modifiers = prompts.modifiers
	return modifiers[intent.type] or modifiers.add
end

--- Format intent for logging
---@param intent Intent
---@return string
function M.format(intent)
	return string.format(
		"%s (scope: %s, action: %s, confidence: %.2f)",
		intent.type,
		intent.scope_hint or "auto",
		intent.action,
		intent.confidence
	)
end

return M
