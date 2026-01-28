---@mod codetyper.inject Code injection for Codetyper.nvim

local M = {}

local utils = require("codetyper.support.utils")

--- Import patterns for different languages
local import_patterns = {
	-- JavaScript/TypeScript
	javascript = {
		"^import%s+.+%s+from%s+['\"].-['\"]",
		"^import%s+['\"].-['\"]",
		"^import%s*{.-}%s*from%s*['\"].-['\"]",
		"^import%s*%*%s*as%s+%w+%s+from%s*['\"].-['\"]",
		"^import%s*{", -- Multi-line import start
		"^const%s+%w+%s*=%s*require%s*%(['\"].-['\"]%)",
		"^let%s+%w+%s*=%s*require%s*%(['\"].-['\"]%)",
		"^var%s+%w+%s*=%s*require%s*%(['\"].-['\"]%)",
	},
	-- Python
	python = {
		"^import%s+[%w_%.]+",
		"^from%s+[%w_%.]+%s+import%s+.+",
	},
	-- Lua
	lua = {
		"^local%s+%w+%s*=%s*require%s*%(?['\"].-['\"]%)?",
		"^%w+%s*=%s*require%s*%(?['\"].-['\"]%)?",
	},
	-- Go
	go = {
		'^import%s+".-"',
		"^import%s+%(",
	},
	-- Rust
	rust = {
		"^use%s+[%w_:]+",
		"^extern%s+crate%s+%w+",
	},
	-- C/C++
	c = {
		'^#include%s+[<"].-[>"]',
	},
}

-- Aliases for filetypes
import_patterns.typescript = import_patterns.javascript
import_patterns.tsx = import_patterns.javascript
import_patterns.jsx = import_patterns.javascript
import_patterns.ts = import_patterns.javascript
import_patterns.js = import_patterns.javascript
import_patterns.py = import_patterns.python
import_patterns.rs = import_patterns.rust
import_patterns.cpp = import_patterns.c
import_patterns.h = import_patterns.c
import_patterns.hpp = import_patterns.c

--- Parse code into imports and body
---@param code string The code to parse
---@param filetype string The filetype for import detection
---@return {imports: string[], body: string[]}
function M.parse_code(code, filetype)
	local result = { imports = {}, body = {} }
	local lines = vim.split(code, "\n", { plain = true })
	local patterns = import_patterns[filetype] or {}

	-- Handle empty code - ensure at least one body line
	if #lines == 1 and lines[1] == "" then
		return { imports = {}, body = { "" } }
	end

	local in_multiline_import = false
	local multiline_buffer = {}

	for _, line in ipairs(lines) do
		local is_import = false
		local trimmed = line:match("^%s*(.-)%s*$")

		-- Handle multi-line imports (e.g., Go import blocks, JS multi-line imports)
		if in_multiline_import then
			table.insert(multiline_buffer, line)
			-- Check for closing bracket/paren followed by optional 'from' clause and string
			if trimmed:match("^}%s*from%s*['\"]") or
				trimmed:match("^%)") or
				trimmed:match("^}") or
				trimmed:match("}%s*from%s*['\"].-['\"];?$") or
				trimmed:match("%;?$") and trimmed:match("from%s*['\"]") then
				in_multiline_import = false
				table.insert(result.imports, table.concat(multiline_buffer, "\n"))
				multiline_buffer = {}
			end
			is_import = true
		else
			-- Check each pattern
			for _, pattern in ipairs(patterns) do
				if trimmed:match(pattern) then
					is_import = true
					-- Check for multi-line start:
					-- - Has opening { but no closing }
					-- - Has opening ( but no closing )
					-- - Import with { that doesn't end with from 'string'
					local has_open_brace = trimmed:match("{") and not trimmed:match("}")
					local has_open_paren = trimmed:match("%(") and not trimmed:match("%)")
					local is_js_multiline = trimmed:match("^import%s*{") and not trimmed:match("from%s*['\"]")

					if has_open_brace or has_open_paren or is_js_multiline then
						in_multiline_import = true
						multiline_buffer = { line }
					else
						table.insert(result.imports, line)
					end
					break
				end
			end
		end

		if not is_import then
			table.insert(result.body, line)
		end
	end

	-- Trim leading empty lines from body
	while #result.body > 0 and result.body[1]:match("^%s*$") do
		table.remove(result.body, 1)
	end

	return result
end

--- Check if code has imports
---@param code string The code to check
---@param filetype string The filetype
---@return boolean
function M.has_imports(code, filetype)
	local parsed = M.parse_code(code, filetype)
	return #parsed.imports > 0
end

--- Normalize import for comparison (remove whitespace variations)
---@param import string
---@return string
local function normalize_import(import)
	-- Remove extra whitespace
	local normalized = import:gsub("%s+", " ")
	-- Remove trailing semicolons for comparison
	normalized = normalized:gsub(";%s*$", "")
	-- Normalize spaces around braces and parens: { x } -> {x}
	normalized = normalized:gsub("{%s*", "{")
	normalized = normalized:gsub("%s*}", "}")
	normalized = normalized:gsub("%(%s*", "(")
	normalized = normalized:gsub("%s*%)", ")")
	-- Normalize spaces around commas: x , y -> x,y
	normalized = normalized:gsub("%s*,%s*", ",")
	-- Trim
	normalized = normalized:match("^%s*(.-)%s*$")
	return normalized
end

--- Merge imports without duplicates
---@param existing string[] Existing imports
---@param new_imports string[] New imports to merge
---@return string[]
function M.merge_imports(existing, new_imports)
	local seen = {}
	local result = {}

	-- Add existing imports
	for _, imp in ipairs(existing) do
		local normalized = normalize_import(imp)
		if not seen[normalized] then
			seen[normalized] = true
			table.insert(result, imp)
		end
	end

	-- Add new imports if not duplicates
	for _, imp in ipairs(new_imports) do
		local normalized = normalize_import(imp)
		if not seen[normalized] then
			seen[normalized] = true
			table.insert(result, imp)
		end
	end

	return result
end

--- Sort imports by type (builtin, third-party, local)
---@param imports string[] Imports to sort
---@param language string The language
---@return string[]
function M.sort_imports(imports, language)
	-- Simple sort: builtins first, then third-party, then local
	local builtins = {}
	local third_party = {}
	local locals = {}

	local is_js = language == "javascript" or language == "typescript" or
		language == "js" or language == "ts" or language == "tsx" or language == "jsx"

	for _, imp in ipairs(imports) do
		if is_js then
			if imp:match("%.%/") or imp:match("%.%.%/") then
				-- Local import (starts with ./ or ../)
				table.insert(locals, imp)
			elseif imp:match("path") or imp:match("fs") or imp:match("http") or
				imp:match("crypto") or imp:match("os") or imp:match("util") then
				-- Node.js builtins
				table.insert(builtins, imp)
			else
				-- Third-party
				table.insert(third_party, imp)
			end
		else
			-- For other languages, just keep original order
			table.insert(third_party, imp)
		end
	end

	local result = {}
	for _, v in ipairs(builtins) do table.insert(result, v) end
	for _, v in ipairs(third_party) do table.insert(result, v) end
	for _, v in ipairs(locals) do table.insert(result, v) end

	return result
end

--- Smart code injection with import handling
--- Injects code into buffer, intelligently handling imports
---@param bufnr number Target buffer
---@param code string Code to inject
---@param opts table Options: strategy, range, filetype, sort_imports
---@return {imports_added: number, imports_merged: boolean, body_lines: number}
function M.inject(bufnr, code, opts)
	opts = opts or {}
	local strategy = opts.strategy or "append"
	local filetype = opts.filetype or vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":e")
	local range = opts.range

	-- Parse the generated code
	local parsed = M.parse_code(code, filetype)

	-- Get current buffer content
	local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local buf_content = table.concat(buf_lines, "\n")
	local buf_parsed = M.parse_code(buf_content, filetype)

	local imports_added = 0
	local imports_merged = false

	-- Handle imports: merge with existing at top of file
	if #parsed.imports > 0 then
		local merged_imports = M.merge_imports(buf_parsed.imports, parsed.imports)

		if opts.sort_imports then
			merged_imports = M.sort_imports(merged_imports, filetype)
		end

		imports_added = #merged_imports - #buf_parsed.imports
		imports_merged = #buf_parsed.imports > 0 and imports_added > 0

		-- If we have new imports, we need to insert them
		if imports_added > 0 then
			-- Find where imports end in the buffer
			local import_end_line = 0
			for i, line in ipairs(buf_lines) do
				local trimmed = line:match("^%s*(.-)%s*$")
				local is_import = false
				for _, pattern in ipairs(import_patterns[filetype] or {}) do
					if trimmed:match(pattern) then
						is_import = true
						break
					end
				end
				if is_import then
					import_end_line = i
				elseif import_end_line > 0 and not trimmed:match("^%s*$") then
					-- Non-empty, non-import line after imports
					break
				end
			end

			-- Insert merged imports at top (replacing old imports)
			if import_end_line > 0 then
				-- Replace existing imports section
				local new_lines = {}
				for _, imp in ipairs(merged_imports) do
					for _, l in ipairs(vim.split(imp, "\n")) do
						table.insert(new_lines, l)
					end
				end
				-- Add blank line after imports
				table.insert(new_lines, "")
				-- Add rest of file after imports
				for i = import_end_line + 1, #buf_lines do
					-- Skip leading blank lines right after imports
					if i == import_end_line + 1 and buf_lines[i]:match("^%s*$") then
						-- skip
					else
						table.insert(new_lines, buf_lines[i])
					end
				end
				buf_lines = new_lines
			else
				-- No existing imports, add at top
				local new_lines = {}
				for _, imp in ipairs(merged_imports) do
					for _, l in ipairs(vim.split(imp, "\n")) do
						table.insert(new_lines, l)
					end
				end
				table.insert(new_lines, "")
				for _, line in ipairs(buf_lines) do
					table.insert(new_lines, line)
				end
				buf_lines = new_lines
			end
		end
	end

	-- Handle body based on strategy
	local body_lines = parsed.body
	local body_line_count = #body_lines

	if strategy == "replace" and range then
		-- Replace the specified range with body
		local start_line = math.max(1, range.start_line)
		local end_line = range.end_line or start_line

		-- Adjust for any import changes at top of file
		local line_count = #buf_lines
		start_line = math.min(start_line, line_count)
		end_line = math.min(end_line, line_count)

		-- Build new content
		local new_lines = {}
		for i = 1, start_line - 1 do
			table.insert(new_lines, buf_lines[i])
		end
		for _, line in ipairs(body_lines) do
			table.insert(new_lines, line)
		end
		for i = end_line + 1, #buf_lines do
			table.insert(new_lines, buf_lines[i])
		end
		buf_lines = new_lines

	elseif strategy == "insert" and range then
		-- Insert at the specified line
		local insert_line = math.max(1, range.start_line)
		insert_line = math.min(insert_line, #buf_lines + 1)

		local new_lines = {}
		for i = 1, insert_line - 1 do
			table.insert(new_lines, buf_lines[i])
		end
		for _, line in ipairs(body_lines) do
			table.insert(new_lines, line)
		end
		for i = insert_line, #buf_lines do
			table.insert(new_lines, buf_lines[i])
		end
		buf_lines = new_lines

	elseif strategy == "prepend" then
		-- Prepend to start of file
		local new_lines = {}
		for _, line in ipairs(body_lines) do
			table.insert(new_lines, line)
		end
		-- Add blank line after prepended content
		table.insert(new_lines, "")
		for _, line in ipairs(buf_lines) do
			table.insert(new_lines, line)
		end
		buf_lines = new_lines

	elseif strategy == "append" then
		-- Append to end of file
		-- Add blank line before appended content if file doesn't end with blank
		if #buf_lines > 0 and buf_lines[#buf_lines] ~= "" then
			table.insert(buf_lines, "")
		end
		for _, line in ipairs(body_lines) do
			table.insert(buf_lines, line)
		end

	else
		-- Default: append to end
		for _, line in ipairs(body_lines) do
			table.insert(buf_lines, line)
		end
	end

	-- Apply to buffer
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, buf_lines)

	return {
		imports_added = imports_added,
		imports_merged = imports_merged,
		body_lines = body_line_count,
	}
end

--- Inject generated code into target file
---@param target_path string Path to target file
---@param code string Generated code
---@param prompt_type string Type of prompt (refactor, add, document, etc.)
function M.inject_code(target_path, code, prompt_type)
  local window = require("codetyper.adapters.nvim.windows")

  -- Normalize the target path
  target_path = vim.fn.fnamemodify(target_path, ":p")

  -- Get target buffer
  local target_buf = window.get_target_buf()

  if not target_buf or not vim.api.nvim_buf_is_valid(target_buf) then
    -- Try to find buffer by path
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      local buf_name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":p")
      if buf_name == target_path then
        target_buf = buf
        break
      end
    end
  end

  -- If still not found, open the file
  if not target_buf or not vim.api.nvim_buf_is_valid(target_buf) then
    -- Check if file exists
    if utils.file_exists(target_path) then
      vim.cmd("edit " .. vim.fn.fnameescape(target_path))
      target_buf = vim.api.nvim_get_current_buf()
      utils.notify("Opened target file: " .. vim.fn.fnamemodify(target_path, ":t"))
    else
      utils.notify("Target file not found: " .. target_path, vim.log.levels.ERROR)
      return
    end
  end

  if not target_buf then
    utils.notify("Target buffer not found", vim.log.levels.ERROR)
    return
  end

  utils.notify("Injecting code into: " .. vim.fn.fnamemodify(target_path, ":t"))

  -- Different injection strategies based on prompt type
  if prompt_type == "refactor" then
    M.inject_refactor(target_buf, code)
  elseif prompt_type == "add" then
    M.inject_add(target_buf, code)
  elseif prompt_type == "document" then
    M.inject_document(target_buf, code)
  else
    -- For generic, auto-add instead of prompting
    M.inject_add(target_buf, code)
  end
  
  -- Mark buffer as modified and save
  vim.bo[target_buf].modified = true
  
  -- Auto-save the target file
  vim.schedule(function()
    if vim.api.nvim_buf_is_valid(target_buf) then
      local wins = vim.fn.win_findbuf(target_buf)
      if #wins > 0 then
        vim.api.nvim_win_call(wins[1], function()
          vim.cmd("silent! write")
        end)
      end
    end
  end)
end

--- Inject code for refactor (replace entire file)
---@param bufnr number Buffer number
---@param code string Generated code
function M.inject_refactor(bufnr, code)
  local lines = vim.split(code, "\n", { plain = true })

  -- Save cursor position
  local cursor = nil
  local wins = vim.fn.win_findbuf(bufnr)
  if #wins > 0 then
    cursor = vim.api.nvim_win_get_cursor(wins[1])
  end

  -- Replace buffer content
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  -- Restore cursor position if possible
  if cursor then
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    cursor[1] = math.min(cursor[1], line_count)
    pcall(vim.api.nvim_win_set_cursor, wins[1], cursor)
  end

  utils.notify("Code refactored", vim.log.levels.INFO)
end

--- Inject code for add (append at cursor or end)
---@param bufnr number Buffer number
---@param code string Generated code
function M.inject_add(bufnr, code)
  local lines = vim.split(code, "\n", { plain = true })

  -- Get cursor position in target window
  local window = require("codetyper.adapters.nvim.windows")
  local target_win = window.get_target_win()

  local insert_line
  if target_win and vim.api.nvim_win_is_valid(target_win) then
    local cursor = vim.api.nvim_win_get_cursor(target_win)
    insert_line = cursor[1]
  else
    -- Append at end
    insert_line = vim.api.nvim_buf_line_count(bufnr)
  end

  -- Insert lines at position
  vim.api.nvim_buf_set_lines(bufnr, insert_line, insert_line, false, lines)

  utils.notify("Code added at line " .. (insert_line + 1), vim.log.levels.INFO)
end

--- Inject documentation
---@param bufnr number Buffer number
---@param code string Generated documentation
function M.inject_document(bufnr, code)
  -- Documentation typically goes above the current function/class
  -- For simplicity, insert at cursor position
  M.inject_add(bufnr, code)
  utils.notify("Documentation added", vim.log.levels.INFO)
end

--- Generic injection (prompt user for action)
---@param bufnr number Buffer number
---@param code string Generated code
function M.inject_generic(bufnr, code)
  local actions = {
    "Replace entire file",
    "Insert at cursor",
    "Append to end",
    "Copy to clipboard",
    "Cancel",
  }

  vim.ui.select(actions, {
    prompt = "How to inject the generated code?",
  }, function(choice)
    if not choice then
      return
    end

    if choice == "Replace entire file" then
      M.inject_refactor(bufnr, code)
    elseif choice == "Insert at cursor" then
      M.inject_add(bufnr, code)
    elseif choice == "Append to end" then
      local lines = vim.split(code, "\n", { plain = true })
      local line_count = vim.api.nvim_buf_line_count(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, line_count, line_count, false, lines)
      utils.notify("Code appended to end", vim.log.levels.INFO)
    elseif choice == "Copy to clipboard" then
      vim.fn.setreg("+", code)
      utils.notify("Code copied to clipboard", vim.log.levels.INFO)
    end
  end)
end

--- Preview code in a floating window before injection
---@param code string Generated code
---@param callback fun(action: string) Callback with selected action
function M.preview(code, callback)
  local codetyper = require("codetyper")
  local config = codetyper.get_config()

  local lines = vim.split(code, "\n", { plain = true })

  -- Create buffer for preview
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- Calculate window size
  local width = math.min(80, vim.o.columns - 10)
  local height = math.min(#lines + 2, vim.o.lines - 10)

  -- Create floating window
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = config.window.border,
    title = " Generated Code Preview ",
    title_pos = "center",
  })

  -- Set buffer options
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"

  -- Add keymaps for actions
  local opts = { buffer = buf, noremap = true, silent = true }

  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(win, true)
    callback("cancel")
  end, opts)

  vim.keymap.set("n", "<CR>", function()
    vim.api.nvim_win_close(win, true)
    callback("inject")
  end, opts)

  vim.keymap.set("n", "y", function()
    vim.fn.setreg("+", code)
    utils.notify("Copied to clipboard")
  end, opts)

  -- Show help in command line
  vim.api.nvim_echo({
    { "Press ", "Normal" },
    { "<CR>", "Keyword" },
    { " to inject, ", "Normal" },
    { "y", "Keyword" },
    { " to copy, ", "Normal" },
    { "q", "Keyword" },
    { " to cancel", "Normal" },
  }, false, {})
end

return M
