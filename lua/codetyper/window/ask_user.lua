--- Safe, serialized ask-user interaction for agent tool calls.

local local_cli = require("codetyper.core.agent.tools.local_cli")

local M = {}

M.MAX_QUESTION_LENGTH = 1000
M.MAX_OPTION_LENGTH = 200
M.MAX_OPTIONS = 8
M.MAX_WIDTH = 80
M.MAX_HEIGHT = 20
M.MAX_QUESTION_LINES = 6

local state = {
  active = nil,
  queue = {},
  next_id = 0,
  resetting = false,
}

local function safe_error(value, fallback)
  return local_cli.safe_error(value, fallback or "ask-user request failed")
end

local function result(status, data, error, stale, metadata)
  return {
    status = status,
    data = data,
    error = error and safe_error(error, "ask-user request failed") or nil,
    stale = stale == true,
    metadata = metadata,
  }
end

local function callback_once(callback, value)
  if type(callback) ~= "function" then
    return
  end
  pcall(callback, value)
end

local function normalize_text(value, field, max_length)
  if type(value) ~= "string" then
    return nil, field .. " must be a string"
  end

  local normalized = value:gsub("^%s+", ""):gsub("%s+$", "")
  if normalized == "" then
    return nil, field .. " must be non-empty text"
  end
  if normalized:find("[%z\1-\31\127]") then
    return nil, field .. " contains invalid control characters"
  end
  if #normalized > max_length then
    return nil, field .. " is too long"
  end
  return normalized, nil
end

local function validate_options(options)
  if type(options) ~= "table" or #options < 1 or #options > M.MAX_OPTIONS then
    return nil, "options must contain 1 to 8 strings"
  end

  local normalized = {}
  for index = 1, #options do
    local option, option_error = normalize_text(options[index], "option", M.MAX_OPTION_LENGTH)
    if not option then
      return nil, option_error
    end
    normalized[index] = option
  end

  for key in pairs(options) do
    if type(key) ~= "number" or key < 1 or key > #options or key ~= math.floor(key) then
      return nil, "options must be a contiguous list"
    end
  end

  return normalized, nil
end

--- Normalize and validate one ask-user request without opening a window.
---@param args table
---@return table|nil normalized
---@return string|nil error
function M.validate(args)
  if type(args) ~= "table" then
    return nil, "tool arguments must be an object"
  end

  for key in pairs(args) do
    if key ~= "question" and key ~= "options" then
      return nil, "unexpected tool argument: " .. tostring(key)
    end
  end

  local question, question_error = normalize_text(args.question, "question", M.MAX_QUESTION_LENGTH)
  if not question then
    return nil, question_error
  end

  local options, options_error = validate_options(args.options)
  if not options then
    return nil, options_error
  end

  return { question = question, options = options }, nil
end

local function total_queue_length()
  return (state.active and 1 or 0) + #state.queue
end

--- Return non-sensitive state for tests and UI integration.
---@return table
function M.state()
  local active = state.active
  return {
    active = active and active.id or nil,
    question = active and active.question or nil,
    selected = active and active.selected or nil,
    win = active and active.win or nil,
    buf = active and active.buf or nil,
    queue_length = total_queue_length(),
    pending_length = #state.queue,
  }
end

M.get_state = M.state

local function option_row(request, index)
  return request.option_start + index - 1
end

local function add_line(lines, value)
  if #lines >= M.MAX_HEIGHT then
    return false
  end
  lines[#lines + 1] = value
  return true
end

local function wrap_question(question, width)
  local lines = {}
  local current = ""
  local function flush()
    if current ~= "" and #lines < M.MAX_QUESTION_LINES then
      lines[#lines + 1] = current
    end
    current = ""
  end

  for word in question:gmatch("%S+") do
    if current == "" then
      current = word
    elseif #current + 1 + #word <= width then
      current = current .. " " .. word
    else
      flush()
      if #lines >= M.MAX_QUESTION_LINES then
        break
      end
      current = word
    end
  end
  flush()

  if #lines == 0 then
    lines[1] = question:sub(1, width)
  elseif #lines == M.MAX_QUESTION_LINES and (#lines == 0 or lines[#lines] ~= question) then
    local full_length = #question
    local rendered_length = 0
    for _, line in ipairs(lines) do
      rendered_length = rendered_length + #line
    end
    if rendered_length < full_length then
      lines[#lines] = lines[#lines]:sub(1, math.max(1, width - 3)) .. "..."
    end
  end

  return lines
end

local function render_lines(request, width)
  local lines = { "Question:" }
  local question_width = math.max(8, width - 4)
  for _, line in ipairs(wrap_question(request.question, question_width)) do
    add_line(lines, "  " .. line)
  end
  add_line(lines, "")
  add_line(lines, "Options:")
  request.option_start = #lines + 1

  for index, option in ipairs(request.options) do
    local marker = index == request.selected and ">" or " "
    if not add_line(lines, string.format("%s %d. %s", marker, index, option)) then
      break
    end
  end
  add_line(lines, "")
  add_line(lines, "Use Up/Down and Enter to select; Esc cancels.")
  return lines
end

local function window_dimensions(lines)
  local columns = math.max(1, tonumber(vim.o.columns) or 80)
  local screen_lines = math.max(1, tonumber(vim.o.lines) or 24)
  local desired_width = 24
  for _, line in ipairs(lines) do
    desired_width = math.max(desired_width, #line + 2)
  end

  local width = math.min(M.MAX_WIDTH, desired_width, math.max(1, columns - 2))
  local height = math.min(M.MAX_HEIGHT, #lines, math.max(1, screen_lines - 2))
  local row = math.max(0, math.floor((screen_lines - height) / 2))
  local col = math.max(0, math.floor((columns - width) / 2))
  return width, height, row, col
end

local function close_ui_handle(request)
  local ui = request.ui_handle
  if type(ui) ~= "table" then
    return
  end
  if type(ui.cancel) == "function" then
    pcall(ui.cancel, ui)
  elseif type(ui.close) == "function" then
    pcall(ui.close, ui)
  end
end

local function delete_keymaps(request)
  if not request.buf or not vim.api.nvim_buf_is_valid(request.buf) then
    return
  end
  for _, mapping in ipairs(request.mappings or {}) do
    pcall(vim.keymap.del, "n", mapping, { buffer = request.buf })
  end
  request.mappings = {}
end

local function delete_autocmds(request)
  if request.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, request.augroup)
    request.augroup = nil
  end
end

local function cleanup_popup(request, close_window)
  delete_autocmds(request)
  delete_keymaps(request)

  if close_window and request.win and vim.api.nvim_win_is_valid(request.win) then
    pcall(vim.api.nvim_win_close, request.win, true)
  end

  if request.buf and vim.api.nvim_buf_is_valid(request.buf) then
    pcall(vim.api.nvim_buf_delete, request.buf, { force = true })
  end

  request.win = nil
  request.buf = nil
  request.ui_handle = nil
end

local pump

local function finish(request, value, close_window, suppress_pump)
  if request.completed then
    return
  end
  request.completed = true
  if state.active == request then
    state.active = nil
  end

  if request.ui_handle then
    close_ui_handle(request)
  end
  cleanup_popup(request, close_window)
  callback_once(request.callback, value)

  if not suppress_pump and not state.resetting then
    pump()
  end
end

local function cancelled_result(reason)
  local message = reason or "ask-user request cancelled"
  return result("cancelled", nil, message, false, { reason = message })
end

local function selected_result(request, index)
  local option = request.options[index]
  local data = { index = index, option = option }
  local value = result("selected", data, nil, false, { reason = "selected" })
  value.index = index
  value.option = option
  return value
end

local function select_request(request, index)
  if request.completed then
    return
  end
  if type(index) ~= "number" or index ~= math.floor(index) or index < 1 or index > #request.options then
    finish(request, result("error", nil, "selected option is invalid", false, { reason = "invalid_selection" }), true)
    return
  end
  finish(request, selected_result(request, index), true)
end

local function cancel_request(request, reason)
  if request.completed then
    return
  end

  if state.active ~= request then
    for index, queued in ipairs(state.queue) do
      if queued == request then
        table.remove(state.queue, index)
        break
      end
    end
  end

  finish(request, cancelled_result(reason), state.active == request)
end

local function move_request(request, delta)
  if request.completed or state.active ~= request then
    return
  end
  local next_index = math.max(1, math.min(#request.options, request.selected + delta))
  request.selected = next_index
  if request.buf and vim.api.nvim_buf_is_valid(request.buf) then
    local line = option_row(request, next_index)
    vim.bo[request.buf].modifiable = true
    pcall(vim.api.nvim_buf_set_lines, request.buf, 0, -1, false, render_lines(request, request.width))
    vim.bo[request.buf].modifiable = false
    if request.win and vim.api.nvim_win_is_valid(request.win) then
      pcall(vim.api.nvim_win_set_cursor, request.win, { line, 0 })
    end
  end
end

local function attach_popup_autocmds(request)
  request.augroup = vim.api.nvim_create_augroup("CodetyperAskUser" .. tostring(request.id), { clear = true })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = request.augroup,
    pattern = tostring(request.win),
    callback = function()
      if not request.completed then
        cancel_request(request, "ask-user window closed")
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = request.augroup,
    buffer = request.buf,
    callback = function()
      if not request.completed then
        cancel_request(request, "ask-user buffer closed")
      end
    end,
  })
end

local function map_popup(request, lhs, callback)
  vim.keymap.set("n", lhs, callback, {
    buffer = request.buf,
    silent = true,
    noremap = true,
    nowait = true,
  })
  request.mappings[#request.mappings + 1] = lhs
end

local function open_float(request)
  local buffer = vim.api.nvim_create_buf(false, true)
  request.buf = buffer
  vim.bo[buffer].buftype = "nofile"
  vim.bo[buffer].bufhidden = "wipe"
  vim.bo[buffer].swapfile = false
  vim.bo[buffer].modifiable = true

  local initial_lines = render_lines(request, M.MAX_WIDTH - 4)
  local width, height, row, col = window_dimensions(initial_lines)
  request.width = width
  local lines = render_lines(request, width - 4)
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
  vim.bo[buffer].modifiable = false

  local win = vim.api.nvim_open_win(buffer, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " Ask User ",
    title_pos = "center",
    focusable = true,
  })
  request.win = win
  request.option_start = request.option_start or 5

  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"

  vim.api.nvim_buf_add_highlight(buffer, -1, "Title", 0, 0, -1)
  vim.api.nvim_buf_add_highlight(buffer, -1, "Special", request.option_start - 1, 0, -1)

  map_popup(request, "<Down>", function()
    move_request(request, 1)
  end)
  map_popup(request, "j", function()
    move_request(request, 1)
  end)
  map_popup(request, "<Up>", function()
    move_request(request, -1)
  end)
  map_popup(request, "k", function()
    move_request(request, -1)
  end)
  map_popup(request, "<CR>", function()
    select_request(request, request.selected)
  end)
  map_popup(request, "<Esc>", function()
    cancel_request(request, "ask-user request cancelled")
  end)

  attach_popup_autocmds(request)
  vim.api.nvim_win_set_cursor(win, { option_row(request, request.selected), 0 })
  return {
    close = function()
      if request.win and vim.api.nvim_win_is_valid(request.win) then
        vim.api.nvim_win_close(request.win, true)
      end
    end,
  }
end

local function open_injected(request)
  local ui = request.opts.ui
  local open = type(ui) == "function" and ui or type(ui) == "table" and ui.open
  if ui ~= nil and type(open) ~= "function" then
    return nil, "injected ask-user UI is invalid", true
  end
  if type(open) ~= "function" then
    return nil, nil, false
  end

  local callbacks = {
    id = request.id,
    question = request.question,
    options = vim.deepcopy(request.options),
    selected = request.selected,
    on_select = function(index)
      select_request(request, index)
    end,
    on_cancel = function(reason)
      cancel_request(request, reason or "ask-user request cancelled")
    end,
  }

  local ok, handle = pcall(open, callbacks, request.opts)
  if not ok then
    return nil, "injected ask-user UI failed", true
  end
  return handle, nil, true
end

local function open_request(request)
  local injected_handle, injected_error, injected = open_injected(request)
  if injected_error then
    finish(request, result("error", nil, injected_error, true, { reason = "ui_error" }), false)
    return
  end
  if injected then
    request.ui_handle = injected_handle
    return
  end

  local ok, handle = pcall(open_float, request)
  if not ok then
    cleanup_popup(request, true)
    finish(request, result("error", nil, "unable to open ask-user popup", true, { reason = "ui_error" }), false)
    return
  end
  request.ui_handle = handle
end

pump = function()
  if state.active or state.resetting then
    return
  end
  local request = table.remove(state.queue, 1)
  if not request then
    return
  end
  state.active = request
  open_request(request)
end

--- Queue one validated ask-user request and return a cancellable handle.
---@param args table {question:string, options:string[]}
---@param callback fun(result:table)|nil
---@param opts table|nil
---@return table handle
function M.request(args, callback, opts)
  opts = type(opts) == "table" and opts or {}
  local normalized, validation_error = M.validate(args)
  if not normalized then
    local completed = true
    callback_once(callback, result("error", nil, validation_error, false, { reason = "validation" }))
    return {
      cancel = function()
        if completed then
          return
        end
        completed = true
      end,
    }
  end

  state.next_id = state.next_id + 1
  local request = {
    id = state.next_id,
    question = normalized.question,
    options = normalized.options,
    callback = callback,
    opts = opts,
    selected = 1,
    mappings = {},
    completed = false,
  }

  local handle = {}
  function handle.cancel()
    cancel_request(request, "ask-user request cancelled")
  end
  request.handle = handle
  state.queue[#state.queue + 1] = request
  pump()
  return handle
end

M.ask = M.request
M.call = M.request
M.dispatch = M.request
M.open = M.request
M.show = M.request

--- Select an option on the active request. This is also a headless test seam.
---@param index number
function M.select(index)
  if state.active then
    select_request(state.active, index)
  end
end

--- Move the active selection by a bounded number of options.
---@param delta number
function M.move(delta)
  if state.active and type(delta) == "number" then
    move_request(state.active, delta)
  end
end

--- Cancel the active request while leaving queued requests intact.
function M.cancel()
  if state.active then
    cancel_request(state.active, "ask-user request cancelled")
  end
end

--- Close the active popup as a cancellation.
function M.close()
  if state.active then
    cancel_request(state.active, "ask-user window closed")
  end
end

--- Cancel all active and queued requests and release every UI resource.
function M.reset()
  state.resetting = true
  local active = state.active
  local queued = state.queue
  state.queue = {}

  if active then
    finish(active, cancelled_result("ask-user state reset"), true, true)
  end
  for _, request in ipairs(queued) do
    finish(request, cancelled_result("ask-user state reset"), false, true)
  end
  state.active = nil
  state.resetting = false
end

function M.is_open()
  return state.active ~= nil and state.active.win ~= nil and vim.api.nvim_win_is_valid(state.active.win)
end

function M.availability()
  local available = type(vim) == "table" and type(vim.api) == "table" and type(vim.api.nvim_open_win) == "function"
  return {
    available = available,
    stale = not available,
    error = not available and "Neovim floating windows are unavailable" or nil,
  }
end

return M
