---@mod codetyper.agent.diff Diff preview UI for agent changes
---
--- Shows diff previews for file changes and bash command approvals.

local M = {}

local api = vim.api
local fn = vim.fn
local fmt = string.format

local function is_callable(v)
  return type(v) == "function"
end

local function safe_win_valid(win)
  return type(win) == "number" and pcall(api.nvim_win_get_config, win)
end

local function create_scratch_buf(lines)
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines or {})
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  return buf
end

local function open_centered_win(buf, opts)
  local cols = vim.o.columns
  local lines = vim.o.lines
  local width = opts.width
  local height = opts.height
  local row = math.floor((lines - height) / 2)
  local col = math.floor((cols - width) / 2)
  local win_opts = vim.tbl_extend("force", {
    relative = "editor",
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title_pos = "center",
  }, opts)
  return api.nvim_open_win(buf, opts.focus and true or false, win_opts)
end

--- Show a diff preview for file changes
---@param diff_data table { path: string, original: string, modified: string, operation: string, reason: string|nil }
---@param callback fun(approved: boolean) Called with user decision
function M.show_diff(diff_data, callback)
  if type(diff_data) ~= "table" or not diff_data.path or not is_callable(callback) then
    return
  end

  local original_lines = vim.split(diff_data.original or "", "\n", { plain = true })
  local modified_lines

  if diff_data.operation == "delete" then
    modified_lines = {
      "",
      "  FILE WILL BE DELETED",
      "",
      "  Reason: " .. (diff_data.reason or "No reason provided"),
      "",
    }
  else
    modified_lines = vim.split(diff_data.modified or "", "\n", { plain = true })
  end

  -- Window dimensions
  local win_width = math.floor(vim.o.columns * 0.8)
  local win_height = math.floor(vim.o.lines * 0.7)
  local half_width = math.floor((win_width - 1) / 2)
  local content_height = math.max(3, win_height - 2)

  -- Buffers
  local left_buf = create_scratch_buf(original_lines)
  local right_buf = create_scratch_buf(modified_lines)

  -- Filetype detection
  local ext = fn.fnamemodify(diff_data.path, ":e")
  if ext and ext ~= "" then
    vim.bo[left_buf].filetype = ext
    vim.bo[right_buf].filetype = ext
  end

  -- Windows
  local left_win = open_centered_win(left_buf, {
    focus = true,
    width = half_width,
    height = content_height,
    col = math.floor((vim.o.columns - win_width) / 2),
    row = math.floor((vim.o.lines - win_height) / 2),
    title = " ORIGINAL ",
  })

  local right_win = open_centered_win(right_buf, {
    focus = false,
    width = half_width,
    height = content_height,
    col = math.floor((vim.o.columns - win_width) / 2) + half_width + 1,
    row = math.floor((vim.o.lines - win_height) / 2),
    title = diff_data.operation == "delete" and " ⚠️ DELETE "
      or fmt(" MODIFIED [%s] ", tostring(diff_data.operation or "modified")),
  })

  -- Enable diff mode safely
  pcall(function()
    api.nvim_win_call(left_win, function()
      vim.cmd("diffthis")
    end)
  end)
  pcall(function()
    api.nvim_win_call(right_win, function()
      vim.cmd("diffthis")
    end)
  end)

  -- Sync scrolling and cursors
  if safe_win_valid(left_win) and safe_win_valid(right_win) then
    vim.wo[left_win].scrollbind = true
    vim.wo[right_win].scrollbind = true
    vim.wo[left_win].cursorbind = true
    vim.wo[right_win].cursorbind = true
  end

  local callback_called = false
  local function cleanup_diff()
    pcall(function()
      if safe_win_valid(left_win) then
        api.nvim_win_call(left_win, function()
          vim.cmd("diffoff")
        end)
      end
    end)
    pcall(function()
      if safe_win_valid(right_win) then
        api.nvim_win_call(right_win, function()
          vim.cmd("diffoff")
        end)
      end
    end)
    pcall(api.nvim_win_close, left_win, true)
    pcall(api.nvim_win_close, right_win, true)
  end

  local function close_and_respond(approved)
    if callback_called then
      return
    end
    callback_called = true
    cleanup_diff()
    vim.schedule(function()
      callback(approved)
    end)
  end

  -- Keymaps
  local base_opts = { noremap = true, silent = true, nowait = true }
  for _, buf in ipairs({ left_buf, right_buf }) do
    local opts = vim.tbl_extend("force", base_opts, { buffer = buf })

    vim.keymap.set("n", "y", function()
      close_and_respond(true)
    end, opts)
    vim.keymap.set("n", "<CR>", function()
      close_and_respond(true)
    end, opts)

    vim.keymap.set("n", "n", function()
      close_and_respond(false)
    end, opts)
    vim.keymap.set("n", "q", function()
      close_and_respond(false)
    end, opts)
    vim.keymap.set("n", "<Esc>", function()
      close_and_respond(false)
    end, opts)

    vim.keymap.set("n", "<Tab>", function()
      local current = api.nvim_get_current_win()
      if current == left_win and safe_win_valid(right_win) then
        api.nvim_set_current_win(right_win)
      elseif safe_win_valid(left_win) then
        api.nvim_set_current_win(left_win)
      end
    end, opts)
  end

  -- Help message (with path substitution)
  local help_msg = require("codetyper.prompts.agents.diff").diff_help or {}
  local final_help = {}
  for _, item in ipairs(help_msg) do
    if type(item) == "table" and item[1] == "{path}" then
      table.insert(final_help, { diff_data.path, item[2] })
    else
      table.insert(final_help, item)
    end
  end
  if #final_help > 0 then
    api.nvim_echo(final_help, false, {})
  end
end

---@alias BashApprovalResult {approved: boolean, permission_level: string|nil}

--- Show approval dialog for bash commands with permission levels
---@param command string The bash command to approve
---@param callback fun(result: BashApprovalResult) Called with user decision
function M.show_bash_approval(command, callback)
  if type(command) ~= "string" or not is_callable(callback) then
    return
  end

  local permissions = require("codetyper.features.agents.permissions")
  local perm_result = permissions.check_bash_permission(command)

  if perm_result.auto and perm_result.allowed then
    vim.schedule(function()
      callback({ approved = true, permission_level = "auto" })
    end)
    return
  end

  local approval_prompts = require("codetyper.prompts.agents.diff").bash_approval
  approval_prompts = approval_prompts
    or {
      title = "Approve command",
      divider = "----------------",
      command_label = "Command:",
      warning_prefix = "Warning: ",
      options = { "  [y] Allow once", "  [s] Allow this session", "  [a] Add to allow list", "  [n] Deny" },
      cancel_hint = "Press q or <Esc> to cancel",
    }

  local buf_lines = {
    "",
    approval_prompts.title,
    approval_prompts.divider,
    "",
    approval_prompts.command_label,
    "  $ " .. command,
    "",
  }

  if not perm_result.allowed and perm_result.reason and perm_result.reason ~= "Requires approval" then
    table.insert(buf_lines, approval_prompts.warning_prefix .. perm_result.reason)
    table.insert(buf_lines, "")
  end

  table.insert(buf_lines, approval_prompts.divider)
  table.insert(buf_lines, "")
  for _, opt in ipairs(approval_prompts.options or {}) do
    table.insert(buf_lines, opt)
  end
  table.insert(buf_lines, "")
  table.insert(buf_lines, approval_prompts.divider)
  table.insert(buf_lines, approval_prompts.cancel_hint)
  table.insert(buf_lines, "")

  local width = math.max(65, #command + 15)
  local buf = create_scratch_buf(buf_lines)
  local height = #buf_lines

  local win = api.nvim_open_win(buf, true, {
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

  pcall(api.nvim_buf_add_highlight, buf, -1, "Title", 1, 0, -1)
  pcall(api.nvim_buf_add_highlight, buf, -1, "String", 5, 0, -1)

  for i, line in ipairs(buf_lines) do
    if line:match("^%s*%[y%]") then
      api.nvim_buf_add_highlight(buf, -1, "DiagnosticOk", i - 1, 0, -1)
    elseif line:match("^%s*%[s%]") then
      api.nvim_buf_add_highlight(buf, -1, "DiagnosticInfo", i - 1, 0, -1)
    elseif line:match("^%s*%[a%]") then
      api.nvim_buf_add_highlight(buf, -1, "DiagnosticHint", i - 1, 0, -1)
    elseif line:match("^%s*%[n%]") then
      api.nvim_buf_add_highlight(buf, -1, "DiagnosticError", i - 1, 0, -1)
    elseif line:match("⚠️") then
      api.nvim_buf_add_highlight(buf, -1, "DiagnosticWarn", i - 1, 0, -1)
    end
  end

  local callback_called = false
  local function close_and_respond(approved, permission_level)
    if callback_called then
      return
    end
    callback_called = true

    if approved and permission_level then
      permissions.grant_permission(command, permission_level)
    end

    pcall(api.nvim_win_close, win, true)
    vim.schedule(function()
      callback({ approved = approved, permission_level = permission_level })
    end)
  end

  local keymap_opts = { buffer = buf, noremap = true, silent = true, nowait = true }

  local mappings = {
    { "y", true, "allow" },
    { "<CR>", true, "allow" },
    { "s", true, "allow_session" },
    { "a", true, "allow_list" },
    { "n", false, nil },
    { "q", false, nil },
    { "<Esc>", false, nil },
  }

  for _, m in ipairs(mappings) do
    vim.keymap.set("n", m[1], function()
      close_and_respond(m[2], m[3])
    end, keymap_opts)
  end
end

--- Show approval dialog for bash commands (simple version for backward compatibility)
---@param command string The bash command to approve
---@param callback fun(approved: boolean) Called with user decision
function M.show_bash_approval_simple(command, callback)
  M.show_bash_approval(command, function(result)
    callback(result and result.approved)
  end)
end

return M
