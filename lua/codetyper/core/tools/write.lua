---@mod codetyper.agent.tools.write File writing tool
---@brief [[
--- Tool for creating or overwriting files.
---@brief ]]

local Base = require("codetyper.core.tools.base")
local path_utils = require("codetyper.support.path")
local common = require("codetyper.core.tools.common")
local file_ops = require("codetyper.core.tools.file_ops")
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
	local valid, err = common.validate_required(input, { "path", "content" })
	if not valid then
		return nil, err
	end

	common.log(opts, "Writing file: " .. input.path)

	local path = path_utils.resolve(input.path)

	-- Create parent directories
	path_utils.ensure_parent_dir(path)

	-- Write the file
	local lines = vim.split(input.content, "\n", { plain = true })
	local ok = pcall(vim.fn.writefile, lines, path)

	if not ok then
		return nil, "Failed to write file: " .. path
	end

	-- Post-write processing: lint, format, save
	file_ops.post_write_process(path, opts.on_log)

	return common.return_result(opts, true, nil)
end

return M
