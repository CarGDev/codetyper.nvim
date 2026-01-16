---@mod codetyper.agent.tools.write File writing tool
---@brief [[
--- Tool for creating or overwriting files.
---@brief ]]

local Base = require("codetyper.agent.tools.base")
local description = require("codetyper.prompts.agents.write").description
local params = require("codetyper.params.agents.write")

---@class CoderTool
local M = setmetatable({}, Base)

M.name = "write"
M.description = description
M.params = params.params
M.returns = params.returns

M.requires_confirmation = true

---@param input {path: string, content: string}
---@param opts CoderToolOpts
---@return boolean|nil result
---@return string|nil error
function M.func(input, opts)
	if not input.path then
		return nil, "path is required"
	end
	if not input.content then
		return nil, "content is required"
	end

	-- Log the operation
	if opts.on_log then
		opts.on_log("Writing file: " .. input.path)
	end

	-- Resolve path
	local path = input.path
	if not vim.startswith(path, "/") then
		path = vim.fn.getcwd() .. "/" .. path
	end

	-- Create parent directories
	local dir = vim.fn.fnamemodify(path, ":h")
	if vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, "p")
	end

	-- Write the file
	local lines = vim.split(input.content, "\n", { plain = true })
	local ok = pcall(vim.fn.writefile, lines, path)

	if not ok then
		return nil, "Failed to write file: " .. path
	end

	-- Reload buffer if open
	local bufnr = vim.fn.bufnr(path)
	if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
		vim.api.nvim_buf_call(bufnr, function()
			vim.cmd("edit!")
		end)
	end

	if opts.on_complete then
		opts.on_complete(true, nil)
	end

	return true, nil
end

return M
