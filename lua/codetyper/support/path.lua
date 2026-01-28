---@mod codetyper.support.path Path resolution utilities
---@brief [[
--- Shared utilities for resolving and normalizing file paths.
--- Consolidates duplicate path resolution patterns across the codebase.
---@brief ]]

local M = {}

--- Resolve a path to absolute, expanding user paths and relative paths
---@param path string File or directory path
---@param base_dir? string Base directory for relative paths (default: vim.fn.getcwd())
---@return string Absolute path
function M.resolve(path, base_dir)
	if not path then
		return ""
	end

	-- First expand user paths (~)
	local expanded = vim.fn.expand(path)

	-- If already absolute, return as-is
	if vim.startswith(expanded, "/") then
		return expanded
	end

	-- Resolve relative path from base directory
	local base = base_dir or vim.fn.getcwd()
	return base .. "/" .. expanded
end

--- Check if a path is absolute
---@param path string
---@return boolean
function M.is_absolute(path)
	return vim.startswith(path or "", "/")
end

--- Make a path relative to a base directory
---@param path string Absolute path
---@param base_dir? string Base directory (default: vim.fn.getcwd())
---@return string Relative path
function M.make_relative(path, base_dir)
	local base = base_dir or vim.fn.getcwd()
	if vim.startswith(path, base .. "/") then
		return path:sub(#base + 2)
	end
	return path
end

--- Get file stat info (wrapper around vim.uv.fs_stat)
---@param path string
---@return table|nil stat
function M.stat(path)
	local full_path = M.resolve(path)
	return vim.uv.fs_stat(full_path)
end

--- Check if path exists
---@param path string
---@return boolean
function M.exists(path)
	return M.stat(path) ~= nil
end

--- Check if path is a file
---@param path string
---@return boolean
function M.is_file(path)
	local stat = M.stat(path)
	return stat ~= nil and stat.type == "file"
end

--- Check if path is a directory
---@param path string
---@return boolean
function M.is_directory(path)
	local stat = M.stat(path)
	return stat ~= nil and stat.type == "directory"
end

--- Get the parent directory of a path
---@param path string
---@return string
function M.parent(path)
	return vim.fn.fnamemodify(path, ":h")
end

--- Get the filename from a path
---@param path string
---@return string
function M.filename(path)
	return vim.fn.fnamemodify(path, ":t")
end

--- Get the file extension
---@param path string
---@return string
function M.extension(path)
	return vim.fn.fnamemodify(path, ":e")
end

--- Ensure parent directory exists
---@param path string File path
---@return boolean success
function M.ensure_parent_dir(path)
	local full_path = M.resolve(path)
	local dir = M.parent(full_path)
	if vim.fn.isdirectory(dir) == 0 then
		return vim.fn.mkdir(dir, "p") == 1
	end
	return true
end

--- Normalize path separators and remove redundant parts
---@param path string
---@return string
function M.normalize(path)
	-- Remove double slashes
	local normalized = path:gsub("//+", "/")
	-- Remove trailing slash unless it's root
	if #normalized > 1 and normalized:sub(-1) == "/" then
		normalized = normalized:sub(1, -2)
	end
	return normalized
end

--- Join path components
---@param ... string Path components
---@return string
function M.join(...)
	local parts = { ... }
	local result = table.concat(parts, "/")
	return M.normalize(result)
end

return M
