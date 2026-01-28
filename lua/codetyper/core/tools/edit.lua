---@mod codetyper.agent.tools.edit File editing tool with fallback matching
---@brief [[
--- Tool for making targeted edits to files using search/replace.
--- Uses shared string_match module for multi-strategy matching.
---@brief ]]

local Base = require("codetyper.core.tools.base")
local path_utils = require("codetyper.support.path")
local string_match = require("codetyper.support.string_match")
local common = require("codetyper.core.tools.common")
local file_ops = require("codetyper.core.tools.file_ops")
local _ok_desc, _agents_edit = pcall(require, "codetyper.prompts.agents.edit")
local description = (_ok_desc and _agents_edit.description) or "[PROMPTS_MOVED_TO_AGENT] Tool descriptions are now managed by the Python agent."
local params = require("codetyper.params.agents.edit").params
local returns = require("codetyper.params.agents.edit").returns

---@class CoderTool
local M = setmetatable({}, Base)

M.name = "edit"
M.description = description
M.params = params
M.returns = returns
M.requires_confirmation = false

---@param input {path: string, old_string: string, new_string: string}
---@param opts CoderToolOpts
---@return boolean|nil result
---@return string|nil error
function M.func(input, opts)
	if not input.path then
		return nil, "path is required"
	end
	if input.old_string == nil then
		return nil, "old_string is required"
	end
	if input.new_string == nil then
		return nil, "new_string is required"
	end

	common.log(opts, "Editing file: " .. input.path)

	local path = path_utils.resolve(input.path)

	-- Normalize inputs
	local old_str = string_match.normalize_line_endings(input.old_string)
	local new_str = string_match.normalize_line_endings(input.new_string)

	-- Handle new file creation (empty old_string)
	if old_str == "" then
		path_utils.ensure_parent_dir(path)

		local lines = vim.split(new_str, "\n", { plain = true })
		local ok = pcall(vim.fn.writefile, lines, path)

		if not ok then
			return nil, "Failed to create file: " .. input.path
		end

		file_ops.post_write_process(path, opts.on_log)
		return common.return_result(opts, true, nil)
	end

	-- Check if file exists
	if vim.fn.filereadable(path) ~= 1 then
		return nil, "File not found: " .. input.path
	end

	-- Read current content
	local lines = vim.fn.readfile(path)
	if not lines then
		return nil, "Failed to read file: " .. input.path
	end

	local content = string_match.normalize_line_endings(table.concat(lines, "\n"))

	-- Find match using shared multi-strategy matching
	local match, strategy = string_match.find_match(content, old_str)

	if not match then
		return nil, "old_string not found in file (tried 5 matching strategies)"
	end

	common.log(opts, "Match found using strategy: " .. strategy)

	-- Perform replacement
	local new_content = content:sub(1, match.start_pos - 1) .. new_str .. content:sub(match.end_pos + 1)

	-- Write back
	local new_lines = vim.split(new_content, "\n", { plain = true })
	local ok = pcall(vim.fn.writefile, new_lines, path)

	if not ok then
		return nil, "Failed to write file: " .. input.path
	end

	file_ops.post_write_process(path, opts.on_log)
	return common.return_result(opts, true, nil)
end

return M
