local state = require("codetyper.state.state")
local queue = require("codetyper.core.events.queue")
local constants = require("codetyper.adapters.nvim.ui.logs_panel.constants")

--- Update the queue display buffer with pending and processing events
local function update_queue_display()
  if not state.queue_buf or not vim.api.nvim_buf_is_valid(state.queue_buf) then
    return
  end

  vim.schedule(function()
    if not state.queue_buf or not vim.api.nvim_buf_is_valid(state.queue_buf) then
      return
    end

    vim.bo[state.queue_buf].modifiable = true

    local lines = {
      "Queue",
      string.rep("─", constants.LOGS_WIDTH - 2),
    }

    local pending_events = queue.get_pending()
    local processing_events = queue.get_processing()

    for _, event in ipairs(processing_events) do
      local filename = vim.fn.fnamemodify(event.target_path or "", ":t")
      local line_num = event.range and event.range.start_line or 0
      local prompt_preview = (event.prompt_content or ""):sub(1, 25):gsub("\n", " ")
      if #(event.prompt_content or "") > 25 then
        prompt_preview = prompt_preview .. "..."
      end
      table.insert(lines, string.format("▶ %s:%d %s", filename, line_num, prompt_preview))
    end

    for _, event in ipairs(pending_events) do
      local filename = vim.fn.fnamemodify(event.target_path or "", ":t")
      local line_num = event.range and event.range.start_line or 0
      local prompt_preview = (event.prompt_content or ""):sub(1, 25):gsub("\n", " ")
      if #(event.prompt_content or "") > 25 then
        prompt_preview = prompt_preview .. "..."
      end
      table.insert(lines, string.format("○ %s:%d %s", filename, line_num, prompt_preview))
    end

    if #pending_events == 0 and #processing_events == 0 then
      table.insert(lines, "  (empty)")
    end

    vim.api.nvim_buf_set_lines(state.queue_buf, 0, -1, false, lines)

    vim.api.nvim_buf_clear_namespace(state.queue_buf, constants.ns_queue, 0, -1)
    vim.api.nvim_buf_add_highlight(state.queue_buf, constants.ns_queue, "Title", 0, 0, -1)
    vim.api.nvim_buf_add_highlight(state.queue_buf, constants.ns_queue, "Comment", 1, 0, -1)

    local highlight_line = 2
    for _ = 1, #processing_events do
      vim.api.nvim_buf_add_highlight(state.queue_buf, constants.ns_queue, "DiagnosticWarn", highlight_line, 0, 1)
      vim.api.nvim_buf_add_highlight(state.queue_buf, constants.ns_queue, "String", highlight_line, 2, -1)
      highlight_line = highlight_line + 1
    end
    for _ = 1, #pending_events do
      vim.api.nvim_buf_add_highlight(state.queue_buf, constants.ns_queue, "Comment", highlight_line, 0, 1)
      vim.api.nvim_buf_add_highlight(state.queue_buf, constants.ns_queue, "Normal", highlight_line, 2, -1)
      highlight_line = highlight_line + 1
    end

    vim.bo[state.queue_buf].modifiable = false
  end)
end

return update_queue_display
