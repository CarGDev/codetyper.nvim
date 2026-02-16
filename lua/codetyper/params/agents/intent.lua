---@mod codetyper.params.agents.intent Intent patterns and scope configuration
local M = {}

--- Intent patterns with associated metadata
M.intent_patterns = {
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
M.scope_patterns = {
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

return M
