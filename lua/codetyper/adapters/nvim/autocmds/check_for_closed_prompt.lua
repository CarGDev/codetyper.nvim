local constants = require("codetyper.constants.constants")
local get_prompt_key = require("codetyper.adapters.nvim.autocmds.get_prompt_key")
local get_config = require("codetyper.utils.get_config").get_config
local flog = require("codetyper.support.flog") -- TODO: remove after debugging

--- Check if the buffer has a newly closed prompt and auto-process
local function check_for_closed_prompt()
  if constants.is_processing then
    return
  end
  constants.is_processing = true

  local has_closing_tag = require("codetyper.parser.has_closing_tag")
  local get_last_prompt = require("codetyper.parser.get_last_prompt")
  local process_single_prompt = require("codetyper.adapters.nvim.autocmds.process_single_prompt")

  local bufnr = vim.api.nvim_get_current_buf()
  local current_file = vim.fn.expand("%:p")

  if current_file == "" then
    constants.is_processing = false
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]
  local lines = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)

  if #lines == 0 then
    constants.is_processing = false
    return
  end

  local current_line = lines[1]
  local cfg = get_config()

  if has_closing_tag(current_line, cfg.patterns.close_tag) then
    flog.info("inline_prompt", string.format( -- TODO: remove after debugging
      "closing tag detected at line %d: %s", line, current_line:sub(1, 80)
    ))
    local prompt = get_last_prompt(bufnr)
    if prompt and prompt.content and prompt.content ~= "" then
      local prompt_key = get_prompt_key(bufnr, prompt)

      if constants.processed_prompts[prompt_key] then
        flog.info("inline_prompt", "already processed, skipping") -- TODO: remove after debugging
        constants.is_processing = false
        return
      end

      flog.info("inline_prompt", string.format( -- TODO: remove after debugging
        "processing: lines=%d-%d content=%s",
        prompt.start_line or 0, prompt.end_line or 0,
        (prompt.content or ""):sub(1, 100):gsub("\n", "\\n")
      ))

      process_single_prompt(bufnr, prompt, current_file, false)
    else
      flog.warn("inline_prompt", "no prompt found or empty content") -- TODO: remove after debugging
    end
  end

  constants.is_processing = false
end

return check_for_closed_prompt
