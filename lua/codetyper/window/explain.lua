--- Explain window — shows LLM explanation in a right-side markdown panel
local M = {}

local flog = require("codetyper.support.flog") -- TODO: remove after debugging

--- Active explain window state
local state = {
  buf = nil,
  win = nil,
  loading_timer = nil,
  loading_dots = 0,
}

--- Stop the loading animation
local function stop_loading()
  if state.loading_timer then
    state.loading_timer:stop()
    state.loading_timer = nil
  end
end

--- Start the loading animation (. → .. → ... → .)
local function start_loading()
  stop_loading()
  state.loading_dots = 0
  state.loading_timer = vim.loop.new_timer()
  state.loading_timer:start(0, 400, vim.schedule_wrap(function()
    if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
      stop_loading()
      return
    end
    state.loading_dots = (state.loading_dots % 3) + 1
    local dots = string.rep(".", state.loading_dots)
    vim.bo[state.buf].modifiable = true
    vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, {
      "# Thinking" .. dots,
      "",
      "Loading" .. dots,
    })
    vim.bo[state.buf].modifiable = false
  end))
end

--- Close the explain window
function M.close()
  stop_loading()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
  state.buf = nil
end

--- Show explanation text in a right-side vertical split
---@param title string Window title
---@param content string Markdown content to display
---@param filetype string|nil Source filetype for context (shown in title)
function M.show(title, content, filetype)
  flog.info("explain", "showing: " .. title:sub(1, 50)) -- TODO: remove after debugging

  -- Close existing explain window
  M.close()

  -- Create buffer
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].buftype = "nofile"
  vim.bo[state.buf].bufhidden = "wipe"
  vim.bo[state.buf].swapfile = false
  vim.bo[state.buf].filetype = "markdown"

  -- Set initial content — start loading animation if content is a placeholder
  local is_loading = content:match("^Loading") or content:match("^Thinking")
  if is_loading then
    vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, { "# Thinking.", "", "Loading." })
    vim.bo[state.buf].modifiable = false
    start_loading()
  else
    local lines = vim.split(content, "\n", { plain = true })
    vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
    vim.bo[state.buf].modifiable = false
  end

  -- Open as right vertical split (40% width)
  local width = math.max(40, math.floor(vim.o.columns * 0.4))
  vim.cmd("botright vsplit")
  state.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.win, state.buf)
  vim.api.nvim_win_set_width(state.win, width)

  -- Window options
  vim.wo[state.win].wrap = true
  vim.wo[state.win].linebreak = true
  vim.wo[state.win].number = false
  vim.wo[state.win].relativenumber = false
  vim.wo[state.win].signcolumn = "no"
  vim.wo[state.win].cursorline = false
  vim.wo[state.win].spell = false
  vim.wo[state.win].foldmethod = "manual"
  vim.wo[state.win].conceallevel = 2

  -- Keymaps for the explain buffer
  local opts = { buffer = state.buf, silent = true }
  vim.keymap.set("n", "q", function()
    M.close()
  end, opts)
  vim.keymap.set("n", "<Esc>", function()
    M.close()
  end, opts)

  -- Return focus to the original window
  vim.cmd("wincmd p")
end

--- Check if explain window is open
---@return boolean
function M.is_open()
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

--- Update content of an open explain window
---@param content string New markdown content
function M.update(content)
  stop_loading()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end
  local lines = vim.split(content, "\n", { plain = true })
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
end

--- Internal state for accumulating tool results
M._last_content = ""

return M
