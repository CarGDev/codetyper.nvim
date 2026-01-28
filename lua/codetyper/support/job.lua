---@mod codetyper.support.job Plenary.job execution utilities
---@brief [[
--- Shared utilities for executing shell commands via plenary.job.
--- Consolidates duplicate job execution patterns across tools.
---@brief ]]

local M = {}

---@class JobResult
---@field stdout string[] Array of stdout lines
---@field stderr string[] Array of stderr lines
---@field output string Combined stdout as single string
---@field error_output string Combined stderr as single string
---@field exit_code number Exit code
---@field success boolean Whether command succeeded (exit_code == 0)

---@class JobOpts
---@field command string Command to execute
---@field args? string[] Command arguments
---@field cwd? string Working directory (default: vim.fn.getcwd())
---@field timeout? number Timeout in ms (default: 30000)
---@field env? table<string, string> Environment variables

--- Execute a command synchronously via plenary.job
---@param opts JobOpts
---@return JobResult
function M.run(opts)
	local Job = require("plenary.job")

	local cwd = opts.cwd or vim.fn.getcwd()
	local timeout = opts.timeout or 30000

	local job = Job:new({
		command = opts.command,
		args = opts.args or {},
		cwd = cwd,
		env = opts.env,
	})

	job:sync(timeout)

	local stdout = job:result() or {}
	local stderr = job:stderr_result() or {}
	local exit_code = job.code or 0

	return {
		stdout = stdout,
		stderr = stderr,
		output = table.concat(stdout, "\n"),
		error_output = table.concat(stderr, "\n"),
		exit_code = exit_code,
		success = exit_code == 0,
	}
end

--- Execute a bash command synchronously
---@param command string Shell command to execute
---@param opts? {cwd?: string, timeout?: number}
---@return string|nil output Output on success
---@return string|nil error Error message on failure
function M.bash(command, opts)
	opts = opts or {}

	local result = M.run({
		command = "bash",
		args = { "-c", command },
		cwd = opts.cwd,
		timeout = opts.timeout or 120000,
	})

	-- Combine stdout and stderr
	local output = result.output
	if result.error_output and result.error_output ~= "" then
		if output ~= "" then
			output = output .. "\n" .. result.error_output
		else
			output = result.error_output
		end
	end

	if not result.success then
		return nil, string.format("Command failed (exit %d): %s", result.exit_code, output)
	end

	return output, nil
end

--- Execute ripgrep search
---@param pattern string Search pattern
---@param path string Search path
---@param opts? {max_results?: number, include?: string, timeout?: number}
---@return table[] matches Array of {file: string, line_number: number, content: string}
---@return string|nil error
function M.ripgrep(pattern, path, opts)
	opts = opts or {}
	local max_results = opts.max_results or 50

	-- Check if ripgrep is available
	if vim.fn.executable("rg") ~= 1 then
		return {}, "ripgrep (rg) is not installed"
	end

	local args = {
		"--json",
		"--max-count",
		tostring(max_results),
		"--no-heading",
	}

	if opts.include then
		table.insert(args, "--glob")
		table.insert(args, opts.include)
	end

	table.insert(args, pattern)
	table.insert(args, path)

	local result = M.run({
		command = "rg",
		args = args,
		timeout = opts.timeout or 30000,
	})

	local matches = {}
	for _, line in ipairs(result.stdout) do
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

	return matches, nil
end

--- Execute fd file finder
---@param pattern string Glob pattern
---@param base_path string Search base path
---@param opts? {max_results?: number, timeout?: number}
---@return string[] files Array of matching file paths
---@return string|nil error
function M.fd(pattern, base_path, opts)
	opts = opts or {}
	local max_results = opts.max_results or 100

	if vim.fn.executable("fd") ~= 1 then
		return {}, "fd is not installed"
	end

	local result = M.run({
		command = "fd",
		args = {
			"--type",
			"f",
			"--max-results",
			tostring(max_results),
			"--glob",
			pattern,
			base_path,
		},
		cwd = base_path,
		timeout = opts.timeout or 30000,
	})

	local files = {}
	for _, line in ipairs(result.stdout) do
		if line and line ~= "" then
			table.insert(files, line)
		end
	end

	return files, nil
end

return M
