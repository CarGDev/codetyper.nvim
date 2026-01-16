---@mod codetyper.params.agent.scope Tree-sitter scope mappings
local M = {}

--- Node types that represent function-like scopes per language
M.function_nodes = {
	-- Lua
	["function_declaration"] = "function",
	["function_definition"] = "function",
	["local_function"] = "function",
	["function"] = "function",

	-- JavaScript/TypeScript
	["function_declaration"] = "function",
	["function_expression"] = "function",
	["arrow_function"] = "function",
	["method_definition"] = "method",
	["function"] = "function",

	-- Python
	["function_definition"] = "function",
	["lambda"] = "function",

	-- Go
	["function_declaration"] = "function",
	["method_declaration"] = "method",
	["func_literal"] = "function",

	-- Rust
	["function_item"] = "function",
	["closure_expression"] = "function",

	-- C/C++
	["function_definition"] = "function",
	["lambda_expression"] = "function",

	-- Java
	["method_declaration"] = "method",
	["constructor_declaration"] = "method",
	["lambda_expression"] = "function",

	-- Ruby
	["method"] = "method",
	["singleton_method"] = "method",
	["lambda"] = "function",
	["block"] = "function",

	-- PHP
	["function_definition"] = "function",
	["method_declaration"] = "method",
	["arrow_function"] = "function",
}

--- Node types that represent class-like scopes
M.class_nodes = {
	["class_declaration"] = "class",
	["class_definition"] = "class",
	["struct_declaration"] = "class",
	["impl_item"] = "class", -- Rust config
	["interface_declaration"] = "class",
	["trait_item"] = "class",
}

--- Node types that represent block scopes
M.block_nodes = {
	["block"] = "block",
	["do_statement"] = "block", -- Lua
	["if_statement"] = "block",
	["for_statement"] = "block",
	["while_statement"] = "block",
}

return M
