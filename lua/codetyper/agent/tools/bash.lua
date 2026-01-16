---@mod codetyper.agent.tools.bash Shell command execution tool
---@brief [[
--- Tool for executing shell commands with safety checks.
---@brief ]]

local Base = require("codetyper.agent.tools.base")

---@class CoderTool
local M = setmetatable({}, Base)

M.name = "bash"

M.description = [[Executes a bash command in a shell.

IMPORTANT RULES:
- Do NOT use bash to read files (use 'view' tool instead)
- Do NOT use bash to modify files (use 'write' or 'edit' tools instead)
- Do NOT use interactive commands (vim, nano, less, etc.)
- Commands timeout after 2 minutes by default

Allowed uses:
- Running builds (make, npm run build, cargo build)
- Running tests (npm test, pytest, cargo test)
- Git operations (git status, git diff, git commit)
- Package management (npm install, pip install)
- System info commands (ls, pwd, which)]]

M.params = {
	{
		name = "command",
		description = "The shell command to execute",
		type = "string",
	},
	{
		name = "cwd",
		description = "Working directory for the command (optional)",
		type = "string",
		optional = true,
	},
	{
		name = "timeout",
		description = "Timeout in milliseconds (default: 120000)",
		type = "integer",
		optional = true,
	},
}

M.returns = {
	{
		name = "stdout",
		description = "Command output",
		type = "string",
	},
	{
		name = "error",
		description = "Error message if command failed",
		type = "string",
		optional = true,
	},
}

M.requires_confirmation = true

--- Banned commands for safety
local BANNED_COMMANDS = {
	"rm -rf /",
	"rm -rf /*",
	"dd if=/dev/zero",
	"mkfs",
	":(){ :|:& };:",
	"> /dev/sda",
}

--- Banned patterns
local BANNED_PATTERNS = {
	"curl.*|.*sh",
	"wget.*|.*sh",
	"rm%s+%-rf%s+/",
}

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
	if not input.command then
		return nil, "command is required"
	end

	-- Safety check
	local safe, reason = is_safe_command(input.command)
	if not safe then
		return nil, reason
	end

	-- Confirmation required
	if M.requires_confirmation and opts.confirm then
		local confirmed = false
		local confirm_error = nil

		opts.confirm("Execute command: " .. input.command, function(ok)
			if not ok then
				confirm_error = "User declined command execution"
			end
			confirmed = ok
		end)

		-- Wait for confirmation (in async context, this would be handled differently)
		if confirm_error then
			return nil, confirm_error
		end
	end

	-- Log the operation
	if opts.on_log then
		opts.on_log("Executing: " .. input.command)
	end

	-- Prepare command
	local cwd = input.cwd or vim.fn.getcwd()
	local timeout = input.timeout or 120000

	-- Execute command
	local output = ""
	local exit_code = 0

	local job_opts = {
		command = "bash",
		args = { "-c", input.command },
		cwd = cwd,
		on_stdout = function(_, data)
			if data then
				output = output .. table.concat(data, "\n")
			end
		end,
		on_stderr = function(_, data)
			if data then
				output = output .. table.concat(data, "\n")
			end
		end,
		on_exit = function(_, code)
			exit_code = code
		end,
	}

	-- Run synchronously with timeout
	local Job = require("plenary.job")
	local job = Job:new(job_opts)

	job:sync(timeout)
	exit_code = job.code or 0
	output = table.concat(job:result() or {}, "\n")

	-- Also get stderr
	local stderr = table.concat(job:stderr_result() or {}, "\n")
	if stderr and stderr ~= "" then
		output = output .. "\n" .. stderr
	end

	-- Check result
	if exit_code ~= 0 then
		local error_msg = string.format("Command failed with exit code %d: %s", exit_code, output)
		if opts.on_complete then
			opts.on_complete(nil, error_msg)
		end
		return nil, error_msg
	end

	if opts.on_complete then
		opts.on_complete(output, nil)
	end

	return output, nil
end

return M
