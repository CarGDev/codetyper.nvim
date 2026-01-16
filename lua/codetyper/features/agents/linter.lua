---@mod codetyper.agent.linter Linter validation for generated code
---@brief [[
--- Validates generated code by checking LSP diagnostics after injection.
--- Automatically saves the file and waits for LSP to update before checking.
---@brief ]]

local M = {}

local config_params = require("codetyper.params.agent.linter")
local prompts = require("codetyper.prompts.agent.linter")

--- Configuration
local config = config_params.config

--- Diagnostic results for tracking
---@type table<number, table>
local validation_results = {}

--- Configure linter behavior
---@param opts table Configuration options
function M.configure(opts)
	for k, v in pairs(opts) do
		if config[k] ~= nil then
			config[k] = v
		end
	end
end

--- Get current configuration
---@return table
function M.get_config()
	return vim.deepcopy(config)
end

--- Save buffer if modified
---@param bufnr number Buffer number
---@return boolean success
local function save_buffer(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return false
	end

	-- Skip if buffer is not modified
	if not vim.bo[bufnr].modified then
		return true
	end

	-- Skip if buffer has no name (unsaved file)
	local bufname = vim.api.nvim_buf_get_name(bufnr)
	if bufname == "" then
		return false
	end

	-- Save the buffer
	local ok, err = pcall(function()
		vim.api.nvim_buf_call(bufnr, function()
			vim.cmd("silent! write")
		end)
	end)

	if not ok then
		pcall(function()
			local logs = require("codetyper.adapters.nvim.ui.logs")
			logs.add({
				type = "warning",
				message = "Failed to save buffer: " .. tostring(err),
			})
		end)
		return false
	end

	return true
end

--- Get LSP diagnostics for a buffer
---@param bufnr number Buffer number
---@param start_line? number Start line (1-indexed)
---@param end_line? number End line (1-indexed)
---@return table[] diagnostics List of diagnostics
function M.get_diagnostics(bufnr, start_line, end_line)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return {}
	end

	local all_diagnostics = vim.diagnostic.get(bufnr)
	local filtered = {}

	for _, diag in ipairs(all_diagnostics) do
		-- Filter by severity
		if diag.severity <= config.min_severity then
			-- Filter by line range if specified
			if start_line and end_line then
				local diag_line = diag.lnum + 1 -- Convert to 1-indexed
				if diag_line >= start_line and diag_line <= end_line then
					table.insert(filtered, diag)
				end
			else
				table.insert(filtered, diag)
			end
		end
	end

	return filtered
end

--- Format a diagnostic for display
---@param diag table Diagnostic object
---@return string
local function format_diagnostic(diag)
	local severity_names = {
		[vim.diagnostic.severity.ERROR] = "ERROR",
		[vim.diagnostic.severity.WARN] = "WARN",
		[vim.diagnostic.severity.INFO] = "INFO",
		[vim.diagnostic.severity.HINT] = "HINT",
	}
	local severity = severity_names[diag.severity] or "UNKNOWN"
	local line = diag.lnum + 1
	local source = diag.source or "lsp"
	return string.format("[%s] Line %d (%s): %s", severity, line, source, diag.message)
end

--- Check if there are errors in generated code region
---@param bufnr number Buffer number
---@param start_line number Start line (1-indexed)
---@param end_line number End line (1-indexed)
---@return table result {has_errors, has_warnings, diagnostics, summary}
function M.check_region(bufnr, start_line, end_line)
	local diagnostics = M.get_diagnostics(bufnr, start_line, end_line)

	local errors = 0
	local warnings = 0

	for _, diag in ipairs(diagnostics) do
		if diag.severity == vim.diagnostic.severity.ERROR then
			errors = errors + 1
		elseif diag.severity == vim.diagnostic.severity.WARN then
			warnings = warnings + 1
		end
	end

	return {
		has_errors = errors > 0,
		has_warnings = warnings > 0,
		error_count = errors,
		warning_count = warnings,
		diagnostics = diagnostics,
		summary = string.format("%d error(s), %d warning(s)", errors, warnings),
	}
end

--- Validate code after injection and report issues
---@param bufnr number Buffer number
---@param start_line? number Start line of injected code (1-indexed)
---@param end_line? number End line of injected code (1-indexed)
---@param callback? function Callback with (result) when validation completes
function M.validate_after_injection(bufnr, start_line, end_line, callback)
	-- Save the file first
	if config.auto_save then
		save_buffer(bufnr)
	end

	-- Wait for LSP to process changes
	vim.defer_fn(function()
		if not vim.api.nvim_buf_is_valid(bufnr) then
			if callback then callback(nil) end
			return
		end

		local result
		if start_line and end_line then
			result = M.check_region(bufnr, start_line, end_line)
		else
			-- Check entire buffer
			local line_count = vim.api.nvim_buf_line_count(bufnr)
			result = M.check_region(bufnr, 1, line_count)
		end

		-- Store result for this buffer
		validation_results[bufnr] = {
			timestamp = os.time(),
			result = result,
			start_line = start_line,
			end_line = end_line,
		}

		-- Log results
		pcall(function()
			local logs = require("codetyper.adapters.nvim.ui.logs")
			if result.has_errors then
				logs.add({
					type = "error",
					message = string.format("Linter found issues: %s", result.summary),
				})
				-- Log individual errors
				for _, diag in ipairs(result.diagnostics) do
					if diag.severity == vim.diagnostic.severity.ERROR then
						logs.add({
							type = "error",
							message = format_diagnostic(diag),
						})
					end
				end
			elseif result.has_warnings then
				logs.add({
					type = "warning",
					message = string.format("Linter warnings: %s", result.summary),
				})
			else
				logs.add({
					type = "success",
					message = "Linter check passed - no errors or warnings",
				})
			end
		end)

		-- Notify user
		if result.has_errors then
			vim.notify(
				string.format("Generated code has lint errors: %s", result.summary),
				vim.log.levels.ERROR
			)

			-- Offer to fix if configured
			if config.auto_offer_fix and #result.diagnostics > 0 then
				M.offer_fix(bufnr, result)
			end
		elseif result.has_warnings then
			vim.notify(
				string.format("Generated code has warnings: %s", result.summary),
				vim.log.levels.WARN
			)
		end

		if callback then
			callback(result)
		end
	end, config.diagnostic_delay_ms)
end

--- Offer to fix lint errors using AI
---@param bufnr number Buffer number
---@param result table Validation result
function M.offer_fix(bufnr, result)
	if not result.has_errors and not result.has_warnings then
		return
	end

	-- Build error summary for prompt
	local error_messages = {}
	for _, diag in ipairs(result.diagnostics) do
		table.insert(error_messages, format_diagnostic(diag))
	end

	vim.ui.select(
		{ "Yes - Auto-fix with AI", "No - I'll fix manually", "Show errors in quickfix" },
		{
			prompt = string.format("Found %d issue(s). Would you like AI to fix them?", #result.diagnostics),
		},
		function(choice)
			if not choice then return end

			if choice:match("^Yes") then
				M.request_ai_fix(bufnr, result)
			elseif choice:match("quickfix") then
				M.show_in_quickfix(bufnr, result)
			end
		end
	)
end

--- Show lint errors in quickfix list
---@param bufnr number Buffer number
---@param result table Validation result
function M.show_in_quickfix(bufnr, result)
	local qf_items = {}
	local bufname = vim.api.nvim_buf_get_name(bufnr)

	for _, diag in ipairs(result.diagnostics) do
		table.insert(qf_items, {
			bufnr = bufnr,
			filename = bufname,
			lnum = diag.lnum + 1,
			col = diag.col + 1,
			text = diag.message,
			type = diag.severity == vim.diagnostic.severity.ERROR and "E" or "W",
		})
	end

	vim.fn.setqflist(qf_items, "r")
	vim.cmd("copen")
end

--- Request AI to fix lint errors
---@param bufnr number Buffer number
---@param result table Validation result
function M.request_ai_fix(bufnr, result)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	local filepath = vim.api.nvim_buf_get_name(bufnr)

	-- Build fix prompt
	local error_list = {}
	for _, diag in ipairs(result.diagnostics) do
		table.insert(error_list, format_diagnostic(diag))
	end

	-- Get the affected code region
	local start_line = result.diagnostics[1] and (result.diagnostics[1].lnum + 1) or 1
	local end_line = start_line
	for _, diag in ipairs(result.diagnostics) do
		local line = diag.lnum + 1
		if line < start_line then start_line = line end
		if line > end_line then end_line = line end
	end

	-- Expand range by a few lines for context
	start_line = math.max(1, start_line - 5)
	end_line = math.min(vim.api.nvim_buf_line_count(bufnr), end_line + 5)

	local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
	local code_context = table.concat(lines, "\n")

	-- Create fix prompt using inline tag
	local fix_prompt = string.format(
		prompts.fix_request,
		table.concat(error_list, "\n"),
		start_line,
		end_line,
		code_context
	)

	-- Queue the fix through the scheduler
	local scheduler = require("codetyper.core.scheduler.scheduler")
	local queue = require("codetyper.core.events.queue")
	local patch_mod = require("codetyper.core.diff.patch")

	-- Ensure scheduler is running
	if not scheduler.status().running then
		scheduler.start()
	end

	-- Take snapshot
	local snapshot = patch_mod.snapshot_buffer(bufnr, {
		start_line = start_line,
		end_line = end_line,
	})

	-- Enqueue fix request
	queue.enqueue({
		id = queue.generate_id(),
		bufnr = bufnr,
		range = { start_line = start_line, end_line = end_line },
		timestamp = os.clock(),
		changedtick = snapshot.changedtick,
		content_hash = snapshot.content_hash,
		prompt_content = fix_prompt,
		target_path = filepath,
		priority = 1, -- High priority for fixes
		status = "pending",
		attempt_count = 0,
		intent = {
			type = "fix",
			action = "replace",
			confidence = 0.9,
		},
		scope_range = { start_line = start_line, end_line = end_line },
		source = "linter_fix",
	})

	pcall(function()
		local logs = require("codetyper.adapters.nvim.ui.logs")
		logs.add({
			type = "info",
			message = "Queued AI fix request for lint errors",
		})
	end)

	vim.notify("Queued AI fix request for lint errors", vim.log.levels.INFO)
end

--- Get last validation result for a buffer
---@param bufnr number Buffer number
---@return table|nil result
function M.get_last_result(bufnr)
	return validation_results[bufnr]
end

--- Clear validation results for a buffer
---@param bufnr number Buffer number
function M.clear_result(bufnr)
	validation_results[bufnr] = nil
end

--- Check if buffer has any lint errors currently
---@param bufnr number Buffer number
---@return boolean has_errors
function M.has_errors(bufnr)
	local diagnostics = vim.diagnostic.get(bufnr, {
		severity = vim.diagnostic.severity.ERROR,
	})
	return #diagnostics > 0
end

--- Check if buffer has any lint warnings currently
---@param bufnr number Buffer number
---@return boolean has_warnings
function M.has_warnings(bufnr)
	local diagnostics = vim.diagnostic.get(bufnr, {
		severity = { min = vim.diagnostic.severity.WARN },
	})
	return #diagnostics > 0
end

--- Validate all buffers with recent changes
function M.validate_all_changed()
	for bufnr, data in pairs(validation_results) do
		if vim.api.nvim_buf_is_valid(bufnr) then
			M.validate_after_injection(bufnr, data.start_line, data.end_line)
		end
	end
end

return M
