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

--- Intent patterns with associated metadata
local intent_patterns = {
	-- Complete: fill in missing implementation
	complete = {
		patterns = {
			"complete",
			"finish",
			"implement",
			"fill in",
			"fill out",
			"stub",
			"todo",
			"fixme",
		},
		scope_hint = "function",
		action = "replace",
		priority = 1,
	},

	-- Refactor: rewrite existing code
	refactor = {
		patterns = {
			"refactor",
			"rewrite",
			"restructure",
			"reorganize",
			"clean up",
			"cleanup",
			"simplify",
			"improve",
		},
		scope_hint = "function",
		action = "replace",
		priority = 2,
	},

	-- Fix: repair bugs or issues
	fix = {
		patterns = {
			"fix",
			"repair",
			"correct",
			"debug",
			"solve",
			"resolve",
			"patch",
			"bug",
			"error",
			"issue",
			"update",
			"modify",
			"change",
			"adjust",
			"tweak",
		},
		scope_hint = "function",
		action = "replace",
		priority = 1,
	},

	-- Add: insert new code
	add = {
		patterns = {
			"add",
			"create",
			"insert",
			"include",
			"append",
			"new",
			"generate",
			"write",
		},
		scope_hint = nil, -- Could be anywhere
		action = "insert",
		priority = 3,
	},

	-- Document: add documentation
	document = {
		patterns = {
			"document",
			"comment",
			"jsdoc",
			"docstring",
			"describe",
			"annotate",
			"type hint",
			"typehint",
		},
		scope_hint = "function",
		action = "replace", -- Replace with documented version
		priority = 2,
	},

	-- Test: generate tests
	test = {
		patterns = {
			"test",
			"spec",
			"unit test",
			"integration test",
			"coverage",
		},
		scope_hint = "file",
		action = "append",
		priority = 3,
	},

	-- Optimize: improve performance
	optimize = {
		patterns = {
			"optimize",
			"performance",
			"faster",
			"efficient",
			"speed up",
			"reduce",
			"minimize",
		},
		scope_hint = "function",
		action = "replace",
		priority = 2,
	},

	-- Explain: provide explanation (no code change)
	explain = {
		patterns = {
			"explain",
			"what does",
			"how does",
			"why",
			"describe",
			"walk through",
			"understand",
		},
		scope_hint = "function",
		action = "none",
		priority = 4,
	},
}

--- Scope hint patterns
local scope_patterns = {
	["this function"] = "function",
	["this method"] = "function",
	["the function"] = "function",
	["the method"] = "function",
	["this class"] = "class",
	["the class"] = "class",
	["this file"] = "file",
	["the file"] = "file",
	["this block"] = "block",
	["the block"] = "block",
	["this"] = nil, -- Use Tree-sitter to determine
	["here"] = nil,
}

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
	local modifiers = {
		complete = [[
You are completing an incomplete function.
Return the complete function with all missing parts filled in.
Keep the existing signature unless changes are required.
Output only the code, no explanations.]],

		refactor = [[
You are refactoring existing code.
Improve the code structure while maintaining the same behavior.
Keep the function signature unchanged.
Output only the refactored code, no explanations.]],

		fix = [[
You are fixing a bug in the code.
Identify and correct the issue while minimizing changes.
Preserve the original intent of the code.
Output only the fixed code, no explanations.]],

		add = [[
You are adding new code.
Follow the existing code style and conventions.
Output only the new code to be inserted, no explanations.]],

		document = [[
You are adding documentation to the code.
Add appropriate comments/docstrings for the function.
Include parameter types, return types, and description.
Output the complete function with documentation.]],

		test = [[
You are generating tests for the code.
Create comprehensive unit tests covering edge cases.
Follow the testing conventions of the project.
Output only the test code, no explanations.]],

		optimize = [[
You are optimizing code for performance.
Improve efficiency while maintaining correctness.
Document any significant algorithmic changes.
Output only the optimized code, no explanations.]],

		explain = [[
You are explaining code to a developer.
Provide a clear, concise explanation of what the code does.
Include information about the algorithm and any edge cases.
Do not output code, only explanation.]],
	}

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
