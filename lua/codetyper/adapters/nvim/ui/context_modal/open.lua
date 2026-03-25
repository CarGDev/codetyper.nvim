local state = require("codetyper.state.state")
local submit = require("codetyper.adapters.nvim.ui.context_modal.submit")
local attach_requested_files = require("codetyper.adapters.nvim.ui.context_modal.attach_requested_files")
local run_project_inspect = require("codetyper.adapters.nvim.ui.context_modal.run_project_inspect")
local run_suggested_command = require("codetyper.adapters.nvim.ui.context_modal.run_suggested_command")
local run_all_suggested_commands = require("codetyper.adapters.nvim.ui.context_modal.run_all_suggested_commands")

--- Open the context modal
---@param original_event table Original prompt event
---@param llm_response string LLM's response asking for context
---@param callback function(event: table, additional_context: string, attached_files?: table)
---@param suggested_commands table[]|nil Optional list of {label,cmd} suggested shell commands
function M.open(original_event, llm_response, callback, suggested_commands)
  close()

  state.original_event = original_event
  state.llm_response = llm_response
  state.callback = callback

  local width = math.min(80, vim.o.columns - 10)
  local height = 10

  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].buftype = "nofile"
  vim.bo[state.buf].bufhidden = "wipe"
  vim.bo[state.buf].filetype = "markdown"

  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  state.win = vim.api.nvim_open_win(state.buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " Additional Context Needed ",
    title_pos = "center",
  })

  vim.wo[state.win].wrap = true
  vim.wo[state.win].cursorline = true

  local ui_prompts = require("codetyper.prompts.agents.modal").ui

  local header_lines = {
    ui_prompts.llm_response_header,
  }

  local response_preview = llm_response or ""
  if #response_preview > 200 then
    response_preview = response_preview:sub(1, 200) .. "..."
  end
  for line in response_preview:gmatch("[^\n]+") do
    table.insert(header_lines, "-- " .. line)
  end

  if suggested_commands and #suggested_commands > 0 then
    table.insert(header_lines, "")
    table.insert(header_lines, ui_prompts.suggested_commands_header)
    for command_index, command in ipairs(suggested_commands) do
      local label = command.label or command.cmd
      table.insert(header_lines, string.format("[%d] %s: %s", command_index, label, command.cmd))
    end
    table.insert(header_lines, ui_prompts.commands_hint)
  end

  table.insert(header_lines, "")
  table.insert(header_lines, ui_prompts.input_header)
  table.insert(header_lines, "")

  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, header_lines)
  vim.api.nvim_win_set_cursor(state.win, { #header_lines, 0 })

  local keymap_opts = { buffer = state.buf, noremap = true, silent = true }

  vim.keymap.set("n", "<C-CR>", submit, keymap_opts)
  vim.keymap.set("i", "<C-CR>", submit, keymap_opts)
  vim.keymap.set("n", "<leader>s", submit, keymap_opts)
  vim.keymap.set("n", "<CR><CR>", submit, keymap_opts)
  vim.keymap.set("n", "c", submit, keymap_opts)

  vim.keymap.set("n", "a", attach_requested_files, keymap_opts)

  vim.keymap.set("n", "<leader>r", run_project_inspect, keymap_opts)
  vim.keymap.set("i", "<C-r>", function()
    vim.schedule(run_project_inspect)
  end, keymap_opts)

  state.suggested_commands = suggested_commands
  if suggested_commands and #suggested_commands > 0 then
    for command_index, command in ipairs(suggested_commands) do
      local key = "<leader>" .. tostring(command_index)
      vim.keymap.set("n", key, function()
        run_suggested_command(command)
      end, keymap_opts)
    end

    vim.keymap.set("n", "<leader>0", function()
      run_all_suggested_commands(suggested_commands)
    end, keymap_opts)
  end

  vim.keymap.set("n", "<Esc>", close, keymap_opts)
  vim.keymap.set("n", "q", close, keymap_opts)

  vim.cmd("startinsert")

  pcall(function()
    local logs_add = require("codetyper.adapters.nvim.ui.logs.add")
    logs_add({
      type = "info",
      message = "Context modal opened - waiting for user input",
    })
  end)
end
