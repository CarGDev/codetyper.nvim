---@mod codetyper.core.tools.common Shared tool utilities
---@brief [[
--- Common utilities for tool implementations: validation, logging, callbacks.
--- Consolidates duplicate patterns across tool modules.
---@brief ]]

local M = {}

---@class ToolOpts
---@field on_log? fun(message: string) Log callback
---@field on_complete? fun(result: any, error: string|nil) Completion callback
---@field confirm? fun(message: string, callback: fun(ok: boolean)) Confirmation callback

--- Validate required parameters
---@param input table Input parameters
---@param required string[] Required parameter names
---@return boolean valid
---@return string|nil error First missing parameter error
function M.validate_required(input, required)
	for _, name in ipairs(required) do
		if input[name] == nil then
			return false, name .. " is required"
		end
	end
	return true, nil
end

--- Log a message if logger is available
---@param opts ToolOpts
---@param message string
function M.log(opts, message)
	if opts.on_log then
		opts.on_log(message)
	end
end

--- Invoke completion callback
---@param opts ToolOpts
---@param result any
---@param error string|nil
function M.complete(opts, result, error)
	if opts.on_complete then
		opts.on_complete(result, error)
	end
end

--- Return result and invoke completion callback
--- Helper that combines returning and callback invocation
---@param opts ToolOpts
---@param result any
---@param error string|nil
---@return any result
---@return string|nil error
function M.return_result(opts, result, error)
	M.complete(opts, result, error)
	return result, error
end

--- Create a standardized JSON result
---@param data table Data to encode
---@return string JSON string
function M.json_result(data)
	return vim.json.encode(data)
end

--- Create a list result with truncation info
---@param items any[] Array of items
---@param max_results number Maximum results allowed
---@return table Result with matches, total, and truncated fields
function M.list_result(items, max_results)
	return {
		matches = items,
		total = #items,
		truncated = #items >= max_results,
	}
end

--- Wrap a tool function with standard error handling
---@param func fun(input: table, opts: ToolOpts): any, string|nil
---@return fun(input: table, opts: ToolOpts): any, string|nil
function M.with_error_handling(func)
	return function(input, opts)
		local ok, result, err = pcall(func, input, opts)
		if not ok then
			local error_msg = "Internal error: " .. tostring(result)
			M.complete(opts, nil, error_msg)
			return nil, error_msg
		end
		return result, err
	end
end

--- Create a validation wrapper for tool functions
---@param required string[] Required parameters
---@param func fun(input: table, opts: ToolOpts): any, string|nil
---@return fun(input: table, opts: ToolOpts): any, string|nil
function M.with_validation(required, func)
	return function(input, opts)
		local valid, err = M.validate_required(input, required)
		if not valid then
			return nil, err
		end
		return func(input, opts)
	end
end

return M
