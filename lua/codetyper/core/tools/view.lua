---@mod codetyper.agent.tools.view File viewing tool
---@brief [[
--- Tool for reading file contents with line range support.
---@brief ]]

local Base = require("codetyper.core.tools.base")
local path_utils = require("codetyper.support.path")
local common = require("codetyper.core.tools.common")

---@class CoderTool
local M = setmetatable({}, Base)

M.name = "view"

local params = require("codetyper.params.agents.view")
local description = require("codetyper.prompts.agents.view").description

M.description = description
M.params = params.params
M.returns = params.returns

M.requires_confirmation = false

--- Maximum content size before truncation
local MAX_CONTENT_SIZE = 200 * 1024 -- 200KB

---@param input {path: string, start_line?: integer, end_line?: integer}
---@param opts CoderToolOpts
---@return string|nil result
---@return string|nil error
function M.func(input, opts)
	local valid, err = common.validate_required(input, { "path" })
	if not valid then
		return nil, err
	end

	common.log(opts, "Reading file: " .. input.path)

	-- Resolve path
	local path = path_utils.resolve(input.path)

	-- Check if file exists
	local stat = path_utils.stat(input.path)
	if not stat then
		return nil, "File not found: " .. input.path
	end

	if stat.type == "directory" then
		return nil, "Path is a directory: " .. input.path
	end

	-- Read file
	local lines = vim.fn.readfile(path)
	if not lines then
		return nil, "Failed to read file: " .. input.path
	end

	-- Apply line range
	local start_line = input.start_line or 1
	local end_line = input.end_line or #lines

	start_line = math.max(1, start_line)
	end_line = math.min(#lines, end_line)

	local total_lines = #lines
	local selected_lines = {}

	for i = start_line, end_line do
		table.insert(selected_lines, lines[i])
	end

	-- Check for truncation
	local content = table.concat(selected_lines, "\n")
	local is_truncated = false

	if #content > MAX_CONTENT_SIZE then
		-- Truncate content
		local truncated_lines = {}
		local size = 0

		for _, line in ipairs(selected_lines) do
			size = size + #line + 1
			if size > MAX_CONTENT_SIZE then
				is_truncated = true
				break
			end
			table.insert(truncated_lines, line)
		end

		content = table.concat(truncated_lines, "\n")
	end

	-- Return as JSON
	local result = common.json_result({
		content = content,
		total_line_count = total_lines,
		is_truncated = is_truncated,
		start_line = start_line,
		end_line = end_line,
	})

	return common.return_result(opts, result, nil)
end

return M
