---@mod codetyper.inject Code injection for Codetyper.nvim

local M = {}

local utils = require("codetyper.utils")

--- Inject generated code into target file
---@param target_path string Path to target file
---@param code string Generated code
---@param prompt_type string Type of prompt (refactor, add, document, etc.)
function M.inject_code(target_path, code, prompt_type)
  local window = require("codetyper.window")

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
  local window = require("codetyper.window")
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
