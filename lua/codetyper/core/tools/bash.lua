---@mod codetyper.agent.tools.bash Shell command execution tool
---@brief [[
--- Tool for executing shell commands with safety checks.
---@brief ]]

local Base = require("codetyper.core.tools.base")
local job_utils = require("codetyper.support.job")
local common = require("codetyper.core.tools.common")

local description = require("codetyper.prompts.agents.bash").description
local params = require("codetyper.params.agents.bash").params
local returns = require("codetyper.params.agents.bash").returns
local BANNED_COMMANDS = require("codetyper.commands.agents.banned").BANNED_COMMANDS
local BANNED_PATTERNS = require("codetyper.commands.agents.banned").BANNED_PATTERNS

---@class CoderTool
local M = setmetatable({}, Base)

M.name = "bash"
M.description = description
M.params = params
M.returns = returns
M.requires_confirmation = true

--- Check if command is safe
---@param command string
---@return boolean safe
---@return string|nil reason
local function is_safe_command(command)
	-- Check exact matches
	for _, banned in ipairs(BANNED_COMMANDS) do
		if command == banned then
			return false, "Command is banned for safety"
		end
	end

	-- Check patterns
	for _, pattern in ipairs(BANNED_PATTERNS) do
		if command:match(pattern) then
			return false, "Command matches banned pattern"
		end
	end

	return true
end

---@param input {command: string, cwd?: string, timeout?: integer}
---@param opts CoderToolOpts
---@return string|nil result
---@return string|nil error
function M.func(input, opts)
	local valid, err = common.validate_required(input, { "command" })
	if not valid then
		return nil, err
	end

	-- Safety check
	local safe, reason = is_safe_command(input.command)
	if not safe then
		return nil, reason
	end

	-- Confirmation required
	if M.requires_confirmation and opts.confirm then
		local confirm_error = nil

		opts.confirm("Execute command: " .. input.command, function(ok)
			if not ok then
				confirm_error = "User declined command execution"
			end
		end)

		if confirm_error then
			return nil, confirm_error
		end
	end

	common.log(opts, "Executing: " .. input.command)

	local output, bash_err = job_utils.bash(input.command, {
		cwd = input.cwd,
		timeout = input.timeout,
	})

	if bash_err then
		return common.return_result(opts, nil, bash_err)
	end

	return common.return_result(opts, output, nil)
end

return M
