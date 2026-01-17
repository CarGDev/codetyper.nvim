---@mod codetyper.executor.file_ops File operations for plan execution
---@brief [[
--- Pure file operations. No validation (agent already validated).
--- All operations are atomic where possible.
---@brief ]]

local M = {}

--- Read file content
---@param path string File path
---@return string|nil content
---@return string|nil error
function M.read_file(path)
	local full_path = vim.fn.expand(path)
	if not vim.startswith(full_path, "/") then
		full_path = vim.fn.getcwd() .. "/" .. full_path
	end

	local stat = vim.uv.fs_stat(full_path)
	if not stat then
		return nil, "File not found: " .. path
	end

	if stat.type == "directory" then
		return nil, "Path is a directory: " .. path
	end

	local lines = vim.fn.readfile(full_path)
	if not lines then
		return nil, "Failed to read: " .. path
	end

	return table.concat(lines, "\n"), nil
end

--- Write content to file
---@param path string File path
---@param content string Content to write
---@return boolean success
---@return string|nil error
function M.write_file(path, content)
	local full_path = vim.fn.expand(path)
	if not vim.startswith(full_path, "/") then
		full_path = vim.fn.getcwd() .. "/" .. full_path
	end

	-- Ensure parent directory exists
	local dir = vim.fn.fnamemodify(full_path, ":h")
	if vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, "p")
	end

	-- Write file
	local lines = vim.split(content, "\n", { plain = true })
	local ok = pcall(vim.fn.writefile, lines, full_path)

	if not ok then
		return false, "Failed to write: " .. path
	end

	-- Reload buffer if open
	M.reload_buffer(full_path)

	return true, nil
end

--- Edit file by replacing old_string with new_string
---@param path string File path
---@param old_string string Text to find
---@param new_string string Text to replace with
---@return boolean success
---@return string|nil error
function M.edit_file(path, old_string, new_string)
	local content, err = M.read_file(path)
	if not content then
		return false, err
	end

	-- Handle new file creation (empty old_string)
	if old_string == "" then
		return M.write_file(path, new_string)
	end

	-- Try exact match first
	local new_content, count = content:gsub(old_string, new_string, 1)

	if count == 0 then
		-- Try with normalized whitespace
		local norm_old = old_string:gsub("%s+", " ")
		local norm_content = content:gsub("%s+", " ")
		if norm_content:find(norm_old, 1, true) then
			-- Found with normalized whitespace - try line-by-line
			local old_lines = vim.split(old_string, "\n", { plain = true })
			local content_lines = vim.split(content, "\n", { plain = true })

			-- Find start line
			for i = 1, #content_lines - #old_lines + 1 do
				local match = true
				for j = 1, #old_lines do
					local content_trimmed = content_lines[i + j - 1]:match("^%s*(.-)%s*$")
					local old_trimmed = old_lines[j]:match("^%s*(.-)%s*$")
					if content_trimmed ~= old_trimmed then
						match = false
						break
					end
				end
				if match then
					-- Replace the block
					local new_lines = vim.split(new_string, "\n", { plain = true })
					local result_lines = {}
					for k = 1, i - 1 do
						table.insert(result_lines, content_lines[k])
					end
					for _, line in ipairs(new_lines) do
						table.insert(result_lines, line)
					end
					for k = i + #old_lines, #content_lines do
						table.insert(result_lines, content_lines[k])
					end
					new_content = table.concat(result_lines, "\n")
					count = 1
					break
				end
			end
		end
	end

	if count == 0 then
		return false, "old_string not found in file"
	end

	return M.write_file(path, new_content)
end

--- Delete a file
---@param path string File path
---@return boolean success
---@return string|nil error
function M.delete_file(path)
	local full_path = vim.fn.expand(path)
	if not vim.startswith(full_path, "/") then
		full_path = vim.fn.getcwd() .. "/" .. full_path
	end

	-- Close buffer if open
	M.close_buffer(full_path)

	local ok, err = os.remove(full_path)
	if not ok then
		return false, "Failed to delete: " .. (err or "unknown error")
	end

	return true, nil
end

--- Ensure directory exists
---@param path string Directory path
---@return boolean success
---@return string|nil error
function M.ensure_dir(path)
	local full_path = vim.fn.expand(path)
	if not vim.startswith(full_path, "/") then
		full_path = vim.fn.getcwd() .. "/" .. full_path
	end

	if vim.fn.isdirectory(full_path) == 1 then
		return true, nil
	end

	local ok = pcall(vim.fn.mkdir, full_path, "p")
	if not ok then
		return false, "Failed to create directory: " .. path
	end

	return true, nil
end

--- Execute a shell command
---@param command string Command to execute
---@param timeout? number Timeout in ms (default 30000)
---@return string|nil output
---@return string|nil error
function M.execute_command(command, timeout)
	timeout = timeout or 30000

	local Job = require("plenary.job")
	local job = Job:new({
		command = "bash",
		args = { "-c", command },
		cwd = vim.fn.getcwd(),
	})

	job:sync(timeout)
	local exit_code = job.code or 0
	local output = table.concat(job:result() or {}, "\n")
	local stderr = table.concat(job:stderr_result() or {}, "\n")

	if stderr and stderr ~= "" then
		output = output .. "\n" .. stderr
	end

	if exit_code ~= 0 then
		return nil, string.format("Command failed (exit %d): %s", exit_code, output)
	end

	return output, nil
end

--- Reload a buffer if it's open
---@param path string Full file path
function M.reload_buffer(path)
	vim.schedule(function()
		local bufnr = vim.fn.bufnr(path)
		if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
			vim.api.nvim_buf_call(bufnr, function()
				vim.cmd("silent! edit!")
			end)
		end
	end)
end

--- Close a buffer if it's open
---@param path string Full file path
function M.close_buffer(path)
	local bufnr = vim.fn.bufnr(path)
	if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
		pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
	end
end

return M
