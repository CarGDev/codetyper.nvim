---@mod codetyper.indexer.analyzer Code analyzer using Tree-sitter
---@brief [[
--- Analyzes source files to extract functions, classes, exports, and imports.
--- Uses Tree-sitter when available, falls back to pattern matching.
---@brief ]]

local M = {}

local utils = require("codetyper.utils")
local scanner = require("codetyper.indexer.scanner")

--- Language-specific query patterns for Tree-sitter
local TS_QUERIES = {
	lua = {
		functions = [[
			(function_declaration name: (identifier) @name) @func
			(function_definition) @func
			(local_function name: (identifier) @name) @func
			(assignment_statement
				(variable_list name: (identifier) @name)
				(expression_list value: (function_definition) @func))
		]],
		exports = [[
			(return_statement (expression_list (table_constructor))) @export
		]],
	},
	typescript = {
		functions = [[
			(function_declaration name: (identifier) @name) @func
			(method_definition name: (property_identifier) @name) @func
			(arrow_function) @func
			(lexical_declaration
				(variable_declarator name: (identifier) @name value: (arrow_function) @func))
		]],
		exports = [[
			(export_statement) @export
		]],
		imports = [[
			(import_statement) @import
		]],
	},
	javascript = {
		functions = [[
			(function_declaration name: (identifier) @name) @func
			(method_definition name: (property_identifier) @name) @func
			(arrow_function) @func
		]],
		exports = [[
			(export_statement) @export
		]],
		imports = [[
			(import_statement) @import
		]],
	},
	python = {
		functions = [[
			(function_definition name: (identifier) @name) @func
		]],
		classes = [[
			(class_definition name: (identifier) @name) @class
		]],
		imports = [[
			(import_statement) @import
			(import_from_statement) @import
		]],
	},
	go = {
		functions = [[
			(function_declaration name: (identifier) @name) @func
			(method_declaration name: (field_identifier) @name) @func
		]],
		imports = [[
			(import_declaration) @import
		]],
	},
	rust = {
		functions = [[
			(function_item name: (identifier) @name) @func
		]],
		imports = [[
			(use_declaration) @import
		]],
	},
}

-- Forward declaration for analyze_tree_generic (defined below)
local analyze_tree_generic

--- Hash file content for change detection
---@param content string
---@return string
local function hash_content(content)
	local hash = 0
	for i = 1, math.min(#content, 10000) do
		hash = (hash * 31 + string.byte(content, i)) % 2147483647
	end
	return string.format("%08x", hash)
end

--- Try to get Tree-sitter parser for a language
---@param lang string
---@return boolean
local function has_ts_parser(lang)
	local ok = pcall(vim.treesitter.language.inspect, lang)
	return ok
end

--- Analyze file using Tree-sitter
---@param filepath string
---@param lang string
---@param content string
---@return table|nil
local function analyze_with_treesitter(filepath, lang, content)
	if not has_ts_parser(lang) then
		return nil
	end

	local result = {
		functions = {},
		classes = {},
		exports = {},
		imports = {},
	}

	-- Create a temporary buffer for parsing
	local bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(content, "\n"))

	local ok, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
	if not ok or not parser then
		vim.api.nvim_buf_delete(bufnr, { force = true })
		return nil
	end

	local tree = parser:parse()[1]
	if not tree then
		vim.api.nvim_buf_delete(bufnr, { force = true })
		return nil
	end

	local root = tree:root()
	local queries = TS_QUERIES[lang]

	if not queries then
		-- Fallback: walk tree manually for common patterns
		result = analyze_tree_generic(root, bufnr)
	else
		-- Use language-specific queries
		if queries.functions then
			local query_ok, query = pcall(vim.treesitter.query.parse, lang, queries.functions)
			if query_ok then
				for id, node in query:iter_captures(root, bufnr, 0, -1) do
					local capture_name = query.captures[id]
					if capture_name == "func" or capture_name == "name" then
						local start_row, _, end_row, _ = node:range()
						local name = nil

						-- Try to get name from sibling capture or child
						if capture_name == "func" then
							local name_node = node:field("name")[1]
							if name_node then
								name = vim.treesitter.get_node_text(name_node, bufnr)
							end
						else
							name = vim.treesitter.get_node_text(node, bufnr)
						end

						if name and not vim.tbl_contains(vim.tbl_map(function(f)
							return f.name
						end, result.functions), name) then
							table.insert(result.functions, {
								name = name,
								line = start_row + 1,
								end_line = end_row + 1,
								params = {},
							})
						end
					end
				end
			end
		end

		if queries.classes then
			local query_ok, query = pcall(vim.treesitter.query.parse, lang, queries.classes)
			if query_ok then
				for id, node in query:iter_captures(root, bufnr, 0, -1) do
					local capture_name = query.captures[id]
					if capture_name == "class" then
						local start_row, _, end_row, _ = node:range()
						local name_node = node:field("name")[1]
						local name = name_node and vim.treesitter.get_node_text(name_node, bufnr) or "anonymous"

						table.insert(result.classes, {
							name = name,
							line = start_row + 1,
							end_line = end_row + 1,
							methods = {},
						})
					end
				end
			end
		end

		if queries.exports then
			local query_ok, query = pcall(vim.treesitter.query.parse, lang, queries.exports)
			if query_ok then
				for _, node in query:iter_captures(root, bufnr, 0, -1) do
					local text = vim.treesitter.get_node_text(node, bufnr)
					local start_row, _, _, _ = node:range()

					-- Extract export names (simplified)
					local names = {}
					for name in text:gmatch("export%s+[%w_]+%s+([%w_]+)") do
						table.insert(names, name)
					end
					for name in text:gmatch("export%s*{([^}]+)}") do
						for n in name:gmatch("([%w_]+)") do
							table.insert(names, n)
						end
					end

					for _, name in ipairs(names) do
						table.insert(result.exports, {
							name = name,
							type = "unknown",
							line = start_row + 1,
						})
					end
				end
			end
		end

		if queries.imports then
			local query_ok, query = pcall(vim.treesitter.query.parse, lang, queries.imports)
			if query_ok then
				for _, node in query:iter_captures(root, bufnr, 0, -1) do
					local text = vim.treesitter.get_node_text(node, bufnr)
					local start_row, _, _, _ = node:range()

					-- Extract import source
					local source = text:match('["\']([^"\']+)["\']')
					if source then
						table.insert(result.imports, {
							source = source,
							names = {},
							line = start_row + 1,
						})
					end
				end
			end
		end
	end

	vim.api.nvim_buf_delete(bufnr, { force = true })
	return result
end

--- Generic tree analysis for unsupported languages
---@param root TSNode
---@param bufnr number
---@return table
analyze_tree_generic = function(root, bufnr)
	local result = {
		functions = {},
		classes = {},
		exports = {},
		imports = {},
	}

	local function visit(node)
		local node_type = node:type()

		-- Common function patterns
		if
			node_type:match("function")
			or node_type:match("method")
			or node_type == "arrow_function"
			or node_type == "func_literal"
		then
			local start_row, _, end_row, _ = node:range()
			local name_node = node:field("name")[1]
			local name = name_node and vim.treesitter.get_node_text(name_node, bufnr) or "anonymous"

			table.insert(result.functions, {
				name = name,
				line = start_row + 1,
				end_line = end_row + 1,
				params = {},
			})
		end

		-- Common class patterns
		if node_type:match("class") or node_type == "struct_item" or node_type == "impl_item" then
			local start_row, _, end_row, _ = node:range()
			local name_node = node:field("name")[1]
			local name = name_node and vim.treesitter.get_node_text(name_node, bufnr) or "anonymous"

			table.insert(result.classes, {
				name = name,
				line = start_row + 1,
				end_line = end_row + 1,
				methods = {},
			})
		end

		-- Recurse into children
		for child in node:iter_children() do
			visit(child)
		end
	end

	visit(root)
	return result
end

--- Analyze file using pattern matching (fallback)
---@param content string
---@param lang string
---@return table
local function analyze_with_patterns(content, lang)
	local result = {
		functions = {},
		classes = {},
		exports = {},
		imports = {},
	}

	local lines = vim.split(content, "\n")

	-- Language-specific patterns
	local patterns = {
		lua = {
			func_start = "^%s*local?%s*function%s+([%w_%.]+)",
			func_assign = "^%s*([%w_%.]+)%s*=%s*function",
			module_return = "^return%s+M",
		},
		javascript = {
			func_start = "^%s*function%s+([%w_]+)",
			func_arrow = "^%s*const%s+([%w_]+)%s*=%s*",
			class_start = "^%s*class%s+([%w_]+)",
			export_line = "^%s*export%s+",
			import_line = "^%s*import%s+",
		},
		typescript = {
			func_start = "^%s*function%s+([%w_]+)",
			func_arrow = "^%s*const%s+([%w_]+)%s*=%s*",
			class_start = "^%s*class%s+([%w_]+)",
			export_line = "^%s*export%s+",
			import_line = "^%s*import%s+",
		},
		python = {
			func_start = "^%s*def%s+([%w_]+)",
			class_start = "^%s*class%s+([%w_]+)",
			import_line = "^%s*import%s+",
			from_import = "^%s*from%s+",
		},
		go = {
			func_start = "^func%s+([%w_]+)",
			method_start = "^func%s+%([^%)]+%)%s+([%w_]+)",
			import_line = "^import%s+",
		},
		rust = {
			func_start = "^%s*pub?%s*fn%s+([%w_]+)",
			struct_start = "^%s*pub?%s*struct%s+([%w_]+)",
			impl_start = "^%s*impl%s+([%w_<>]+)",
			use_line = "^%s*use%s+",
		},
	}

	local lang_patterns = patterns[lang] or patterns.javascript

	for i, line in ipairs(lines) do
		-- Functions
		if lang_patterns.func_start then
			local name = line:match(lang_patterns.func_start)
			if name then
				table.insert(result.functions, {
					name = name,
					line = i,
					end_line = i,
					params = {},
				})
			end
		end

		if lang_patterns.func_arrow then
			local name = line:match(lang_patterns.func_arrow)
			if name and line:match("=>") then
				table.insert(result.functions, {
					name = name,
					line = i,
					end_line = i,
					params = {},
				})
			end
		end

		if lang_patterns.func_assign then
			local name = line:match(lang_patterns.func_assign)
			if name then
				table.insert(result.functions, {
					name = name,
					line = i,
					end_line = i,
					params = {},
				})
			end
		end

		if lang_patterns.method_start then
			local name = line:match(lang_patterns.method_start)
			if name then
				table.insert(result.functions, {
					name = name,
					line = i,
					end_line = i,
					params = {},
				})
			end
		end

		-- Classes
		if lang_patterns.class_start then
			local name = line:match(lang_patterns.class_start)
			if name then
				table.insert(result.classes, {
					name = name,
					line = i,
					end_line = i,
					methods = {},
				})
			end
		end

		if lang_patterns.struct_start then
			local name = line:match(lang_patterns.struct_start)
			if name then
				table.insert(result.classes, {
					name = name,
					line = i,
					end_line = i,
					methods = {},
				})
			end
		end

		-- Exports
		if lang_patterns.export_line and line:match(lang_patterns.export_line) then
			local name = line:match("export%s+[%w_]+%s+([%w_]+)")
				or line:match("export%s+default%s+([%w_]+)")
				or line:match("export%s+{%s*([%w_]+)")
			if name then
				table.insert(result.exports, {
					name = name,
					type = "unknown",
					line = i,
				})
			end
		end

		-- Imports
		if lang_patterns.import_line and line:match(lang_patterns.import_line) then
			local source = line:match('["\']([^"\']+)["\']')
			if source then
				table.insert(result.imports, {
					source = source,
					names = {},
					line = i,
				})
			end
		end

		if lang_patterns.from_import and line:match(lang_patterns.from_import) then
			local source = line:match("from%s+([%w_%.]+)")
			if source then
				table.insert(result.imports, {
					source = source,
					names = {},
					line = i,
				})
			end
		end

		if lang_patterns.use_line and line:match(lang_patterns.use_line) then
			local source = line:match("use%s+([%w_:]+)")
			if source then
				table.insert(result.imports, {
					source = source,
					names = {},
					line = i,
				})
			end
		end
	end

	-- For Lua, infer exports from module table
	if lang == "lua" then
		for _, func in ipairs(result.functions) do
			if func.name:match("^M%.") then
				local name = func.name:gsub("^M%.", "")
				table.insert(result.exports, {
					name = name,
					type = "function",
					line = func.line,
				})
			end
		end
	end

	return result
end

--- Analyze a single file
---@param filepath string Full path to file
---@return FileIndex|nil
function M.analyze_file(filepath)
	local content = utils.read_file(filepath)
	if not content then
		return nil
	end

	local lang = scanner.get_language(filepath)

	-- Map to Tree-sitter language names
	local ts_lang_map = {
		typescript = "typescript",
		typescriptreact = "tsx",
		javascript = "javascript",
		javascriptreact = "javascript",
		python = "python",
		go = "go",
		rust = "rust",
		lua = "lua",
	}

	local ts_lang = ts_lang_map[lang] or lang

	-- Try Tree-sitter first
	local analysis = analyze_with_treesitter(filepath, ts_lang, content)

	-- Fallback to pattern matching
	if not analysis then
		analysis = analyze_with_patterns(content, lang)
	end

	return {
		path = filepath,
		language = lang,
		hash = hash_content(content),
		exports = analysis.exports,
		imports = analysis.imports,
		functions = analysis.functions,
		classes = analysis.classes,
		last_indexed = os.time(),
	}
end

--- Extract exports from a buffer
---@param bufnr number
---@return Export[]
function M.extract_exports(bufnr)
	local filepath = vim.api.nvim_buf_get_name(bufnr)
	local analysis = M.analyze_file(filepath)
	return analysis and analysis.exports or {}
end

--- Extract functions from a buffer
---@param bufnr number
---@return FunctionInfo[]
function M.extract_functions(bufnr)
	local filepath = vim.api.nvim_buf_get_name(bufnr)
	local analysis = M.analyze_file(filepath)
	return analysis and analysis.functions or {}
end

--- Extract imports from a buffer
---@param bufnr number
---@return Import[]
function M.extract_imports(bufnr)
	local filepath = vim.api.nvim_buf_get_name(bufnr)
	local analysis = M.analyze_file(filepath)
	return analysis and analysis.imports or {}
end

return M
