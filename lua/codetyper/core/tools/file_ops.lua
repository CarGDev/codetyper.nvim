---@mod codetyper.core.tools.file_ops Shared file operation utilities
---@brief [[
--- Utilities for post-write processing: linting, formatting, saving.
---@brief ]]

local M = {}

--- Find the main editor window (not the agent chat panels)
---@return number|nil winid
local function find_main_editor_window()
	-- Get all windows
	local wins = vim.api.nvim_list_wins()

	for _, win in ipairs(wins) do
		local buf = vim.api.nvim_win_get_buf(win)
		local buftype = vim.bo[buf].buftype

		-- Skip special buffers (nofile buffers are the agent chat/logs panels)
		if buftype == "" then
			-- This is a normal file buffer window
			local width = vim.api.nvim_win_get_width(win)
			local height = vim.api.nvim_win_get_height(win)

			-- Prefer larger windows (likely the main editor, not side panels)
			if width > 30 and height > 10 then
				return win
			end
		end
	end

	return nil
end

--- Post-write processing: reload buffer, run linter, format, save
--- Opens the file in the main editor window if available
---@param path string Absolute file path
---@param on_log function|nil Logger function
---@param opts? {open_in_editor?: boolean} Options
function M.post_write_process(path, on_log, opts)
	opts = opts or {}
	local open_in_editor = opts.open_in_editor ~= false -- Default true

	vim.schedule(function()
		-- Check if buffer already exists
		local bufnr = vim.fn.bufnr(path)
		local is_new_buffer = bufnr == -1

		if is_new_buffer then
			-- For new buffers, decide whether to open in window or just track silently
			if open_in_editor then
				-- Find main editor window to open the file
				local main_win = find_main_editor_window()
				if main_win then
					vim.api.nvim_set_current_win(main_win)
					vim.cmd("edit " .. vim.fn.fnameescape(path))
					bufnr = vim.fn.bufnr(path)
				else
					-- No suitable window, create hidden buffer
					bufnr = vim.fn.bufadd(path)
					vim.fn.bufload(bufnr)
				end
			else
				-- Silent mode - just add buffer without opening
				bufnr = vim.fn.bufadd(path)
				vim.fn.bufload(bufnr)
			end
		end

		if not vim.api.nvim_buf_is_valid(bufnr) then
			return
		end

		-- Reload from disk if buffer was already open
		if not is_new_buffer then
			vim.api.nvim_buf_call(bufnr, function()
				vim.cmd("silent! edit!")
			end)
		end

		-- Trigger LSP diagnostics refresh
		vim.schedule(function()
			if not vim.api.nvim_buf_is_valid(bufnr) then
				return
			end

			-- Notify LSP clients of the change
			local clients = vim.lsp.get_clients({ bufnr = bufnr })
			if #clients > 0 then
				if on_log then
					on_log("Running linter...")
				end
				-- Force diagnostic refresh
				vim.diagnostic.reset(nil, bufnr)
				for _, client in ipairs(clients) do
					if client.supports_method("textDocument/diagnostic") then
						vim.lsp.buf.document_diagnostic()
					end
				end
			end

			-- Try to format the file if LSP supports it
			vim.schedule(function()
				if not vim.api.nvim_buf_is_valid(bufnr) then
					return
				end

				local format_clients = vim.lsp.get_clients({ bufnr = bufnr, method = "textDocument/formatting" })
				if #format_clients > 0 then
					if on_log then
						on_log("Formatting file...")
					end
					vim.api.nvim_buf_call(bufnr, function()
						vim.lsp.buf.format({ async = false, timeout_ms = 3000 })
						-- Save after formatting
						if vim.bo[bufnr].modified then
							vim.cmd("silent! write")
						end
					end)
				else
					-- No formatter, just save if modified
					vim.api.nvim_buf_call(bufnr, function()
						if vim.bo[bufnr].modified then
							vim.cmd("silent! write")
						end
					end)
				end

				-- Final diagnostic check after format
				vim.schedule(function()
					if vim.api.nvim_buf_is_valid(bufnr) then
						local diags = vim.diagnostic.get(bufnr)
						local errors = vim.tbl_filter(function(d)
							return d.severity == vim.diagnostic.severity.ERROR
						end, diags)
						if #errors > 0 and on_log then
							on_log(string.format("Linter found %d error(s)", #errors))
						end
					end
				end)
			end)
		end)
	end)
end

return M
