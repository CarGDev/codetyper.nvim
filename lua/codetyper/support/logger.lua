---@mod codetyper.support.logger Structured logging utility for Codetyper.nvim

local M = {}

-- Get the codetyper logger instance
local logger = nil

local function get_logger()
	if logger then
		return logger
	end
	
	-- Try to get codetyper module for config
	local ok, codetyper = pcall(require, "codetyper")
	local config = {}
	if ok and codetyper.get_config then
		config = codetyper.get_config() or {}
	end
	
	-- Use ~/.config/nvim/logs/ directory
	local log_dir = vim.fn.expand("~/.config/nvim/logs")
	vim.fn.mkdir(log_dir, "p")
	
	logger = {
		debug_enabled = config.debug_logging or false,
		log_file = config.log_file or log_dir .. "/codetyper.log",
	}
	
	return logger
end

--- Get current timestamp
---@return string timestamp ISO 8601 format
local function get_timestamp()
	return os.date("%Y-%m-%d %H:%M:%S")
end

--- Get calling function info
---@return string caller_info
local function get_caller_info()
	local info = debug.getinfo(3, "Sn")
	if not info then
		return "unknown"
	end
	
	local name = info.name or "anonymous"
	local source = info.source and info.source:gsub("^@", "") or "unknown"
	local line = info.linedefined or 0
	
	return string.format("%s:%d [%s]", source, line, name)
end

--- Format log message
---@param level string Log level
---@param module string Module name
---@param message string Log message
---@return string formatted
local function format_log(level, module, message)
	local timestamp = get_timestamp()
	local caller = get_caller_info()
	return string.format("[%s] [%s] [%s] %s | %s", timestamp, level, module, caller, message)
end

--- Write log to file
---@param message string Log message
local function write_to_file(message)
	local log = get_logger()
	local f = io.open(log.log_file, "a")
	if f then
		f:write(message .. "\n")
		f:close()
	end
end

--- Log debug message
---@param module string Module name
---@param message string Log message
function M.debug(module, message)
	local log = get_logger()
	if not log.debug_enabled then
		return
	end
	
	local formatted = format_log("DEBUG", module, message)
	write_to_file(formatted)
	
	-- Also use vim.notify for visibility
	vim.notify("[codetyper] " .. message, vim.log.levels.DEBUG)
end

--- Log info message
---@param module string Module name
---@param message string Log message
function M.info(module, message)
	local formatted = format_log("INFO", module, message)
	write_to_file(formatted)
	vim.notify("[codetyper] " .. message, vim.log.levels.INFO)
end

--- Log warning message
---@param module string Module name
---@param message string Log message
function M.warn(module, message)
	local formatted = format_log("WARN", module, message)
	write_to_file(formatted)
	vim.notify("[codetyper] " .. message, vim.log.levels.WARN)
end

--- Log error message
---@param module string Module name
---@param message string Log message
function M.error(module, message)
	local formatted = format_log("ERROR", module, message)
	write_to_file(formatted)
	vim.notify("[codetyper] " .. message, vim.log.levels.ERROR)
end

--- Log function entry with parameters
---@param module string Module name
---@param func_name string Function name
---@param params table|nil Parameters (will be inspected)
function M.func_entry(module, func_name, params)
	local log = get_logger()
	if not log.debug_enabled then
		return
	end
	
	local param_str = ""
	if params then
		local parts = {}
		for k, v in pairs(params) do
			local val_str = tostring(v)
			if #val_str > 50 then
				val_str = val_str:sub(1, 47) .. "..."
			end
			table.insert(parts, k .. "=" .. val_str)
		end
		param_str = table.concat(parts, ", ")
	end
	
	local message = string.format("ENTER %s(%s)", func_name, param_str)
	M.debug(module, message)
end

--- Log function exit with return value
---@param module string Module name
---@param func_name string Function name
---@param result any Return value (will be inspected)
function M.func_exit(module, func_name, result)
	local log = get_logger()
	if not log.debug_enabled then
		return
	end
	
	local result_str = tostring(result)
	if type(result) == "table" then
		result_str = vim.inspect(result)
	end
	if #result_str > 100 then
		result_str = result_str:sub(1, 97) .. "..."
	end
	
	local message = string.format("EXIT %s -> %s", func_name, result_str)
	M.debug(module, message)
end

--- Enable or disable debug logging
---@param enabled boolean
function M.set_debug(enabled)
	local log = get_logger()
	log.debug_enabled = enabled
	M.info("logger", "Debug logging " .. (enabled and "enabled" or "disabled"))
end

--- Get log file path
---@return string log_file path
function M.get_log_file()
	local log = get_logger()
	return log.log_file
end

--- Clear log file
function M.clear()
	local log = get_logger()
	local f = io.open(log.log_file, "w")
	if f then
		f:write("")
		f:close()
	end
	M.info("logger", "Log file cleared")
end

--- Show logs in a buffer
function M.show()
	local log = get_logger()
	local lines = {}
	
	local f = io.open(log.log_file, "r")
	if f then
		for line in f:lines() do
			table.insert(lines, line)
		end
		f:close()
	end
	
	-- Create a new buffer
	local bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	vim.bo[bufnr].filetype = "log"
	vim.bo[bufnr].modifiable = false
	vim.bo[bufnr].readonly = true
	
	-- Open in a split
	vim.cmd("vsplit")
	local win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win, bufnr)
	
	return bufnr
end

return M
