---@mod codetyper.autocmds Autocommands for Codetyper.nvim

local M = {}

local utils = require("codetyper.utils")

--- Autocommand group name
local AUGROUP = "Codetyper"

--- Debounce timer for tree updates
local tree_update_timer = nil
local TREE_UPDATE_DEBOUNCE_MS = 1000 -- 1 second debounce

--- Track processed prompts to avoid re-processing
---@type table<string, boolean>
local processed_prompts = {}

--- Generate a unique key for a prompt
---@param bufnr number Buffer number
---@param prompt table Prompt object
---@return string Unique key
local function get_prompt_key(bufnr, prompt)
	return string.format("%d:%d:%d:%s", bufnr, prompt.start_line, prompt.end_line, prompt.content:sub(1, 50))
end

--- Schedule tree update with debounce
local function schedule_tree_update()
	if tree_update_timer then
		tree_update_timer:stop()
	end

	tree_update_timer = vim.defer_fn(function()
		local tree = require("codetyper.tree")
		tree.update_tree_log()
		tree_update_timer = nil
	end, TREE_UPDATE_DEBOUNCE_MS)
end

--- Setup autocommands
function M.setup()
	local group = vim.api.nvim_create_augroup(AUGROUP, { clear = true })

	-- Auto-check for closed prompts when leaving insert mode (works on ALL files)
	vim.api.nvim_create_autocmd("InsertLeave", {
		group = group,
		pattern = "*",
		callback = function()
			-- Skip special buffers
			local buftype = vim.bo.buftype
			if buftype ~= "" then
				return
			end
			-- Auto-save coder files only
			local filepath = vim.fn.expand("%:p")
			if utils.is_coder_file(filepath) and vim.bo.modified then
				vim.cmd("silent! write")
			end
			-- Check for closed prompts and auto-process
			M.check_for_closed_prompt()
		end,
		desc = "Check for closed prompt tags on InsertLeave",
	})

	-- Auto-process prompts when entering normal mode (works on ALL files)
	vim.api.nvim_create_autocmd("ModeChanged", {
		group = group,
		pattern = "*:n",
		callback = function()
			-- Skip special buffers
			local buftype = vim.bo.buftype
			if buftype ~= "" then
				return
			end
			-- Slight delay to let buffer settle
			vim.defer_fn(function()
				M.check_all_prompts()
			end, 50)
		end,
		desc = "Auto-process closed prompts when entering normal mode",
	})

	-- Also check on CursorHold as backup (works on ALL files)
	vim.api.nvim_create_autocmd("CursorHold", {
		group = group,
		pattern = "*",
		callback = function()
			-- Skip special buffers
			local buftype = vim.bo.buftype
			if buftype ~= "" then
				return
			end
			local mode = vim.api.nvim_get_mode().mode
			if mode == "n" then
				M.check_all_prompts()
			end
		end,
		desc = "Auto-process closed prompts when idle in normal mode",
	})

	-- Auto-set filetype for coder files based on extension
	vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
		group = group,
		pattern = "*.coder.*",
		callback = function()
			M.set_coder_filetype()
		end,
		desc = "Set filetype for coder files",
	})

	-- Auto-open split view when opening a coder file directly (e.g., from nvim-tree)
	vim.api.nvim_create_autocmd("BufEnter", {
		group = group,
		pattern = "*.coder.*",
		callback = function()
			-- Delay slightly to ensure buffer is fully loaded
			vim.defer_fn(function()
				M.auto_open_target_file()
			end, 50)
		end,
		desc = "Auto-open target file when coder file is opened",
	})

	-- Cleanup on buffer close
	vim.api.nvim_create_autocmd("BufWipeout", {
		group = group,
		pattern = "*.coder.*",
		callback = function(ev)
			local window = require("codetyper.window")
			if window.is_open() then
				window.close_split()
			end
			-- Clear processed prompts for this buffer
			local bufnr = ev.buf
			for key, _ in pairs(processed_prompts) do
				if key:match("^" .. bufnr .. ":") then
					processed_prompts[key] = nil
				end
			end
			-- Clear auto-opened tracking
			M.clear_auto_opened(bufnr)
		end,
		desc = "Cleanup on coder buffer close",
	})

	-- Update tree.log when files are created/written
	vim.api.nvim_create_autocmd({ "BufWritePost", "BufNewFile" }, {
		group = group,
		pattern = "*",
		callback = function(ev)
			-- Skip coder files and tree.log itself
			local filepath = ev.file or vim.fn.expand("%:p")
			if filepath:match("%.coder%.") or filepath:match("tree%.log$") then
				return
			end
			-- Schedule tree update with debounce
			schedule_tree_update()
		end,
		desc = "Update tree.log on file creation/save",
	})

	-- Update tree.log when files are deleted (via netrw or file explorer)
	vim.api.nvim_create_autocmd("BufDelete", {
		group = group,
		pattern = "*",
		callback = function(ev)
			local filepath = ev.file or ""
			-- Skip special buffers and coder files
			if filepath == "" or filepath:match("%.coder%.") or filepath:match("tree%.log$") then
				return
			end
			schedule_tree_update()
		end,
		desc = "Update tree.log on file deletion",
	})

	-- Update tree on directory change
	vim.api.nvim_create_autocmd("DirChanged", {
		group = group,
		pattern = "*",
		callback = function()
			schedule_tree_update()
		end,
		desc = "Update tree.log on directory change",
	})

	-- Auto-index: Create/open coder companion file when opening source files
	vim.api.nvim_create_autocmd("BufEnter", {
		group = group,
		pattern = "*",
		callback = function(ev)
			-- Delay to ensure buffer is fully loaded
			vim.defer_fn(function()
				M.auto_index_file(ev.buf)
			end, 100)
		end,
		desc = "Auto-index source files with coder companion",
	})
end

--- Get config with fallback defaults
local function get_config_safe()
	local codetyper = require("codetyper")
	local config = codetyper.get_config()
	-- Return defaults if not initialized
	if not config or not config.patterns then
		return {
			patterns = {
				open_tag = "/@",
				close_tag = "@/",
				file_pattern = "*.coder.*",
			}
		}
	end
	return config
end

--- Read attached files from prompt content
---@param prompt_content string Prompt content
---@param base_path string Base path to resolve relative file paths
---@return table[] attached_files List of {path, content} tables
local function read_attached_files(prompt_content, base_path)
	local parser = require("codetyper.parser")
	local file_refs = parser.extract_file_references(prompt_content)
	local attached = {}
	local cwd = vim.fn.getcwd()
	local base_dir = vim.fn.fnamemodify(base_path, ":h")

	for _, ref in ipairs(file_refs) do
		local file_path = nil

		-- Try resolving relative to cwd first
		local cwd_path = cwd .. "/" .. ref
		if utils.file_exists(cwd_path) then
			file_path = cwd_path
		else
			-- Try resolving relative to base file directory
			local rel_path = base_dir .. "/" .. ref
			if utils.file_exists(rel_path) then
				file_path = rel_path
			end
		end

		if file_path then
			local content = utils.read_file(file_path)
			if content then
				table.insert(attached, {
					path = ref,
					full_path = file_path,
					content = content,
				})
			end
		end
	end

	return attached
end

--- Check if the buffer has a newly closed prompt and auto-process (works on ANY file)
function M.check_for_closed_prompt()
	local config = get_config_safe()
	local parser = require("codetyper.parser")

	local bufnr = vim.api.nvim_get_current_buf()
	local current_file = vim.fn.expand("%:p")

	-- Skip if no file
	if current_file == "" then
		return
	end

	-- Get current line
	local cursor = vim.api.nvim_win_get_cursor(0)
	local line = cursor[1]
	local lines = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)

	if #lines == 0 then
		return
	end

	local current_line = lines[1]

	-- Check if line contains closing tag
	if parser.has_closing_tag(current_line, config.patterns.close_tag) then
		-- Find the complete prompt
		local prompt = parser.get_last_prompt(bufnr)
		if prompt and prompt.content and prompt.content ~= "" then
			-- Generate unique key for this prompt
			local prompt_key = get_prompt_key(bufnr, prompt)

			-- Check if already processed
			if processed_prompts[prompt_key] then
				return
			end

			-- Mark as processed
			processed_prompts[prompt_key] = true

			-- Check if scheduler is enabled
			local codetyper = require("codetyper")
			local ct_config = codetyper.get_config()
			local scheduler_enabled = ct_config and ct_config.scheduler and ct_config.scheduler.enabled

			if scheduler_enabled then
				-- Event-driven: emit to queue
				vim.schedule(function()
					local queue = require("codetyper.agent.queue")
					local patch_mod = require("codetyper.agent.patch")
					local intent_mod = require("codetyper.agent.intent")
					local scope_mod = require("codetyper.agent.scope")
					local logs_panel = require("codetyper.logs_panel")

					-- Open logs panel to show progress
					logs_panel.ensure_open()

					-- Take buffer snapshot
					local snapshot = patch_mod.snapshot_buffer(bufnr, {
						start_line = prompt.start_line,
						end_line = prompt.end_line,
					})

					-- Get target path - for coder files, get the target; for regular files, use self
					local target_path
					if utils.is_coder_file(current_file) then
						target_path = utils.get_target_path(current_file)
					else
						target_path = current_file
					end

					-- Read attached files before cleaning
					local attached_files = read_attached_files(prompt.content, current_file)

					-- Clean prompt content (strip file references)
					local cleaned = parser.clean_prompt(parser.strip_file_references(prompt.content))

					-- Resolve scope in target file FIRST (need it to adjust intent)
					local target_bufnr = vim.fn.bufnr(target_path)
					if target_bufnr == -1 then
						target_bufnr = bufnr
					end

					local scope = nil
					local scope_text = nil
					local scope_range = nil

					scope = scope_mod.resolve_scope(target_bufnr, prompt.start_line, 1)
					if scope and scope.type ~= "file" then
						scope_text = scope.text
						scope_range = {
							start_line = scope.range.start_row,
							end_line = scope.range.end_row,
						}
					end

					-- Detect intent from prompt
					local intent = intent_mod.detect(cleaned)

					-- IMPORTANT: If prompt is inside a function/method and intent is "add",
					-- override to "complete" since we're completing the function body
					if scope and (scope.type == "function" or scope.type == "method") then
						if intent.type == "add" or intent.action == "insert" or intent.action == "append" then
							-- Override to complete the function instead of adding new code
							intent = {
								type = "complete",
								scope_hint = "function",
								confidence = intent.confidence,
								action = "replace",
								keywords = intent.keywords,
							}
						end
					end

					-- Determine priority based on intent
					local priority = 2 -- Normal
					if intent.type == "fix" or intent.type == "complete" then
						priority = 1 -- High priority for fixes and completions
					elseif intent.type == "test" or intent.type == "document" then
						priority = 3 -- Lower priority for tests and docs
					end

					-- Enqueue the event
					queue.enqueue({
						id = queue.generate_id(),
						bufnr = bufnr,
						range = { start_line = prompt.start_line, end_line = prompt.end_line },
						timestamp = os.clock(),
						changedtick = snapshot.changedtick,
						content_hash = snapshot.content_hash,
						prompt_content = cleaned,
						target_path = target_path,
						priority = priority,
						status = "pending",
						attempt_count = 0,
						intent = intent,
						scope = scope,
						scope_text = scope_text,
						scope_range = scope_range,
						attached_files = attached_files,
					})

					local scope_info = scope and scope.type ~= "file"
						and string.format(" [%s: %s]", scope.type, scope.name or "anonymous")
						or ""
					utils.notify(
						string.format("Prompt queued: %s%s", intent.type, scope_info),
						vim.log.levels.INFO
					)
				end)
			else
				-- Legacy: direct processing
				utils.notify("Processing prompt...", vim.log.levels.INFO)
				vim.schedule(function()
					vim.cmd("CoderProcess")
				end)
			end
		end
	end
end

--- Check and process all closed prompts in the buffer (works on ANY file)
function M.check_all_prompts()
	local parser = require("codetyper.parser")
	local bufnr = vim.api.nvim_get_current_buf()
	local current_file = vim.fn.expand("%:p")

	-- Skip if no file
	if current_file == "" then
		return
	end

	-- Find all prompts in buffer
	local prompts = parser.find_prompts_in_buffer(bufnr)

	if #prompts == 0 then
		return
	end

	-- Check if scheduler is enabled
	local codetyper = require("codetyper")
	local ct_config = codetyper.get_config()
	local scheduler_enabled = ct_config and ct_config.scheduler and ct_config.scheduler.enabled

	if not scheduler_enabled then
		return
	end

	for _, prompt in ipairs(prompts) do
		if prompt.content and prompt.content ~= "" then
			-- Generate unique key for this prompt
			local prompt_key = get_prompt_key(bufnr, prompt)

			-- Skip if already processed
			if processed_prompts[prompt_key] then
				goto continue
			end

			-- Mark as processed
			processed_prompts[prompt_key] = true

			-- Process this prompt
			vim.schedule(function()
				local queue = require("codetyper.agent.queue")
				local patch_mod = require("codetyper.agent.patch")
				local intent_mod = require("codetyper.agent.intent")
				local scope_mod = require("codetyper.agent.scope")
				local logs_panel = require("codetyper.logs_panel")

				-- Open logs panel to show progress
				logs_panel.ensure_open()

				-- Take buffer snapshot
				local snapshot = patch_mod.snapshot_buffer(bufnr, {
					start_line = prompt.start_line,
					end_line = prompt.end_line,
				})

				-- Get target path - for coder files, get the target; for regular files, use self
				local target_path
				if utils.is_coder_file(current_file) then
					target_path = utils.get_target_path(current_file)
				else
					target_path = current_file
				end

				-- Read attached files before cleaning
				local attached_files = read_attached_files(prompt.content, current_file)

				-- Clean prompt content (strip file references)
				local cleaned = parser.clean_prompt(parser.strip_file_references(prompt.content))

				-- Resolve scope in target file FIRST (need it to adjust intent)
				local target_bufnr = vim.fn.bufnr(target_path)
				if target_bufnr == -1 then
					target_bufnr = bufnr -- Use current buffer if target not loaded
				end

				local scope = nil
				local scope_text = nil
				local scope_range = nil

				scope = scope_mod.resolve_scope(target_bufnr, prompt.start_line, 1)
				if scope and scope.type ~= "file" then
					scope_text = scope.text
					scope_range = {
						start_line = scope.range.start_row,
						end_line = scope.range.end_row,
					}
				end

				-- Detect intent from prompt
				local intent = intent_mod.detect(cleaned)

				-- IMPORTANT: If prompt is inside a function/method and intent is "add",
				-- override to "complete" since we're completing the function body
				if scope and (scope.type == "function" or scope.type == "method") then
					if intent.type == "add" or intent.action == "insert" or intent.action == "append" then
						-- Override to complete the function instead of adding new code
						intent = {
							type = "complete",
							scope_hint = "function",
							confidence = intent.confidence,
							action = "replace",
							keywords = intent.keywords,
						}
					end
				end

				-- Determine priority based on intent
				local priority = 2
				if intent.type == "fix" or intent.type == "complete" then
					priority = 1
				elseif intent.type == "test" or intent.type == "document" then
					priority = 3
				end

				-- Enqueue the event
				queue.enqueue({
					id = queue.generate_id(),
					bufnr = bufnr,
					range = { start_line = prompt.start_line, end_line = prompt.end_line },
					timestamp = os.clock(),
					changedtick = snapshot.changedtick,
					content_hash = snapshot.content_hash,
					prompt_content = cleaned,
					target_path = target_path,
					priority = priority,
					status = "pending",
					attempt_count = 0,
					intent = intent,
					scope = scope,
					scope_text = scope_text,
					scope_range = scope_range,
					attached_files = attached_files,
				})

				local scope_info = scope and scope.type ~= "file"
					and string.format(" [%s: %s]", scope.type, scope.name or "anonymous")
					or ""
				utils.notify(
					string.format("Prompt queued: %s%s", intent.type, scope_info),
					vim.log.levels.INFO
				)
			end)

			::continue::
		end
	end
end

--- Reset processed prompts for a buffer (useful for re-processing)
---@param bufnr? number Buffer number (default: current)
function M.reset_processed(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	for key, _ in pairs(processed_prompts) do
		if key:match("^" .. bufnr .. ":") then
			processed_prompts[key] = nil
		end
	end
	utils.notify("Prompt history cleared - prompts can be re-processed")
end

--- Track if we already opened the split for this buffer
---@type table<number, boolean>
local auto_opened_buffers = {}

--- Auto-open target file when a coder file is opened directly
function M.auto_open_target_file()
	local window = require("codetyper.window")

	-- Skip if split is already open
	if window.is_open() then
		return
	end

	local bufnr = vim.api.nvim_get_current_buf()

	-- Skip if we already handled this buffer
	if auto_opened_buffers[bufnr] then
		return
	end

	local current_file = vim.fn.expand("%:p")

	-- Skip empty paths
	if not current_file or current_file == "" then
		return
	end

	-- Verify it's a coder file
	if not utils.is_coder_file(current_file) then
		return
	end

	-- Skip if we're in a special buffer (nvim-tree, etc.)
	local buftype = vim.bo[bufnr].buftype
	if buftype ~= "" then
		return
	end

	-- Mark as handled
	auto_opened_buffers[bufnr] = true

	-- Get the target file path
	local target_path = utils.get_target_path(current_file)

	-- Check if target file exists
	if not utils.file_exists(target_path) then
		utils.notify("Target file not found: " .. vim.fn.fnamemodify(target_path, ":t"), vim.log.levels.WARN)
		return
	end

	-- Get config with fallback defaults
	local codetyper = require("codetyper")
	local config = codetyper.get_config()

	-- Fallback width if config not fully loaded (percentage, e.g., 25 = 25%)
	local width_pct = (config and config.window and config.window.width) or 25
	local width = math.ceil(vim.o.columns * (width_pct / 100))

	-- Store current coder window
	local coder_win = vim.api.nvim_get_current_win()
	local coder_buf = bufnr

	-- Open target file in a vertical split on the right
	local ok, err = pcall(function()
		vim.cmd("vsplit " .. vim.fn.fnameescape(target_path))
	end)

	if not ok then
		utils.notify("Failed to open target file: " .. tostring(err), vim.log.levels.ERROR)
		auto_opened_buffers[bufnr] = nil -- Allow retry
		return
	end

	-- Now we're in the target window (right side)
	local target_win = vim.api.nvim_get_current_win()
	local target_buf = vim.api.nvim_get_current_buf()

	-- Set the coder window width (left side)
	pcall(vim.api.nvim_win_set_width, coder_win, width)

	-- Update window module state
	window._coder_win = coder_win
	window._coder_buf = coder_buf
	window._target_win = target_win
	window._target_buf = target_buf

	-- Set up window options for coder window
	pcall(function()
		vim.wo[coder_win].number = true
		vim.wo[coder_win].relativenumber = true
		vim.wo[coder_win].signcolumn = "yes"
	end)

	utils.notify("Opened target: " .. vim.fn.fnamemodify(target_path, ":t"))
end

--- Clear auto-opened tracking for a buffer
---@param bufnr number Buffer number
function M.clear_auto_opened(bufnr)
	auto_opened_buffers[bufnr] = nil
end

--- Set appropriate filetype for coder files
function M.set_coder_filetype()
	local filepath = vim.fn.expand("%:p")

	-- Extract the actual extension (e.g., index.coder.ts -> ts)
	local ext = filepath:match("%.coder%.(%w+)$")

	if ext then
		-- Map extension to filetype
		local ft_map = {
			ts = "typescript",
			tsx = "typescriptreact",
			js = "javascript",
			jsx = "javascriptreact",
			py = "python",
			lua = "lua",
			go = "go",
			rs = "rust",
			rb = "ruby",
			java = "java",
			c = "c",
			cpp = "cpp",
			cs = "cs",
			json = "json",
			yaml = "yaml",
			yml = "yaml",
			md = "markdown",
			html = "html",
			css = "css",
			scss = "scss",
			vue = "vue",
			svelte = "svelte",
		}

		local filetype = ft_map[ext] or ext
		vim.bo.filetype = filetype
	end
end

--- Clear all autocommands
function M.clear()
	vim.api.nvim_del_augroup_by_name(AUGROUP)
end

--- Track buffers that have been auto-indexed
---@type table<number, boolean>
local auto_indexed_buffers = {}

--- Supported file extensions for auto-indexing
local supported_extensions = {
	"ts", "tsx", "js", "jsx", "py", "lua", "go", "rs", "rb",
	"java", "c", "cpp", "cs", "json", "yaml", "yml", "md",
	"html", "css", "scss", "vue", "svelte", "php", "sh", "zsh",
}

--- Check if extension is supported
---@param ext string File extension
---@return boolean
local function is_supported_extension(ext)
	for _, supported in ipairs(supported_extensions) do
		if ext == supported then
			return true
		end
	end
	return false
end

--- Auto-index a file by creating/opening its coder companion
---@param bufnr number Buffer number
function M.auto_index_file(bufnr)
	-- Skip if buffer is invalid
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	-- Skip if already indexed
	if auto_indexed_buffers[bufnr] then
		return
	end

	-- Get file path
	local filepath = vim.api.nvim_buf_get_name(bufnr)
	if not filepath or filepath == "" then
		return
	end

	-- Skip coder files
	if utils.is_coder_file(filepath) then
		return
	end

	-- Skip special buffers
	local buftype = vim.bo[bufnr].buftype
	if buftype ~= "" then
		return
	end

	-- Skip unsupported file types
	local ext = vim.fn.fnamemodify(filepath, ":e")
	if ext == "" or not is_supported_extension(ext) then
		return
	end

	-- Skip if auto_index is disabled in config
	local codetyper = require("codetyper")
	local config = codetyper.get_config()
	if config and config.auto_index == false then
		return
	end

	-- Mark as indexed
	auto_indexed_buffers[bufnr] = true

	-- Get coder companion path
	local coder_path = utils.get_coder_path(filepath)

	-- Check if coder file already exists
	local coder_exists = utils.file_exists(coder_path)

	-- Create coder file with template if it doesn't exist
	if not coder_exists then
		local filename = vim.fn.fnamemodify(filepath, ":t")
		local template = string.format(
			[[-- Coder companion for %s
-- Use /@ @/ tags to write pseudo-code prompts
-- Example:
-- /@
-- Add a function that validates user input
-- - Check for empty strings
-- - Validate email format
-- @/

]],
			filename
		)
		utils.write_file(coder_path, template)
	end

	-- Notify user about the coder companion
	local coder_filename = vim.fn.fnamemodify(coder_path, ":t")
	if coder_exists then
		utils.notify("Coder companion available: " .. coder_filename, vim.log.levels.DEBUG)
	else
		utils.notify("Created coder companion: " .. coder_filename, vim.log.levels.INFO)
	end
end

--- Open the coder companion for the current file
---@param open_split? boolean Whether to open in split view (default: true)
function M.open_coder_companion(open_split)
	open_split = open_split ~= false -- Default to true

	local filepath = vim.fn.expand("%:p")
	if not filepath or filepath == "" then
		utils.notify("No file open", vim.log.levels.WARN)
		return
	end

	if utils.is_coder_file(filepath) then
		utils.notify("Already in coder file", vim.log.levels.INFO)
		return
	end

	local coder_path = utils.get_coder_path(filepath)

	-- Create if it doesn't exist
	if not utils.file_exists(coder_path) then
		local filename = vim.fn.fnamemodify(filepath, ":t")
		local ext = vim.fn.fnamemodify(filepath, ":e")
		local comment_prefix = "--"
		if vim.tbl_contains({ "js", "jsx", "ts", "tsx", "java", "c", "cpp", "cs", "go", "rs", "php" }, ext) then
			comment_prefix = "//"
		elseif vim.tbl_contains({ "py", "sh", "zsh", "yaml", "yml" }, ext) then
			comment_prefix = "#"
		elseif vim.tbl_contains({ "html", "md" }, ext) then
			comment_prefix = "<!--"
		end

		local close_comment = comment_prefix == "<!--" and " -->" or ""
		local template = string.format(
			[[%s Coder companion for %s%s
%s Use /@ @/ tags to write pseudo-code prompts%s
%s Example:%s
%s /@%s
%s Add a function that validates user input%s
%s - Check for empty strings%s
%s - Validate email format%s
%s @/%s

]],
			comment_prefix, filename, close_comment,
			comment_prefix, close_comment,
			comment_prefix, close_comment,
			comment_prefix, close_comment,
			comment_prefix, close_comment,
			comment_prefix, close_comment,
			comment_prefix, close_comment,
			comment_prefix, close_comment
		)
		utils.write_file(coder_path, template)
	end

	if open_split then
		-- Use the window module to open split view
		local window = require("codetyper.window")
		window.open_split(coder_path, filepath)
	else
		-- Just open the coder file
		vim.cmd("edit " .. vim.fn.fnameescape(coder_path))
	end
end

--- Clear auto-indexed tracking for a buffer
---@param bufnr number Buffer number
function M.clear_auto_indexed(bufnr)
	auto_indexed_buffers[bufnr] = nil
end

return M
