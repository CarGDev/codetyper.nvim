---@mod codetyper.features.agents.inline In-file agent mode
---@brief [[
--- Handles /@ ... @/ prompts as full agentic interactions, not patches.
--- The agent can read files, write new files, edit existing files, and
--- materialize a complete program state from intent.
--- Changes are collected and shown in a diff review UI for approval.
---@brief ]]

local M = {}

local utils = require("codetyper.support.utils")
local path_utils = require("codetyper.support.path")
local string_match = require("codetyper.support.string_match")
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

	local path = path_utils.resolve(input.path)
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

	local path = path_utils.resolve(input.path)
	local old_str = string_match.normalize_line_endings(input.old_string)
	local new_str = string_match.normalize_line_endings(input.new_string)

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

	content = string_match.normalize_line_endings(content)

	-- Find match using shared multi-strategy matching
	local match = string_match.find_match(content, old_str)
	if not match then
		return nil, "old_string not found in file"
	end

	-- Compute new content
	local new_content = content:sub(1, match.start_pos - 1) .. new_str .. content:sub(match.end_pos + 1)

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

--- Remove ALL /@ @/ tags from the buffer after agent completes
--- This version scans the entire buffer to handle cases where line numbers may have changed
---@param bufnr number
---@return number Number of tag regions removed
local function remove_prompt_tags(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return 0
	end

	local removed = 0
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	-- Find and remove all /@ ... @/ regions (can be multiline)
	local i = 1
	while i <= #lines do
		local line = lines[i]
		local open_start = line:find("/@")

		if open_start then
			-- Found an opening tag, look for closing tag
			local close_end = nil
			local close_line = i

			-- Check if closing tag is on same line
			local after_open = line:sub(open_start + 2)
			local same_line_close = after_open:find("@/")
			if same_line_close then
				-- Single line tag - remove just this portion
				local before = line:sub(1, open_start - 1)
				local after = line:sub(open_start + 2 + same_line_close + 1)
				lines[i] = before .. after
				-- If line is now empty or just whitespace, remove it
				if lines[i]:match("^%s*$") then
					table.remove(lines, i)
				else
					i = i + 1
				end
				removed = removed + 1
			else
				-- Multi-line tag - find the closing line
				for j = i, #lines do
					if lines[j]:find("@/") then
						close_line = j
						close_end = lines[j]:find("@/")
						break
					end
				end

				if close_end then
					-- Remove lines from i to close_line
					-- Keep content before /@ on first line and after @/ on last line
					local before = lines[i]:sub(1, open_start - 1)
					local after = lines[close_line]:sub(close_end + 2)

					-- Remove the lines containing the tag
					for _ = i, close_line do
						table.remove(lines, i)
					end

					-- If there's content to keep, insert it back
					local remaining = (before .. after):match("^%s*(.-)%s*$")
					if remaining and remaining ~= "" then
						table.insert(lines, i, remaining)
						i = i + 1
					end

					removed = removed + 1
				else
					-- No closing tag found, skip this line
					i = i + 1
				end
			end
		else
			i = i + 1
		end
	end

	if removed > 0 then
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	end

	return removed
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

					remove_prompt_tags(agent_opts.bufnr)

					-- Save the buffer to persist tag removal
					if vim.api.nvim_buf_is_valid(agent_opts.bufnr) then
						vim.api.nvim_buf_call(agent_opts.bufnr, function()
							vim.cmd("silent write")
						end)
					end

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
								-- Get source buffer's path
								local source_path = vim.api.nvim_buf_get_name(agent_opts.bufnr)
								local source_was_modified = false

								-- Reload all modified buffers
								for _, entry in ipairs(entries) do
									if entry.applied then
										local entry_bufnr = vim.fn.bufnr(entry.path)
										if entry_bufnr ~= -1 and vim.api.nvim_buf_is_valid(entry_bufnr) then
											vim.api.nvim_buf_call(entry_bufnr, function()
												vim.cmd("edit!")
											end)
										end
										-- Check if source buffer was modified
										if entry.path == source_path then
											source_was_modified = true
										end
									end
								end

								-- Now remove prompt tags from source buffer
								-- (they may still exist if agent preserved them, or if source wasn't modified)
								local tags_removed = remove_prompt_tags(agent_opts.bufnr)

								-- Save the source buffer to persist tag removal (only if we removed tags)
								if tags_removed > 0 and vim.api.nvim_buf_is_valid(agent_opts.bufnr) then
									vim.api.nvim_buf_call(agent_opts.bufnr, function()
										vim.cmd("silent write")
									end)
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
