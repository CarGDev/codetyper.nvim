---@mod codetyper.ask.intent Intent detection for Ask mode
---@brief [[
--- Analyzes user prompts to detect intent (ask/explain vs code generation).
--- Routes to appropriate prompt type and context sources.
---@brief ]]

local M = {}

---@alias IntentType "ask"|"explain"|"generate"|"refactor"|"document"|"test"

---@class Intent
---@field type IntentType Detected intent type
---@field confidence number 0-1 confidence score
---@field needs_project_context boolean Whether project-wide context is needed
---@field needs_brain_context boolean Whether brain/learned context is helpful
---@field needs_exploration boolean Whether full project exploration is needed
---@field keywords string[] Keywords that influenced detection

--- Patterns for detecting ask/explain intent (questions about code)
local ASK_PATTERNS = {
	-- Question words
	{ pattern = "^what%s", weight = 0.9 },
	{ pattern = "^why%s", weight = 0.95 },
	{ pattern = "^how%s+does", weight = 0.9 },
	{ pattern = "^how%s+do%s+i", weight = 0.7 }, -- Could be asking for code
	{ pattern = "^where%s", weight = 0.85 },
	{ pattern = "^when%s", weight = 0.85 },
	{ pattern = "^which%s", weight = 0.8 },
	{ pattern = "^who%s", weight = 0.85 },
	{ pattern = "^can%s+you%s+explain", weight = 0.95 },
	{ pattern = "^could%s+you%s+explain", weight = 0.95 },
	{ pattern = "^please%s+explain", weight = 0.95 },

	-- Explanation requests
	{ pattern = "explain%s", weight = 0.9 },
	{ pattern = "describe%s", weight = 0.85 },
	{ pattern = "tell%s+me%s+about", weight = 0.85 },
	{ pattern = "walk%s+me%s+through", weight = 0.9 },
	{ pattern = "help%s+me%s+understand", weight = 0.95 },
	{ pattern = "what%s+is%s+the%s+purpose", weight = 0.95 },
	{ pattern = "what%s+does%s+this", weight = 0.9 },
	{ pattern = "what%s+does%s+it", weight = 0.9 },
	{ pattern = "how%s+does%s+this%s+work", weight = 0.95 },
	{ pattern = "how%s+does%s+it%s+work", weight = 0.95 },

	-- Understanding queries
	{ pattern = "understand", weight = 0.7 },
	{ pattern = "meaning%s+of", weight = 0.85 },
	{ pattern = "difference%s+between", weight = 0.9 },
	{ pattern = "compared%s+to", weight = 0.8 },
	{ pattern = "vs%s", weight = 0.7 },
	{ pattern = "versus", weight = 0.7 },
	{ pattern = "pros%s+and%s+cons", weight = 0.9 },
	{ pattern = "advantages", weight = 0.8 },
	{ pattern = "disadvantages", weight = 0.8 },
	{ pattern = "trade%-?offs?", weight = 0.85 },

	-- Analysis requests
	{ pattern = "analyze", weight = 0.85 },
	{ pattern = "review", weight = 0.7 }, -- Could also be refactor
	{ pattern = "overview", weight = 0.9 },
	{ pattern = "summary", weight = 0.9 },
	{ pattern = "summarize", weight = 0.9 },

	-- Question marks (weaker signal)
	{ pattern = "%?$", weight = 0.3 },
	{ pattern = "%?%s*$", weight = 0.3 },
}

--- Patterns for detecting code generation intent
local GENERATE_PATTERNS = {
	-- Direct commands
	{ pattern = "^create%s", weight = 0.9 },
	{ pattern = "^make%s", weight = 0.85 },
	{ pattern = "^build%s", weight = 0.85 },
	{ pattern = "^write%s", weight = 0.9 },
	{ pattern = "^add%s", weight = 0.85 },
	{ pattern = "^implement%s", weight = 0.95 },
	{ pattern = "^generate%s", weight = 0.95 },
	{ pattern = "^code%s", weight = 0.8 },

	-- Modification commands
	{ pattern = "^fix%s", weight = 0.9 },
	{ pattern = "^change%s", weight = 0.8 },
	{ pattern = "^update%s", weight = 0.75 },
	{ pattern = "^modify%s", weight = 0.8 },
	{ pattern = "^replace%s", weight = 0.85 },
	{ pattern = "^remove%s", weight = 0.85 },
	{ pattern = "^delete%s", weight = 0.85 },

	-- Feature requests
	{ pattern = "i%s+need%s+a", weight = 0.8 },
	{ pattern = "i%s+want%s+a", weight = 0.8 },
	{ pattern = "give%s+me", weight = 0.7 },
	{ pattern = "show%s+me%s+how%s+to%s+code", weight = 0.9 },
	{ pattern = "how%s+do%s+i%s+implement", weight = 0.85 },
	{ pattern = "can%s+you%s+write", weight = 0.9 },
	{ pattern = "can%s+you%s+create", weight = 0.9 },
	{ pattern = "can%s+you%s+add", weight = 0.85 },
	{ pattern = "can%s+you%s+make", weight = 0.85 },

	-- Code-specific terms
	{ pattern = "function%s+that", weight = 0.85 },
	{ pattern = "class%s+that", weight = 0.85 },
	{ pattern = "method%s+that", weight = 0.85 },
	{ pattern = "component%s+that", weight = 0.85 },
	{ pattern = "module%s+that", weight = 0.85 },
	{ pattern = "api%s+for", weight = 0.8 },
	{ pattern = "endpoint%s+for", weight = 0.8 },
}

--- Patterns for detecting refactor intent
local REFACTOR_PATTERNS = {
	{ pattern = "^refactor%s", weight = 0.95 },
	{ pattern = "refactor%s+this", weight = 0.95 },
	{ pattern = "clean%s+up", weight = 0.85 },
	{ pattern = "improve%s+this%s+code", weight = 0.85 },
	{ pattern = "make%s+this%s+cleaner", weight = 0.85 },
	{ pattern = "simplify", weight = 0.8 },
	{ pattern = "optimize", weight = 0.75 }, -- Could be explain
	{ pattern = "reorganize", weight = 0.9 },
	{ pattern = "restructure", weight = 0.9 },
	{ pattern = "extract%s+to", weight = 0.9 },
	{ pattern = "split%s+into", weight = 0.85 },
	{ pattern = "dry%s+this", weight = 0.9 }, -- Don't repeat yourself
	{ pattern = "reduce%s+duplication", weight = 0.9 },
}

--- Patterns for detecting documentation intent
local DOCUMENT_PATTERNS = {
	{ pattern = "^document%s", weight = 0.95 },
	{ pattern = "add%s+documentation", weight = 0.95 },
	{ pattern = "add%s+docs", weight = 0.95 },
	{ pattern = "add%s+comments", weight = 0.9 },
	{ pattern = "add%s+docstring", weight = 0.95 },
	{ pattern = "add%s+jsdoc", weight = 0.95 },
	{ pattern = "write%s+documentation", weight = 0.95 },
	{ pattern = "document%s+this", weight = 0.95 },
}

--- Patterns for detecting test generation intent
local TEST_PATTERNS = {
	{ pattern = "^test%s", weight = 0.9 },
	{ pattern = "write%s+tests?%s+for", weight = 0.95 },
	{ pattern = "add%s+tests?%s+for", weight = 0.95 },
	{ pattern = "create%s+tests?%s+for", weight = 0.95 },
	{ pattern = "generate%s+tests?", weight = 0.95 },
	{ pattern = "unit%s+tests?", weight = 0.9 },
	{ pattern = "test%s+cases?%s+for", weight = 0.95 },
	{ pattern = "spec%s+for", weight = 0.85 },
}

--- Patterns indicating project-wide context is needed
local PROJECT_CONTEXT_PATTERNS = {
	{ pattern = "project", weight = 0.9 },
	{ pattern = "codebase", weight = 0.95 },
	{ pattern = "entire", weight = 0.7 },
	{ pattern = "whole", weight = 0.7 },
	{ pattern = "all%s+files", weight = 0.9 },
	{ pattern = "architecture", weight = 0.95 },
	{ pattern = "structure", weight = 0.85 },
	{ pattern = "how%s+is%s+.*%s+organized", weight = 0.95 },
	{ pattern = "where%s+is%s+.*%s+defined", weight = 0.9 },
	{ pattern = "dependencies", weight = 0.85 },
	{ pattern = "imports?%s+from", weight = 0.7 },
	{ pattern = "modules?", weight = 0.6 },
	{ pattern = "packages?", weight = 0.6 },
}

--- Patterns indicating project exploration is needed (full indexing)
local EXPLORE_PATTERNS = {
	{ pattern = "explain%s+.*%s*project", weight = 1.0 },
	{ pattern = "explain%s+.*%s*codebase", weight = 1.0 },
	{ pattern = "explain%s+me%s+the%s+project", weight = 1.0 },
	{ pattern = "tell%s+me%s+about%s+.*%s*project", weight = 0.95 },
	{ pattern = "what%s+is%s+this%s+project", weight = 0.95 },
	{ pattern = "overview%s+of%s+.*%s*project", weight = 0.95 },
	{ pattern = "understand%s+.*%s*project", weight = 0.9 },
	{ pattern = "analyze%s+.*%s*project", weight = 0.9 },
	{ pattern = "explore%s+.*%s*project", weight = 1.0 },
	{ pattern = "explore%s+.*%s*codebase", weight = 1.0 },
	{ pattern = "index%s+.*%s*project", weight = 1.0 },
	{ pattern = "scan%s+.*%s*project", weight = 0.95 },
}

--- Match patterns against text
---@param text string Lowercased text to match
---@param patterns table Pattern list with weights
---@return number Score, string[] Matched keywords
local function match_patterns(text, patterns)
	local score = 0
	local matched = {}

	for _, p in ipairs(patterns) do
		if text:match(p.pattern) then
			score = score + p.weight
			table.insert(matched, p.pattern)
		end
	end

	return score, matched
end

--- Detect intent from user prompt
---@param prompt string User's question/request
---@return Intent Detected intent
function M.detect(prompt)
	local text = prompt:lower()

	-- Calculate raw scores for each intent type (sum of matched weights)
	local ask_score, ask_kw = match_patterns(text, ASK_PATTERNS)
	local gen_score, gen_kw = match_patterns(text, GENERATE_PATTERNS)
	local ref_score, ref_kw = match_patterns(text, REFACTOR_PATTERNS)
	local doc_score, doc_kw = match_patterns(text, DOCUMENT_PATTERNS)
	local test_score, test_kw = match_patterns(text, TEST_PATTERNS)
	local proj_score, _ = match_patterns(text, PROJECT_CONTEXT_PATTERNS)
	local explore_score, _ = match_patterns(text, EXPLORE_PATTERNS)

	-- Find the winner by raw score (highest accumulated weight)
	local scores = {
		{ type = "ask", score = ask_score, keywords = ask_kw },
		{ type = "generate", score = gen_score, keywords = gen_kw },
		{ type = "refactor", score = ref_score, keywords = ref_kw },
		{ type = "document", score = doc_score, keywords = doc_kw },
		{ type = "test", score = test_score, keywords = test_kw },
	}

	table.sort(scores, function(a, b)
		return a.score > b.score
	end)

	local winner = scores[1]

	-- If top score is very low, default to ask (safer for Q&A)
	if winner.score < 0.3 then
		winner = { type = "ask", score = 0.5, keywords = {} }
	end

	-- If ask and generate are close AND there's a question mark, prefer ask
	if winner.type == "generate" and ask_score > 0 then
		if text:match("%?%s*$") and ask_score >= gen_score * 0.5 then
			winner = { type = "ask", score = ask_score, keywords = ask_kw }
		end
	end

	-- Determine if "explain" vs "ask" (explain needs more context)
	local intent_type = winner.type
	if intent_type == "ask" then
		-- "explain" if asking about how something works, otherwise "ask"
		if text:match("explain") or text:match("how%s+does") or text:match("walk%s+me%s+through") then
			intent_type = "explain"
		end
	end

	-- Normalize confidence to 0-1 range (cap at reasonable max)
	local confidence = math.min(winner.score / 2, 1.0)

	-- Check if exploration is needed (full project indexing)
	local needs_exploration = explore_score >= 0.9

	---@type Intent
	local intent = {
		type = intent_type,
		confidence = confidence,
		needs_project_context = proj_score > 0.5 or needs_exploration,
		needs_brain_context = intent_type == "ask" or intent_type == "explain",
		needs_exploration = needs_exploration,
		keywords = winner.keywords,
	}

	return intent
end

--- Get prompt type for system prompt selection
---@param intent Intent Detected intent
---@return string Prompt type for prompts.system
function M.get_prompt_type(intent)
	local mapping = {
		ask = "ask",
		explain = "ask", -- Uses same prompt as ask
		generate = "code_generation",
		refactor = "refactor",
		document = "document",
		test = "test",
	}
	return mapping[intent.type] or "ask"
end

--- Check if intent requires code output
---@param intent Intent
---@return boolean
function M.produces_code(intent)
	local code_intents = {
		generate = true,
		refactor = true,
		document = true, -- Documentation is code (comments)
		test = true,
	}
	return code_intents[intent.type] or false
end

return M
