---@mod codetyper.agent.ui Agent chat UI for Codetyper.nvim
---
--- Provides a sidebar chat interface for agent interactions with real-time logs.

local M = {}

local agent = require("codetyper.agent")
local logs = require("codetyper.agent.logs")
local utils = require("codetyper.utils")

---@class AgentUIState
---@field chat_buf number|nil Chat buffer
---@field chat_win number|nil Chat window
---@field input_buf number|nil Input buffer
---@field input_win number|nil Input window
---@field logs_buf number|nil Logs buffer
---@field logs_win number|nil Logs window
---@field is_open boolean Whether the UI is open
---@field log_listener_id number|nil Listener ID for logs
---@field referenced_files table Files referenced with @

local state = {
  chat_buf = nil,
  chat_win = nil,
  input_buf = nil,
  input_win = nil,
  logs_buf = nil,
  logs_win = nil,
  is_open = false,
  log_listener_id = nil,
  referenced_files = {},
}

--- Namespace for highlights
local ns_chat = vim.api.nvim_create_namespace("codetyper_agent_chat")
local ns_logs = vim.api.nvim_create_namespace("codetyper_agent_logs")

--- Fixed widths
local CHAT_WIDTH = 300
local LOGS_WIDTH = 50
local INPUT_HEIGHT = 5

--- Autocmd group
local agent_augroup = nil

--- Add a log entry to the logs buffer
---@param entry table Log entry
local function add_log_entry(entry)
  if not state.logs_buf or not vim.api.nvim_buf_is_valid(state.logs_buf) then
    return
  end

  vim.schedule(function()
    if not state.logs_buf or not vim.api.nvim_buf_is_valid(state.logs_buf) then
      return
    end

    -- Handle clear event
    if entry.level == "clear" then
      vim.bo[state.logs_buf].modifiable = true
      vim.api.nvim_buf_set_lines(state.logs_buf, 0, -1, false, {
        "Logs",
        string.rep("─", LOGS_WIDTH - 2),
        "",
      })
      vim.bo[state.logs_buf].modifiable = false
      return
    end

    vim.bo[state.logs_buf].modifiable = true

    local formatted = logs.format_entry(entry)
    local lines = vim.api.nvim_buf_get_lines(state.logs_buf, 0, -1, false)
    local line_num = #lines

    vim.api.nvim_buf_set_lines(state.logs_buf, -1, -1, false, { formatted })

    -- Apply highlighting based on level
    local hl_map = {
      info = "DiagnosticInfo",
      debug = "Comment",
      request = "DiagnosticWarn",
      response = "DiagnosticOk",
      tool = "DiagnosticHint",
      error = "DiagnosticError",
    }

    local hl = hl_map[entry.level] or "Normal"
    vim.api.nvim_buf_add_highlight(state.logs_buf, ns_logs, hl, line_num, 0, -1)

    vim.bo[state.logs_buf].modifiable = false

    -- Auto-scroll logs
    if state.logs_win and vim.api.nvim_win_is_valid(state.logs_win) then
      local new_count = vim.api.nvim_buf_line_count(state.logs_buf)
      pcall(vim.api.nvim_win_set_cursor, state.logs_win, { new_count, 0 })
    end
  end)
end

--- Add a message to the chat buffer
---@param role string "user" | "assistant" | "tool" | "system"
---@param content string Message content
---@param highlight? string Optional highlight group
local function add_message(role, content, highlight)
  if not state.chat_buf or not vim.api.nvim_buf_is_valid(state.chat_buf) then
    return
  end

  vim.bo[state.chat_buf].modifiable = true

  local lines = vim.api.nvim_buf_get_lines(state.chat_buf, 0, -1, false)
  local start_line = #lines

  -- Add separator if not first message
  if start_line > 0 and lines[start_line] ~= "" then
    vim.api.nvim_buf_set_lines(state.chat_buf, -1, -1, false, { "" })
    start_line = start_line + 1
  end

  -- Format the message
  local prefix_map = {
    user = ">>> You:",
    assistant = "<<< Agent:",
    tool = "[Tool]",
    system = "[System]",
  }

  local prefix = prefix_map[role] or "[Unknown]"
  local message_lines = { prefix }

  -- Split content into lines
  for line in content:gmatch("[^\n]+") do
    table.insert(message_lines, "  " .. line)
  end

  vim.api.nvim_buf_set_lines(state.chat_buf, -1, -1, false, message_lines)

  -- Apply highlighting
  local hl_group = highlight or ({
    user = "DiagnosticInfo",
    assistant = "DiagnosticOk",
    tool = "DiagnosticWarn",
    system = "DiagnosticHint",
  })[role] or "Normal"

  vim.api.nvim_buf_add_highlight(state.chat_buf, ns_chat, hl_group, start_line, 0, -1)

  vim.bo[state.chat_buf].modifiable = false

  -- Scroll to bottom
  if state.chat_win and vim.api.nvim_win_is_valid(state.chat_win) then
    local line_count = vim.api.nvim_buf_line_count(state.chat_buf)
    pcall(vim.api.nvim_win_set_cursor, state.chat_win, { line_count, 0 })
  end
end

--- Create the agent callbacks
---@return table Callbacks for agent.run
local function create_callbacks()
  return {
    on_text = function(text)
      vim.schedule(function()
        add_message("assistant", text)
        logs.thinking("Received response text")
      end)
    end,

    on_tool_start = function(name)
      vim.schedule(function()
        add_message("tool", "Executing: " .. name .. "...", "DiagnosticWarn")
        logs.tool(name, "start")
      end)
    end,

    on_tool_result = function(name, result)
      vim.schedule(function()
        local display_result = result
        if #result > 200 then
          display_result = result:sub(1, 200) .. "..."
        end
        add_message("tool", name .. ": " .. display_result, "DiagnosticOk")
        logs.tool(name, "success", string.format("%d bytes", #result))
      end)
    end,

    on_complete = function()
      vim.schedule(function()
        add_message("system", "Done.", "DiagnosticHint")
        logs.info("Agent loop completed")
        M.focus_input()
      end)
    end,

    on_error = function(err)
      vim.schedule(function()
        add_message("system", "Error: " .. err, "DiagnosticError")
        logs.error(err)
        M.focus_input()
      end)
    end,
  }
end

--- Build file context from referenced files
---@return string Context string
local function build_file_context()
  local context = ""

  for filename, filepath in pairs(state.referenced_files) do
    local content = utils.read_file(filepath)
    if content and content ~= "" then
      local ext = vim.fn.fnamemodify(filepath, ":e")
      context = context .. "\n\n=== FILE: " .. filename .. " ===\n"
      context = context .. "Path: " .. filepath .. "\n"
      context = context .. "```" .. (ext or "text") .. "\n" .. content .. "\n```\n"
    end
  end

  return context
end

--- Submit user input
local function submit_input()
  if not state.input_buf or not vim.api.nvim_buf_is_valid(state.input_buf) then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(state.input_buf, 0, -1, false)
  local input = table.concat(lines, "\n")
  input = vim.trim(input)

  if input == "" then
    return
  end

  -- Clear input buffer
  vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, { "" })

  -- Handle special commands
  if input == "/stop" then
    agent.stop()
    add_message("system", "Stopped.")
    logs.info("Agent stopped by user")
    return
  end

  if input == "/clear" then
    agent.reset()
    logs.clear()
    state.referenced_files = {}
    if state.chat_buf and vim.api.nvim_buf_is_valid(state.chat_buf) then
      vim.bo[state.chat_buf].modifiable = true
      vim.api.nvim_buf_set_lines(state.chat_buf, 0, -1, false, {
        "╔═══════════════════════════════════════════════════════════════╗",
        "║  [AGENT MODE] Can read/write files                           ║",
        "╠═══════════════════════════════════════════════════════════════╣",
        "║  @ attach file | C-f current file | :CoderType switch mode   ║",
        "╚═══════════════════════════════════════════════════════════════╝",
        "",
      })
      vim.bo[state.chat_buf].modifiable = false
    end
    return
  end

  if input == "/close" then
    M.close()
    return
  end

  -- Build file context
  local file_context = build_file_context()
  local file_count = vim.tbl_count(state.referenced_files)

  -- Add user message to chat
  local display_input = input
  if file_count > 0 then
    local files_list = {}
    for fname, _ in pairs(state.referenced_files) do
      table.insert(files_list, fname)
    end
    display_input = input .. "\n[Attached: " .. table.concat(files_list, ", ") .. "]"
  end
  add_message("user", display_input)
  logs.info("User: " .. input:sub(1, 40) .. (input:len() > 40 and "..." or ""))

  -- Clear referenced files after use
  state.referenced_files = {}

  -- Check if agent is already running
  if agent.is_running() then
    add_message("system", "Busy. /stop first.")
    logs.info("Request rejected - busy")
    return
  end

  -- Build context from current buffer
  local current_file = vim.fn.expand("#:p")
  if current_file == "" then
    current_file = vim.fn.expand("%:p")
  end

  local llm = require("codetyper.llm")
  local context = {}

  if current_file ~= "" and vim.fn.filereadable(current_file) == 1 then
    context = llm.build_context(current_file, "agent")
    logs.debug("Context: " .. vim.fn.fnamemodify(current_file, ":t"))
  end

  -- Append file context to input
  local full_input = input
  if file_context ~= "" then
    full_input = input .. "\n\nATTACHED FILES:" .. file_context
  end

  logs.thinking("Starting...")

  -- Run the agent
  agent.run(full_input, context, create_callbacks())
end

--- Show file picker for @ mentions
function M.show_file_picker()
  local has_telescope, telescope = pcall(require, "telescope.builtin")

  if has_telescope then
    telescope.find_files({
      prompt_title = "Attach file (@)",
      attach_mappings = function(prompt_bufnr, map)
        local actions = require("telescope.actions")
        local action_state = require("telescope.actions.state")

        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection then
            local filepath = selection.path or selection[1]
            local filename = vim.fn.fnamemodify(filepath, ":t")
            M.add_file_reference(filepath, filename)
          end
        end)
        return true
      end,
    })
  else
    vim.ui.input({ prompt = "File path: " }, function(input)
      if input and input ~= "" then
        local filepath = vim.fn.fnamemodify(input, ":p")
        local filename = vim.fn.fnamemodify(filepath, ":t")
        M.add_file_reference(filepath, filename)
      end
    end)
  end
end

--- Add a file reference
---@param filepath string Full path to the file
---@param filename string Display name
function M.add_file_reference(filepath, filename)
  filepath = vim.fn.fnamemodify(filepath, ":p")
  state.referenced_files[filename] = filepath

  local content = utils.read_file(filepath)
  if not content then
    utils.notify("Cannot read: " .. filename, vim.log.levels.WARN)
    return
  end

  add_message("system", "Attached: " .. filename, "DiagnosticHint")
  logs.debug("Attached: " .. filename)
  M.focus_input()
end

--- Include current file context
function M.include_current_file()
  -- Get the file from the window that's not the agent sidebar
  local current_file = nil
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if win ~= state.chat_win and win ~= state.logs_win and win ~= state.input_win then
      local buf = vim.api.nvim_win_get_buf(win)
      local name = vim.api.nvim_buf_get_name(buf)
      if name ~= "" and vim.fn.filereadable(name) == 1 then
        current_file = name
        break
      end
    end
  end

  if not current_file then
    utils.notify("No file to attach", vim.log.levels.WARN)
    return
  end

  local filename = vim.fn.fnamemodify(current_file, ":t")
  M.add_file_reference(current_file, filename)
end

--- Focus the input buffer
function M.focus_input()
  if state.input_win and vim.api.nvim_win_is_valid(state.input_win) then
    vim.api.nvim_set_current_win(state.input_win)
    vim.cmd("startinsert")
  end
end

--- Focus the chat buffer
function M.focus_chat()
  if state.chat_win and vim.api.nvim_win_is_valid(state.chat_win) then
    vim.api.nvim_set_current_win(state.chat_win)
  end
end

--- Focus the logs buffer
function M.focus_logs()
  if state.logs_win and vim.api.nvim_win_is_valid(state.logs_win) then
    vim.api.nvim_set_current_win(state.logs_win)
  end
end

--- Show chat mode switcher modal
function M.show_chat_switcher()
  local switcher = require("codetyper.chat_switcher")
  switcher.show()
end

--- Update the logs title with token counts
local function update_logs_title()
  if not state.logs_win or not vim.api.nvim_win_is_valid(state.logs_win) then
    return
  end

  local prompt_tokens, response_tokens = logs.get_token_totals()
  local provider, _ = logs.get_provider_info()

  if provider and state.logs_buf and vim.api.nvim_buf_is_valid(state.logs_buf) then
    vim.bo[state.logs_buf].modifiable = true
    local lines = vim.api.nvim_buf_get_lines(state.logs_buf, 0, 2, false)
    if #lines >= 1 then
      lines[1] = string.format("%s | %d/%d tokens", provider:upper(), prompt_tokens, response_tokens)
      vim.api.nvim_buf_set_lines(state.logs_buf, 0, 1, false, { lines[1] })
    end
    vim.bo[state.logs_buf].modifiable = false
  end
end

--- Open the agent UI
function M.open()
  if state.is_open then
    M.focus_input()
    return
  end

  -- Clear previous state
  logs.clear()
  state.referenced_files = {}

  -- Create chat buffer
  state.chat_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.chat_buf].buftype = "nofile"
  vim.bo[state.chat_buf].bufhidden = "hide"
  vim.bo[state.chat_buf].swapfile = false
  vim.bo[state.chat_buf].filetype = "markdown"

  -- Create input buffer
  state.input_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.input_buf].buftype = "nofile"
  vim.bo[state.input_buf].bufhidden = "hide"
  vim.bo[state.input_buf].swapfile = false

  -- Create logs buffer
  state.logs_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.logs_buf].buftype = "nofile"
  vim.bo[state.logs_buf].bufhidden = "hide"
  vim.bo[state.logs_buf].swapfile = false

  -- Create chat window on the LEFT (like NvimTree)
  vim.cmd("topleft vsplit")
  state.chat_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.chat_win, state.chat_buf)
  vim.api.nvim_win_set_width(state.chat_win, CHAT_WIDTH)

  -- Window options for chat
  vim.wo[state.chat_win].number = false
  vim.wo[state.chat_win].relativenumber = false
  vim.wo[state.chat_win].signcolumn = "no"
  vim.wo[state.chat_win].wrap = true
  vim.wo[state.chat_win].linebreak = true
  vim.wo[state.chat_win].winfixwidth = true
  vim.wo[state.chat_win].cursorline = false

  -- Create input window below chat
  vim.cmd("belowright split")
  state.input_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.input_win, state.input_buf)
  vim.api.nvim_win_set_height(state.input_win, INPUT_HEIGHT)

  -- Window options for input
  vim.wo[state.input_win].number = false
  vim.wo[state.input_win].relativenumber = false
  vim.wo[state.input_win].signcolumn = "no"
  vim.wo[state.input_win].wrap = true
  vim.wo[state.input_win].linebreak = true
  vim.wo[state.input_win].winfixheight = true
  vim.wo[state.input_win].winfixwidth = true

  -- Create logs window on the RIGHT
  vim.cmd("botright vsplit")
  state.logs_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.logs_win, state.logs_buf)
  vim.api.nvim_win_set_width(state.logs_win, LOGS_WIDTH)

  -- Window options for logs
  vim.wo[state.logs_win].number = false
  vim.wo[state.logs_win].relativenumber = false
  vim.wo[state.logs_win].signcolumn = "no"
  vim.wo[state.logs_win].wrap = true
  vim.wo[state.logs_win].linebreak = true
  vim.wo[state.logs_win].winfixwidth = true
  vim.wo[state.logs_win].cursorline = false

  -- Set initial content for chat
  vim.bo[state.chat_buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.chat_buf, 0, -1, false, {
    "╔═══════════════════════════════════════════════════════════════╗",
    "║  [AGENT MODE] Can read/write files                           ║",
    "╠═══════════════════════════════════════════════════════════════╣",
    "║  @ attach file | C-f current file | :CoderType switch mode   ║",
    "╚═══════════════════════════════════════════════════════════════╝",
    "",
  })
  vim.bo[state.chat_buf].modifiable = false

  -- Set initial content for logs
  vim.bo[state.logs_buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.logs_buf, 0, -1, false, {
    "Logs",
    string.rep("─", LOGS_WIDTH - 2),
    "",
  })
  vim.bo[state.logs_buf].modifiable = false

  -- Register log listener
  state.log_listener_id = logs.add_listener(function(entry)
    add_log_entry(entry)
    if entry.level == "response" then
      vim.schedule(update_logs_title)
    end
  end)

  -- Set up keymaps for input buffer
  local input_opts = { buffer = state.input_buf, noremap = true, silent = true }

  vim.keymap.set("i", "<CR>", submit_input, input_opts)
  vim.keymap.set("n", "<CR>", submit_input, input_opts)
  vim.keymap.set("i", "@", M.show_file_picker, input_opts)
  vim.keymap.set({ "n", "i" }, "<C-f>", M.include_current_file, input_opts)
  vim.keymap.set("n", "<Tab>", M.focus_chat, input_opts)
  vim.keymap.set("n", "q", M.close, input_opts)
  vim.keymap.set("n", "<Esc>", M.close, input_opts)

  -- Set up keymaps for chat buffer
  local chat_opts = { buffer = state.chat_buf, noremap = true, silent = true }

  vim.keymap.set("n", "i", M.focus_input, chat_opts)
  vim.keymap.set("n", "<CR>", M.focus_input, chat_opts)
  vim.keymap.set("n", "@", M.show_file_picker, chat_opts)
  vim.keymap.set("n", "<C-f>", M.include_current_file, chat_opts)
  vim.keymap.set("n", "<Tab>", M.focus_logs, chat_opts)
  vim.keymap.set("n", "q", M.close, chat_opts)

  -- Set up keymaps for logs buffer
  local logs_opts = { buffer = state.logs_buf, noremap = true, silent = true }

  vim.keymap.set("n", "<Tab>", M.focus_input, logs_opts)
  vim.keymap.set("n", "q", M.close, logs_opts)
  vim.keymap.set("n", "i", M.focus_input, logs_opts)

  -- Setup autocmd for cleanup
  agent_augroup = vim.api.nvim_create_augroup("CodetypeAgentUI", { clear = true })

  vim.api.nvim_create_autocmd("WinClosed", {
    group = agent_augroup,
    callback = function(args)
      local closed_win = tonumber(args.match)
      if closed_win == state.chat_win or closed_win == state.logs_win or closed_win == state.input_win then
        vim.schedule(function()
          M.close()
        end)
      end
    end,
  })

  state.is_open = true

  -- Focus input and log startup
  M.focus_input()
  logs.info("Agent ready")

  -- Log provider info
  local ok, codetyper = pcall(require, "codetyper")
  if ok then
    local config = codetyper.get_config()
    local provider = config.llm.provider
    local model = provider == "claude" and config.llm.claude.model or config.llm.ollama.model
    logs.info(string.format("%s (%s)", provider, model))
  end
end

--- Close the agent UI
function M.close()
  if not state.is_open then
    return
  end

  -- Stop agent if running
  if agent.is_running() then
    agent.stop()
  end

  -- Remove log listener
  if state.log_listener_id then
    logs.remove_listener(state.log_listener_id)
    state.log_listener_id = nil
  end

  -- Remove autocmd
  if agent_augroup then
    pcall(vim.api.nvim_del_augroup_by_id, agent_augroup)
    agent_augroup = nil
  end

  -- Close windows
  if state.input_win and vim.api.nvim_win_is_valid(state.input_win) then
    pcall(vim.api.nvim_win_close, state.input_win, true)
  end
  if state.chat_win and vim.api.nvim_win_is_valid(state.chat_win) then
    pcall(vim.api.nvim_win_close, state.chat_win, true)
  end
  if state.logs_win and vim.api.nvim_win_is_valid(state.logs_win) then
    pcall(vim.api.nvim_win_close, state.logs_win, true)
  end

  -- Reset state
  state.chat_buf = nil
  state.chat_win = nil
  state.input_buf = nil
  state.input_win = nil
  state.logs_buf = nil
  state.logs_win = nil
  state.is_open = false
  state.referenced_files = {}

  -- Reset agent conversation
  agent.reset()
end

--- Toggle the agent UI
function M.toggle()
  if state.is_open then
    M.close()
  else
    M.open()
  end
end

--- Check if UI is open
---@return boolean
function M.is_open()
  return state.is_open
end

return M
