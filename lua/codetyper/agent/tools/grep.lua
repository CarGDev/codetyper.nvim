---@mod codetyper.agent.tools.grep Search tool
---@brief [[
--- Tool for searching file contents using ripgrep.
---@brief ]]

local Base = require("codetyper.agent.tools.base")
local description = require("codetyper.params.agent.grep").description
local params = require("codetyper.prompts.agents.grep").params
local returns = require("codetyper.prompts.agents.grep").returns

---@class CoderTool
local M = setmetatable({}, Base)

M.name = "grep"
M.description = description
M.params = params
M.returns = returns

M.requires_confirmation = false

---@param input {pattern: string, path?: string, include?: string, max_results?: integer}
---@param opts CoderToolOpts
---@return string|nil result
---@return string|nil error
function M.func(input, opts)
	if not input.pattern then
		return nil, "pattern is required"
	end

	-- Log the operation
	if opts.on_log then
		opts.on_log("Searching for: " .. input.pattern)
	end

	-- Build ripgrep command
	local path = input.path or vim.fn.getcwd()
	local max_results = input.max_results or 50

	-- Resolve path
	if not vim.startswith(path, "/") then
		path = vim.fn.getcwd() .. "/" .. path
	end

	-- Check if ripgrep is available
	if vim.fn.executable("rg") ~= 1 then
		return nil, "ripgrep (rg) is not installed"
	end

	-- Build command args
	local args = {
		"--json",
		"--max-count",
		tostring(max_results),
		"--no-heading",
	}

	if input.include then
		table.insert(args, "--glob")
		table.insert(args, input.include)
	end

	table.insert(args, input.pattern)
	table.insert(args, path)

	-- Execute ripgrep
	local Job = require("plenary.job")
	local job = Job:new({
		command = "rg",
		args = args,
		cwd = vim.fn.getcwd(),
	})

	job:sync(30000) -- 30 second timeout

	local results = job:result() or {}
	local matches = {}

	-- Parse JSON output
	for _, line in ipairs(results) do
		if line and line ~= "" then
			local ok, parsed = pcall(vim.json.decode, line)
			if ok and parsed.type == "match" then
				local data = parsed.data
				table.insert(matches, {
					file = data.path.text,
					line_number = data.line_number,
					content = data.lines.text:gsub("\n$", ""),
				})
			end
		end
	end

	-- Return as JSON
	local result = vim.json.encode({
		matches = matches,
		total = #matches,
		truncated = #matches >= max_results,
	})

	if opts.on_complete then
		opts.on_complete(result, nil)
	end

	return result, nil
end

return M
