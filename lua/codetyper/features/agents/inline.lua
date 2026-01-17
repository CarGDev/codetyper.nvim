---@mod codetyper.features.agents.inline In-file agent mode
---@brief [[
--- Handles /@ ... @/ prompts as full agentic interactions, not patches.
--- The agent can read files, write new files, edit existing files, and
--- materialize a complete program state from intent.
--- Changes are collected and shown in a diff review UI for approval.
---@brief ]]

local M = {}

local utils = require("codetyper.support.utils")
local diff_review = require("codetyper.adapters.nvim.ui.diff_review")

--- Pending changes collected during agent run (before diff review)
---@type table<string, {operation: string, original: string|nil, modified: string}>
local pending_changes = {}

--- Read file content or return nil for new files
---@param path string
---@return string|nil
local function read_file_content(path)
	if vim.fn.filereadable(path) == 1 then
		local lines = vim.fn.readfile(path)
		if lines then
			return table.concat(lines, "\n")
		end
	end
	return nil
end

--- Resolve path to absolute
---@param path string
---@return string
local function resolve_path(path)
	if not vim.startswith(path, "/") then
		return vim.fn.getcwd() .. "/" .. path
	end
	return path
end

--- Preview-mode write handler: collects change instead of writing
---@param input {path: string, content: string}
---@param opts table
---@return boolean|nil
---@return string|nil
local function preview_write(input, opts)
	if not input.path then
		return nil, "path is required"
	end
	if not input.content then
		return nil, "content is required"
	end

	local path = resolve_path(input.path)
	local original = read_file_content(path)
	local operation = original and "edit" or "create"

	-- Store in pending changes
	pending_changes[path] = {
		operation = operation,
		original = original,
		modified = input.content,
	}

	if opts.on_log then
		opts.on_log(string.format("[Preview] Would %s: %s", operation, input.path))
	end

	return true, nil
end

--- Normalize line endings to LF
---@param str string
---@return string
local function normalize_line_endings(str)
	return str:gsub("\r\n", "\n"):gsub("\r", "\n")
end

--- Find match using multiple strategies (simplified version)
---@param content string
---@param old_str string
---@return number|nil start_pos
---@return number|nil end_pos
local function find_match(content, old_str)
	-- Strategy 1: Exact match
	local pos = content:find(old_str, 1, true)
	if pos then
		return pos, pos + #old_str - 1
	end

	-- Strategy 2: Whitespace-normalized match
	local function normalize_ws(s)
		return s:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	end

	local norm_old = normalize_ws(old_str)
	local lines = vim.split(content, "\n")

	for i = 1, #lines do
		local block = {}
		for j = i, #lines do
			table.insert(block, lines[j])
			local block_text = table.concat(block, "\n")
			local norm_block = normalize_ws(block_text)

			if norm_block == norm_old then
				local before = table.concat(vim.list_slice(lines, 1, i - 1), "\n")
				local start_pos = #before + (i > 1 and 2 or 1)
				local end_pos = start_pos + #block_text - 1
				return start_pos, end_pos
			end

			if #norm_block > #norm_old then
				break
			end
		end
	end

	-- Strategy 3: Indentation-flexible match
	local function strip_indent(s)
		local l = vim.split(s, "\n")
		local result = {}
		for _, line in ipairs(l) do
			table.insert(result, line:gsub("^%s+", ""))
		end
		return table.concat(result, "\n")
	end

	local stripped_old = strip_indent(old_str)
	local old_lines = vim.split(old_str, "\n")
	local num_old_lines = #old_lines

	for i = 1, #lines - num_old_lines + 1 do
		local block = vim.list_slice(lines, i, i + num_old_lines - 1)
		local block_text = table.concat(block, "\n")

		if strip_indent(block_text) == stripped_old then
			local before = table.concat(vim.list_slice(lines, 1, i - 1), "\n")
			local start_pos = #before + (i > 1 and 2 or 1)
			local end_pos = start_pos + #block_text - 1
			return start_pos, end_pos
		end
	end

	return nil, nil
end

--- Preview-mode edit handler: collects change instead of writing
---@param input {path: string, old_string: string, new_string: string}
---@param opts table
---@return boolean|nil
---@return string|nil
local function preview_edit(input, opts)
	if not input.path then
		return nil, "path is required"
	end
	if input.old_string == nil then
		return nil, "old_string is required"
	end
	if input.new_string == nil then
		return nil, "new_string is required"
	end

	local path = resolve_path(input.path)
	local old_str = normalize_line_endings(input.old_string)
	local new_str = normalize_line_endings(input.new_string)

	-- Handle new file creation (empty old_string)
	if old_str == "" then
		pending_changes[path] = {
			operation = "create",
			original = nil,
			modified = new_str,
		}

		if opts.on_log then
			opts.on_log(string.format("[Preview] Would create: %s", input.path))
		end

		return true, nil
	end

	-- Get current content (may be from pending changes or disk)
	local content
	if pending_changes[path] then
		content = pending_changes[path].modified
	else
		content = read_file_content(path)
	end

	if not content then
		return nil, "File not found: " .. input.path
	end

	content = normalize_line_endings(content)

	-- Find match
	local start_pos, end_pos = find_match(content, old_str)
	if not start_pos then
		return nil, "old_string not found in file"
	end

	-- Compute new content
	local new_content = content:sub(1, start_pos - 1) .. new_str .. content:sub(end_pos + 1)

	-- Store in pending changes
	local original = pending_changes[path] and pending_changes[path].original or read_file_content(path)
	pending_changes[path] = {
		operation = original and "edit" or "create",
		original = original,
		modified = new_content,
	}

	if opts.on_log then
		opts.on_log(string.format("[Preview] Would edit: %s", input.path))
	end

	return true, nil
end

--- Clear pending changes
local function clear_pending_changes()
	pending_changes = {}
end

--- Transfer pending changes to diff_review module
local function transfer_to_diff_review()
	diff_review.clear()

	for path, change in pairs(pending_changes) do
		diff_review.add({
			path = path,
			operation = change.operation,
			original = change.original,
			modified = change.modified,
			approved = false,
			applied = false,
		})
	end
end

---@class InlineAgentOpts
---@field bufnr number Buffer containing the prompt
---@field prompt_content string The user's instruction (cleaned)
---@field prompt_range {start_line: number, end_line: number} Line range of /@ @/ tags
---@field target_path string Path to the file being edited
---@field attached_files? table[] Files referenced with @path syntax
---@field on_complete? fun(success: boolean, error: string|nil)
---@field on_status? fun(status: string)

--- Build context from the current file and surroundings
---@param opts InlineAgentOpts
---@return string context
local function build_file_context(opts)
	local parts = {}

	-- Get full file content (without the /@ @/ tags)
	local lines = vim.api.nvim_buf_get_lines(opts.bufnr, 0, -1, false)
	local file_content = {}

	for i, line in ipairs(lines) do
		-- Skip the prompt tag region but preserve everything else
		if i < opts.prompt_range.start_line or i > opts.prompt_range.end_line then
			table.insert(file_content, line)
		else
			-- Inside tag region - remove only the tag markers, keep code
			local cleaned = line:gsub("/%@", ""):gsub("%@/", "")
			if cleaned:match("%S") then
				table.insert(file_content, cleaned)
			end
		end
	end

	local filetype = vim.fn.fnamemodify(opts.target_path, ":e")
	local filename = vim.fn.fnamemodify(opts.target_path, ":t")

	table.insert(parts, string.format("## Current File: %s\n```%s\n%s\n```",
		filename, filetype, table.concat(file_content, "\n")))

	-- Add attached files
	if opts.attached_files and #opts.attached_files > 0 then
		table.insert(parts, "\n## Referenced Files")
		for _, file in ipairs(opts.attached_files) do
			local ext = vim.fn.fnamemodify(file.path, ":e")
			table.insert(parts, string.format("\n### %s\n```%s\n%s\n```",
				file.path, ext, file.content))
		end
	end

	return table.concat(parts, "\n")
end

--- Build the task prompt for the agent
---@param opts InlineAgentOpts
---@param file_context string
---@return string
local function build_task(opts, file_context)
	local target_path = opts.target_path
	local project_root = utils.get_project_root() or vim.fn.getcwd()
	local relative_path = target_path:gsub("^" .. vim.pesc(project_root) .. "/", "")

	return string.format([[You are editing files in a project. The user has made a request using an in-file prompt.

## Context
%s

## Current Working File
Path: %s
Project Root: %s

## User Request
%s

## Instructions

1. **Understand the intent**: Parse what the user wants to achieve
2. **Plan the changes**: Determine which files need to be created or modified
3. **Execute**: Use the available tools to:
   - Read files with `view` to understand existing code
   - Edit existing files with `edit` tool (provide exact old_string to match)
   - Create new files with `write` tool
   - Search for patterns with `grep` and `glob` if needed

4. **Validation**: Ensure your changes:
   - Preserve existing functionality
   - Add proper imports when referencing new files
   - Follow the project's coding style

## Important
- For the edit tool, you MUST first `view` the file to see its exact content
- The `old_string` in edit must match EXACTLY what's in the file
- If creating new files, ensure parent directories exist or create them
- After making changes, briefly summarize what was done

Now execute the user's request.]], file_context, relative_path, project_root, opts.prompt_content)
end

--- Remove the /@ @/ tags from the buffer after agent completes
---@param bufnr number
---@param start_line number
---@param end_line number
local function remove_prompt_tags(bufnr, start_line, end_line)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local new_lines = {}

	for i, line in ipairs(lines) do
		if i < start_line or i > end_line then
			-- Outside tag region - keep as is
			table.insert(new_lines, line)
		else
			-- Inside tag region - remove only the markers
			local cleaned = line:gsub("/%@", ""):gsub("%@/", "")
			-- Only include if there's content after removing markers
			if cleaned:match("%S") then
				table.insert(new_lines, cleaned)
			end
		end
	end

	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)
end

--- Run the inline agent
---@param opts InlineAgentOpts
function M.run(opts)
	-- Validate
	if not opts.bufnr or not vim.api.nvim_buf_is_valid(opts.bufnr) then
		if opts.on_complete then
			opts.on_complete(false, "Invalid buffer")
		end
		return
	end

	if not opts.prompt_content or opts.prompt_content == "" then
		if opts.on_complete then
			opts.on_complete(false, "Empty prompt")
		end
		return
	end

	-- Clear any previous pending changes
	clear_pending_changes()

	-- Log start
	pcall(function()
		local logs = require("codetyper.adapters.nvim.ui.logs")
		logs.add({
			type = "info",
			message = "In-file agent: prompt detected (preview mode)",
			data = { file = opts.target_path },
		})
	end)

	if opts.on_status then
		opts.on_status("Analyzing request...")
	end

	-- Build context
	local file_context = build_file_context(opts)
	local task = build_task(opts, file_context)

	-- Get the agent engine and tools module
	local agent_engine = require("codetyper.features.agents.engine")
	local tools_mod = require("codetyper.core.tools")

	-- Store original tool functions
	local original_write = tools_mod.get("write")
	local original_edit = tools_mod.get("edit")
	local original_write_func = original_write and original_write.func
	local original_edit_func = original_edit and original_edit.func

	-- Replace with preview handlers
	if original_write then
		original_write.func = preview_write
	end
	if original_edit then
		original_edit.func = preview_edit
	end

	-- Restore original tools function
	local function restore_tools()
		if original_write and original_write_func then
			original_write.func = original_write_func
		end
		if original_edit and original_edit_func then
			original_edit.func = original_edit_func
		end
	end

	-- Prepare files for context
	local context_files = {}
	if opts.target_path and vim.fn.filereadable(opts.target_path) == 1 then
		table.insert(context_files, opts.target_path)
	end
	if opts.attached_files then
		for _, file in ipairs(opts.attached_files) do
			if file.full_path and vim.fn.filereadable(file.full_path) == 1 then
				table.insert(context_files, file.full_path)
			end
		end
	end

	-- Log the agent start
	pcall(function()
		local logs = require("codetyper.adapters.nvim.ui.logs")
		logs.add({
			type = "info",
			message = "In-file agent: invoking agent engine (preview mode)",
			data = {
				task_preview = opts.prompt_content:sub(1, 100),
				context_files = #context_files,
			},
		})
	end)

	-- Store opts for use in completion handler
	local agent_opts = opts

	-- Run the agent
	agent_engine.run({
		task = task,
		files = context_files,
		agent = "coder",
		max_iterations = 15,

		on_status = function(status)
			if agent_opts.on_status then
				agent_opts.on_status(status)
			end
			pcall(function()
				local logs = require("codetyper.adapters.nvim.ui.logs")
				logs.add({ type = "info", message = "Agent: " .. status })
			end)
		end,

		on_tool_start = function(name, args)
			pcall(function()
				local logs = require("codetyper.adapters.nvim.ui.logs")
				local args_preview = ""
				if args.path then
					args_preview = args.path
				elseif args.pattern then
					args_preview = args.pattern
				end
				logs.add({
					type = "info",
					message = string.format("Tool: %s %s", name, args_preview),
				})
			end)
		end,

		on_tool_end = function(name, result, err)
			if err then
				pcall(function()
					local logs = require("codetyper.adapters.nvim.ui.logs")
					logs.add({
						type = "warning",
						message = string.format("Tool %s error: %s", name, err),
					})
				end)
			end
		end,

		on_file_change = function(path, action)
			pcall(function()
				local logs = require("codetyper.adapters.nvim.ui.logs")
				logs.add({
					type = "success",
					message = string.format("File %s: %s", action, vim.fn.fnamemodify(path, ":~:.")),
				})
			end)
		end,

		on_message = function(msg)
			-- Log assistant messages
			if msg.role == "assistant" and msg.content and type(msg.content) == "string" then
				pcall(function()
					local logs = require("codetyper.adapters.nvim.ui.logs")
					logs.add({
						type = "info",
						message = "Agent: " .. msg.content:sub(1, 200),
					})
				end)
			end
		end,

		on_complete = function(result, err)
			-- Always restore original tools first
			restore_tools()

			vim.schedule(function()
				if err then
					pcall(function()
						local logs = require("codetyper.adapters.nvim.ui.logs")
						logs.add({
							type = "error",
							message = "In-file agent failed: " .. err,
						})
					end)

					-- Clear pending changes on error
					clear_pending_changes()

					if agent_opts.on_complete then
						agent_opts.on_complete(false, err)
					end
					return
				end

				-- Check if we have any changes to review
				local change_count = 0
				for _ in pairs(pending_changes) do
					change_count = change_count + 1
				end

				if change_count == 0 then
					-- No file changes, just clean up
					pcall(function()
						local logs = require("codetyper.adapters.nvim.ui.logs")
						logs.add({
							type = "info",
							message = "In-file agent: completed (no file changes)",
						})
					end)

					remove_prompt_tags(agent_opts.bufnr, agent_opts.prompt_range.start_line, agent_opts.prompt_range.end_line)

					if agent_opts.on_complete then
						agent_opts.on_complete(true, nil)
					end
					return
				end

				-- Transfer changes to diff_review
				transfer_to_diff_review()
				clear_pending_changes()

				pcall(function()
					local logs = require("codetyper.adapters.nvim.ui.logs")
					logs.add({
						type = "success",
						message = string.format("In-file agent: %d file(s) ready for review", change_count),
					})
				end)

				-- Open diff review UI
				utils.notify(string.format("%d change(s) ready for review. Press 'a' to approve, 'A' for all, 'q' to close.", change_count), vim.log.levels.INFO)
				diff_review.open()

				-- Set up callback to clean up prompt tags after changes are applied
				-- We'll use an autocmd to detect when diff_review tab closes
				local review_group = vim.api.nvim_create_augroup("InlineAgentReview", { clear = true })
				vim.api.nvim_create_autocmd("TabClosed", {
					group = review_group,
					callback = function()
						-- Check how many changes were applied
						local entries = diff_review.get_entries()
						local applied_count = 0
						for _, entry in ipairs(entries) do
							if entry.applied then
								applied_count = applied_count + 1
							end
						end

						-- Clean up the autocmd group
						vim.api.nvim_del_augroup_by_name("InlineAgentReview")

						-- If any changes were applied, clean up the prompt tags
						if applied_count > 0 then
							vim.schedule(function()
								remove_prompt_tags(agent_opts.bufnr, agent_opts.prompt_range.start_line, agent_opts.prompt_range.end_line)

								-- Reload buffers that were modified
								for _, entry in ipairs(entries) do
									if entry.applied then
										local bufnr = vim.fn.bufnr(entry.path)
										if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
											vim.api.nvim_buf_call(bufnr, function()
												vim.cmd("edit!")
											end)
										end
									end
								end

								utils.notify(string.format("Applied %d change(s)", applied_count), vim.log.levels.INFO)

								if agent_opts.on_complete then
									agent_opts.on_complete(true, nil)
								end
							end)
						else
							utils.notify("No changes applied", vim.log.levels.INFO)
							if agent_opts.on_complete then
								agent_opts.on_complete(false, "No changes applied")
							end
						end
					end,
					once = true,
				})
			end)
		end,
	})
end

--- Check if a prompt should use inline agent mode vs patch mode
--- Returns true for complex multi-file operations
---@param prompt_content string
---@return boolean
function M.should_use_agent(prompt_content)
	local lower = prompt_content:lower()

	-- Patterns that indicate multi-file or complex operations (checked against lowercase)
	local agent_patterns = {
		"create.*file",
		"add.*file",
		"new.*file",
		"import.*from",
		"add.*import",
		"create.*style",
		"add.*style",
		"add.*css",
		"style.*on.*@",          -- "style on @path"
		"update.*and.*create",
		"modify.*and.*add",
		"refactor.*completely",
		"create.*class.*and",    -- "create a class ... and ..."
		"add.*class.*and",       -- "add class ... and ..."
	}

	for _, pattern in ipairs(agent_patterns) do
		if lower:match(pattern) then
			-- Log match for debugging
			pcall(function()
				local logs = require("codetyper.adapters.nvim.ui.logs")
				logs.add({
					type = "info",
					message = string.format("Agent pattern matched: %s", pattern),
				})
			end)
			return true
		end
	end

	-- Check for @ file references (check against ORIGINAL content to preserve case in paths)
	-- Pattern: @ followed by path-like characters
	if prompt_content:match("@[%w_][%w_/%-%.]+") then
		pcall(function()
			local logs = require("codetyper.adapters.nvim.ui.logs")
			logs.add({
				type = "info",
				message = "Agent pattern matched: @file_reference",
			})
		end)
		return true
	end

	-- If prompt contains code AND instructions, likely needs agent
	local has_code = prompt_content:match("function%s") or
		prompt_content:match("const%s") or
		prompt_content:match("class%s") or
		prompt_content:match("import%s") or
		prompt_content:match("export%s") or
		prompt_content:match("def%s") or
		prompt_content:match("return%s")

	local has_instruction = lower:match("add") or
		lower:match("create") or
		lower:match("modify") or
		lower:match("change") or
		lower:match("update") or
		lower:match("refactor")

	if has_code and has_instruction then
		pcall(function()
			local logs = require("codetyper.adapters.nvim.ui.logs")
			logs.add({
				type = "info",
				message = "Agent pattern matched: code + instruction",
			})
		end)
		return true
	end

	return false
end

return M
