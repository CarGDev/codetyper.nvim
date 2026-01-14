---@mod codetyper.agent.diff Diff preview UI for agent changes
---
--- Shows diff previews for file changes and bash command approvals.

local M = {}

--- Show a diff preview for file changes
---@param diff_data table { path: string, original: string, modified: string, operation: string }
---@param callback fun(approved: boolean) Called with user decision
function M.show_diff(diff_data, callback)
  local original_lines = vim.split(diff_data.original, "\n", { plain = true })
  local modified_lines = vim.split(diff_data.modified, "\n", { plain = true })

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
    title = " MODIFIED [" .. diff_data.operation .. "] ",
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

--- Show approval dialog for bash commands
---@param command string The bash command to approve
---@param callback fun(approved: boolean) Called with user decision
function M.show_bash_approval(command, callback)
  -- Create a simple floating window for bash approval
  local lines = {
    "",
    "  BASH COMMAND APPROVAL",
    "  " .. string.rep("-", 50),
    "",
    "  Command:",
    "  $ " .. command,
    "",
    "  " .. string.rep("-", 50),
    "  Press [y] or [Enter] to execute",
    "  Press [n], [q], or [Esc] to cancel",
    "",
  }

  local width = math.max(60, #command + 10)
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

  -- Apply some highlighting
  vim.api.nvim_buf_add_highlight(buf, -1, "Title", 1, 0, -1)
  vim.api.nvim_buf_add_highlight(buf, -1, "String", 5, 0, -1)

  local callback_called = false

  local function close_and_respond(approved)
    if callback_called then
      return
    end
    callback_called = true

    pcall(vim.api.nvim_win_close, win, true)

    vim.schedule(function()
      callback(approved)
    end)
  end

  local keymap_opts = { buffer = buf, noremap = true, silent = true, nowait = true }

  -- Approve
  vim.keymap.set("n", "y", function()
    close_and_respond(true)
  end, keymap_opts)
  vim.keymap.set("n", "<CR>", function()
    close_and_respond(true)
  end, keymap_opts)

  -- Reject
  vim.keymap.set("n", "n", function()
    close_and_respond(false)
  end, keymap_opts)
  vim.keymap.set("n", "q", function()
    close_and_respond(false)
  end, keymap_opts)
  vim.keymap.set("n", "<Esc>", function()
    close_and_respond(false)
  end, keymap_opts)
end

return M
