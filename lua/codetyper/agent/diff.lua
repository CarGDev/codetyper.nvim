---@mod codetyper.agent.diff Diff preview UI for agent changes
---
--- Shows diff previews for file changes and bash command approvals.

local M = {}

--- Show a diff preview for file changes
---@param diff_data table { path: string, original: string, modified: string, operation: string }
---@param callback fun(approved: boolean) Called with user decision
function M.show_diff(diff_data, callback)
  local original_lines = vim.split(diff_data.original, "\n", { plain = true })
  local modified_lines

  -- For delete operations, show a clear message
  if diff_data.operation == "delete" then
    modified_lines = {
      "",
      "  FILE WILL BE DELETED",
      "",
      "  Reason: " .. (diff_data.reason or "No reason provided"),
      "",
    }
  else
    modified_lines = vim.split(diff_data.modified, "\n", { plain = true })
  end

  -- Calculate window dimensions
  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.7)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  -- Create left buffer (original)
  local left_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(left_buf, 0, -1, false, original_lines)
  vim.bo[left_buf].modifiable = false
  vim.bo[left_buf].bufhidden = "wipe"

  -- Create right buffer (modified)
  local right_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(right_buf, 0, -1, false, modified_lines)
  vim.bo[right_buf].modifiable = false
  vim.bo[right_buf].bufhidden = "wipe"

  -- Set filetype for syntax highlighting based on file extension
  local ext = vim.fn.fnamemodify(diff_data.path, ":e")
  if ext and ext ~= "" then
    vim.bo[left_buf].filetype = ext
    vim.bo[right_buf].filetype = ext
  end

  -- Create left window (original)
  local half_width = math.floor((width - 1) / 2)
  local left_win = vim.api.nvim_open_win(left_buf, true, {
    relative = "editor",
    width = half_width,
    height = height - 2,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " ORIGINAL ",
    title_pos = "center",
  })

  -- Create right window (modified)
  local right_win = vim.api.nvim_open_win(right_buf, false, {
    relative = "editor",
    width = half_width,
    height = height - 2,
    row = row,
    col = col + half_width + 1,
    style = "minimal",
    border = "rounded",
    title = diff_data.operation == "delete" and " ⚠️ DELETE " or (" MODIFIED [" .. diff_data.operation .. "] "),
    title_pos = "center",
  })

  -- Enable diff mode in both windows
  vim.api.nvim_win_call(left_win, function()
    vim.cmd("diffthis")
  end)
  vim.api.nvim_win_call(right_win, function()
    vim.cmd("diffthis")
  end)

  -- Sync scrolling
  vim.wo[left_win].scrollbind = true
  vim.wo[right_win].scrollbind = true
  vim.wo[left_win].cursorbind = true
  vim.wo[right_win].cursorbind = true

  -- Track if callback was already called
  local callback_called = false

  -- Close function
  local function close_and_respond(approved)
    if callback_called then
      return
    end
    callback_called = true

    -- Disable diff mode
    pcall(function()
      vim.api.nvim_win_call(left_win, function()
        vim.cmd("diffoff")
      end)
    end)
    pcall(function()
      vim.api.nvim_win_call(right_win, function()
        vim.cmd("diffoff")
      end)
    end)

    -- Close windows
    pcall(vim.api.nvim_win_close, left_win, true)
    pcall(vim.api.nvim_win_close, right_win, true)

    -- Call callback
    vim.schedule(function()
      callback(approved)
    end)
  end

  -- Set up keymaps for both buffers
  local keymap_opts = { noremap = true, silent = true, nowait = true }

  for _, buf in ipairs({ left_buf, right_buf }) do
    -- Approve
    vim.keymap.set("n", "y", function()
      close_and_respond(true)
    end, vim.tbl_extend("force", keymap_opts, { buffer = buf }))
    vim.keymap.set("n", "<CR>", function()
      close_and_respond(true)
    end, vim.tbl_extend("force", keymap_opts, { buffer = buf }))

    -- Reject
    vim.keymap.set("n", "n", function()
      close_and_respond(false)
    end, vim.tbl_extend("force", keymap_opts, { buffer = buf }))
    vim.keymap.set("n", "q", function()
      close_and_respond(false)
    end, vim.tbl_extend("force", keymap_opts, { buffer = buf }))
    vim.keymap.set("n", "<Esc>", function()
      close_and_respond(false)
    end, vim.tbl_extend("force", keymap_opts, { buffer = buf }))

    -- Switch between windows
    vim.keymap.set("n", "<Tab>", function()
      local current = vim.api.nvim_get_current_win()
      if current == left_win then
        vim.api.nvim_set_current_win(right_win)
      else
        vim.api.nvim_set_current_win(left_win)
      end
    end, vim.tbl_extend("force", keymap_opts, { buffer = buf }))
  end

  -- Show help message
  vim.api.nvim_echo({
    { "Diff: ", "Normal" },
    { diff_data.path, "Directory" },
    { " | ", "Normal" },
    { "y/<CR>", "Keyword" },
    { " approve  ", "Normal" },
    { "n/q/<Esc>", "Keyword" },
    { " reject  ", "Normal" },
    { "<Tab>", "Keyword" },
    { " switch panes", "Normal" },
  }, false, {})
end

---@alias BashApprovalResult {approved: boolean, permission_level: string|nil}

--- Show approval dialog for bash commands with permission levels
---@param command string The bash command to approve
---@param callback fun(result: BashApprovalResult) Called with user decision
function M.show_bash_approval(command, callback)
  local permissions = require("codetyper.agent.permissions")

  -- Check if command is auto-approved
  local perm_result = permissions.check_bash_permission(command)
  if perm_result.auto and perm_result.allowed then
    vim.schedule(function()
      callback({ approved = true, permission_level = "auto" })
    end)
    return
  end

  -- Create approval dialog with options
  local lines = {
    "",
    "  BASH COMMAND APPROVAL",
    "  " .. string.rep("─", 56),
    "",
    "  Command:",
    "  $ " .. command,
    "",
  }

  -- Add warning for dangerous commands
  if not perm_result.allowed and perm_result.reason ~= "Requires approval" then
    table.insert(lines, "  ⚠️  WARNING: " .. perm_result.reason)
    table.insert(lines, "")
  end

  table.insert(lines, "  " .. string.rep("─", 56))
  table.insert(lines, "")
  table.insert(lines, "  [y] Allow once           - Execute this command")
  table.insert(lines, "  [s] Allow this session   - Auto-allow until restart")
  table.insert(lines, "  [a] Add to allow list    - Always allow this command")
  table.insert(lines, "  [n] Reject               - Cancel execution")
  table.insert(lines, "")
  table.insert(lines, "  " .. string.rep("─", 56))
  table.insert(lines, "  Press key to choose | [q] or [Esc] to cancel")
  table.insert(lines, "")

  local width = math.max(65, #command + 15)
  local height = #lines

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " Approve Command? ",
    title_pos = "center",
  })

  -- Apply highlighting
  vim.api.nvim_buf_add_highlight(buf, -1, "Title", 1, 0, -1)
  vim.api.nvim_buf_add_highlight(buf, -1, "String", 5, 0, -1)

  -- Highlight options
  for i, line in ipairs(lines) do
    if line:match("^%s+%[y%]") then
      vim.api.nvim_buf_add_highlight(buf, -1, "DiagnosticOk", i - 1, 0, -1)
    elseif line:match("^%s+%[s%]") then
      vim.api.nvim_buf_add_highlight(buf, -1, "DiagnosticInfo", i - 1, 0, -1)
    elseif line:match("^%s+%[a%]") then
      vim.api.nvim_buf_add_highlight(buf, -1, "DiagnosticHint", i - 1, 0, -1)
    elseif line:match("^%s+%[n%]") then
      vim.api.nvim_buf_add_highlight(buf, -1, "DiagnosticError", i - 1, 0, -1)
    elseif line:match("⚠️") then
      vim.api.nvim_buf_add_highlight(buf, -1, "DiagnosticWarn", i - 1, 0, -1)
    end
  end

  local callback_called = false

  local function close_and_respond(approved, permission_level)
    if callback_called then
      return
    end
    callback_called = true

    -- Grant permission if approved with session or list level
    if approved and permission_level then
      permissions.grant_permission(command, permission_level)
    end

    pcall(vim.api.nvim_win_close, win, true)

    vim.schedule(function()
      callback({ approved = approved, permission_level = permission_level })
    end)
  end

  local keymap_opts = { buffer = buf, noremap = true, silent = true, nowait = true }

  -- Allow once
  vim.keymap.set("n", "y", function()
    close_and_respond(true, "allow")
  end, keymap_opts)
  vim.keymap.set("n", "<CR>", function()
    close_and_respond(true, "allow")
  end, keymap_opts)

  -- Allow this session
  vim.keymap.set("n", "s", function()
    close_and_respond(true, "allow_session")
  end, keymap_opts)

  -- Add to allow list
  vim.keymap.set("n", "a", function()
    close_and_respond(true, "allow_list")
  end, keymap_opts)

  -- Reject
  vim.keymap.set("n", "n", function()
    close_and_respond(false, nil)
  end, keymap_opts)
  vim.keymap.set("n", "q", function()
    close_and_respond(false, nil)
  end, keymap_opts)
  vim.keymap.set("n", "<Esc>", function()
    close_and_respond(false, nil)
  end, keymap_opts)
end

--- Show approval dialog for bash commands (simple version for backward compatibility)
---@param command string The bash command to approve
---@param callback fun(approved: boolean) Called with user decision
function M.show_bash_approval_simple(command, callback)
  M.show_bash_approval(command, function(result)
    callback(result.approved)
  end)
end

return M
