---@mod codetyper.support.imports Import/dependency resolver for attached files
---
--- Parses imports from source files and resolves them to actual file paths.

local M = {}

local utils = require("codetyper.support.utils")

--- Common import patterns for different languages
local import_patterns = {
	-- JavaScript/TypeScript: import X from './path' or import './path'
	js = {
		'import%s+[^"\']*["\']([^"\']+)["\']',
		'import%s*%(["\']([^"\']+)["\']%)',
		'require%s*%(["\']([^"\']+)["\']%)',
		'from%s+["\']([^"\']+)["\']',
	},
	-- Lua: require("path") or require("path.subpath")
	lua = {
		'require%s*%(?["\']([^"\']+)["\']%)?',
	},
	-- Python: import X, from X import Y
	python = {
		"^import%s+([%w_.]+)",
		"^from%s+([%w_.]+)%s+import",
	},
	-- Go: import "path" or import ( "path" )
	go = {
		'import%s+["\']([^"\']+)["\']',
		'["\']([^"\']+)["\']', -- Inside import blocks
	},
	-- Rust: use crate::path or mod path
	rust = {
		"use%s+([%w_:]+)",
		"mod%s+([%w_]+)",
	},
	-- CSS/SCSS: @import 'path'
	css = {
		'@import%s+["\']([^"\']+)["\']',
		'@import%s+url%(["\']?([^"\'%)]+)["\']?%)',
	},
}

--- Map file extensions to language
local ext_to_lang = {
	js = "js",
	jsx = "js",
	ts = "js",
	tsx = "js",
	mjs = "js",
	cjs = "js",
	vue = "js",
	svelte = "js",
	lua = "lua",
	py = "python",
	go = "go",
	rs = "rust",
	css = "css",
	scss = "css",
	sass = "css",
	less = "css",
}

--- Check if an import path is relative (starts with . or ..)
---@param path string Import path
---@return boolean
local function is_relative_import(path)
	return path:match("^%.") ~= nil
end

--- Check if an import path is a local project import (not from node_modules etc)
---@param path string Import path
---@param lang string Language
---@return boolean
local function is_local_import(path, lang)
	-- Skip node_modules, external packages
	if path:match("^@?[%w%-]+$") and lang == "js" then
		-- Bare import like 'react' or '@org/package'
		return false
	end
	if path:match("^node_modules") then
		return false
	end
	-- For JS, relative imports are always local
	if lang == "js" and is_relative_import(path) then
		return true
	end
	-- For Lua, check if it starts with project prefix
	if lang == "lua" then
		-- Assume project-local if it matches common patterns
		return not path:match("^vim%.") and not path:match("^plenary%.")
	end
	return is_relative_import(path)
end

--- Resolve a relative import path to an absolute file path
---@param import_path string The import path
---@param source_file string The file containing the import
---@param lang string The language
---@return string|nil Resolved absolute path or nil
local function resolve_import_path(import_path, source_file, lang)
	local source_dir = vim.fn.fnamemodify(source_file, ":h")
	local project_root = utils.get_project_root() or vim.fn.getcwd()

	if lang == "js" then
		-- Handle relative imports
		if is_relative_import(import_path) then
			local base_path = source_dir .. "/" .. import_path

			-- Try different extensions
			local extensions = { "", ".ts", ".tsx", ".js", ".jsx", ".mjs", "/index.ts", "/index.tsx", "/index.js" }
			for _, ext in ipairs(extensions) do
				local full_path = vim.fn.fnamemodify(base_path .. ext, ":p")
				if vim.fn.filereadable(full_path) == 1 then
					return full_path
				end
			end
		else
			-- Alias imports like @/components - try common patterns
			if import_path:match("^@/") or import_path:match("^~/") then
				local alias_path = import_path:gsub("^[@~]/", "")
				local try_paths = {
					project_root .. "/src/" .. alias_path,
					project_root .. "/" .. alias_path,
				}
				local extensions = { "", ".ts", ".tsx", ".js", ".jsx", "/index.ts", "/index.tsx", "/index.js" }
				for _, base in ipairs(try_paths) do
					for _, ext in ipairs(extensions) do
						local full_path = vim.fn.fnamemodify(base .. ext, ":p")
						if vim.fn.filereadable(full_path) == 1 then
							return full_path
						end
					end
				end
			end
		end
	elseif lang == "lua" then
		-- Convert dot notation to path
		local path_part = import_path:gsub("%.", "/")
		local try_paths = {
			project_root .. "/lua/" .. path_part .. ".lua",
			project_root .. "/lua/" .. path_part .. "/init.lua",
			project_root .. "/" .. path_part .. ".lua",
		}
		for _, try_path in ipairs(try_paths) do
			local full_path = vim.fn.fnamemodify(try_path, ":p")
			if vim.fn.filereadable(full_path) == 1 then
				return full_path
			end
		end
	elseif lang == "python" then
		-- Convert dot notation to path
		local path_part = import_path:gsub("%.", "/")
		local try_paths = {
			source_dir .. "/" .. path_part .. ".py",
			source_dir .. "/" .. path_part .. "/__init__.py",
			project_root .. "/" .. path_part .. ".py",
			project_root .. "/src/" .. path_part .. ".py",
		}
		for _, try_path in ipairs(try_paths) do
			local full_path = vim.fn.fnamemodify(try_path, ":p")
			if vim.fn.filereadable(full_path) == 1 then
				return full_path
			end
		end
	end

	return nil
end

--- Extract imports from file content
---@param content string File content
---@param lang string Language identifier
---@return string[] List of import paths
local function extract_imports(content, lang)
	local imports = {}
	local patterns = import_patterns[lang]

	if not patterns then
		return imports
	end

	for line in content:gmatch("[^\n]+") do
		for _, pattern in ipairs(patterns) do
			local match = line:match(pattern)
			if match then
				-- Clean up the match
				match = match:gsub("^%s+", ""):gsub("%s+$", "")
				if match ~= "" and is_local_import(match, lang) then
					table.insert(imports, match)
				end
			end
		end
	end

	-- Remove duplicates
	local seen = {}
	local unique = {}
	for _, imp in ipairs(imports) do
		if not seen[imp] then
			seen[imp] = true
			table.insert(unique, imp)
		end
	end

	return unique
end

--- Parse a file and find all its local imports
---@param filepath string Path to the file
---@return table[] List of {path, resolved_path, content} for each import
function M.find_imports(filepath)
	local content = utils.read_file(filepath)
	if not content then
		return {}
	end

	local ext = vim.fn.fnamemodify(filepath, ":e"):lower()
	local lang = ext_to_lang[ext]

	if not lang then
		return {}
	end

	local import_paths = extract_imports(content, lang)
	local resolved = {}

	for _, import_path in ipairs(import_paths) do
		local resolved_path = resolve_import_path(import_path, filepath, lang)
		if resolved_path then
			local import_content = utils.read_file(resolved_path)
			if import_content then
				table.insert(resolved, {
					import_path = import_path,
					resolved_path = resolved_path,
					filename = vim.fn.fnamemodify(resolved_path, ":t"),
					content = import_content,
				})
			end
		end
	end

	return resolved
end

--- Recursively find all imports from a file (with depth limit)
---@param filepath string Starting file path
---@param max_depth? number Maximum recursion depth (default 2)
---@param max_files? number Maximum total files (default 20)
---@return table Dictionary of resolved_path -> {import_path, content, filename, depth}
function M.find_imports_recursive(filepath, max_depth, max_files)
	max_depth = max_depth or 2
	max_files = max_files or 20

	local all_imports = {}
	local visited = {}
	local count = 0

	local function recurse(file, depth)
		if depth > max_depth or count >= max_files then
			return
		end

		if visited[file] then
			return
		end
		visited[file] = true

		local imports = M.find_imports(file)
		for _, imp in ipairs(imports) do
			if not all_imports[imp.resolved_path] and count < max_files then
				count = count + 1
				all_imports[imp.resolved_path] = {
					import_path = imp.import_path,
					filename = imp.filename,
					content = imp.content,
					depth = depth,
				}
				-- Recurse into this import
				recurse(imp.resolved_path, depth + 1)
			end
		end
	end

	recurse(filepath, 1)
	return all_imports
end

--- Build expanded context from attached files (includes their imports)
---@param files table Dictionary of filename -> filepath
---@return string Context string with all files and their imports
---@return number Total file count
function M.build_expanded_context(files)
	local context = ""
	local file_count = 0
	local included = {}

	for filename, filepath in pairs(files) do
		-- Skip if already included
		if included[filepath] then
			goto continue
		end

		local content = utils.read_file(filepath)
		if content and content ~= "" then
			included[filepath] = true
			file_count = file_count + 1

			local ext = vim.fn.fnamemodify(filepath, ":e")
			context = context .. "\n\n=== FILE: " .. filename .. " ===\n"
			context = context .. "Path: " .. filepath .. "\n"
			context = context .. "```" .. (ext or "text") .. "\n" .. content .. "\n```\n"

			-- Find and include imports
			local imports = M.find_imports_recursive(filepath, 2, 15)
			if next(imports) then
				context = context .. "\n--- IMPORTED BY " .. filename .. " ---\n"
				for imp_path, imp_data in pairs(imports) do
					if not included[imp_path] then
						included[imp_path] = true
						file_count = file_count + 1

						local imp_ext = vim.fn.fnamemodify(imp_path, ":e")
						context = context .. "\n--- " .. imp_data.filename .. " (imported as '" .. imp_data.import_path .. "') ---\n"
						context = context .. "Path: " .. imp_path .. "\n"
						context = context .. "```" .. (imp_ext or "text") .. "\n" .. imp_data.content .. "\n```\n"
					end
				end
			end
		end

		::continue::
	end

	return context, file_count
end

return M
