local check_for_closed_prompt = require("codetyper.adapters.nvim.autocmds.check_for_closed_prompt")
local preferences = require("codetyper.config.preferences")

--- Check for closed prompt with preference check
--- If auto_process is enabled, process; otherwise do nothing (manual mode)
local function check_for_closed_prompt_with_preference()
  local find_prompts_in_buffer = require("codetyper.parser.find_prompts_in_buffer")

  local bufnr = vim.api.nvim_get_current_buf()
  local prompts = find_prompts_in_buffer(bufnr)
  if #prompts == 0 then
    return
  end

  if preferences.is_auto_process_enabled() then
    check_for_closed_prompt()
  end
end

return check_for_closed_prompt_with_preference
