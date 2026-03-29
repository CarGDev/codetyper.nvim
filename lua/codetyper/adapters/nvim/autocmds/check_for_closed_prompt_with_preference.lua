local check_for_closed_prompt = require("codetyper.adapters.nvim.autocmds.check_for_closed_prompt")
local constants = require("codetyper.constants.constants")

--- Check for closed prompt and process it (only if autotrigger is enabled)
local function check_for_closed_prompt_with_preference()
  if not constants.autotrigger then
    return
  end

  local find_prompts_in_buffer = require("codetyper.parser.find_prompts_in_buffer")

  local bufnr = vim.api.nvim_get_current_buf()
  local prompts = find_prompts_in_buffer(bufnr)
  if #prompts == 0 then
    return
  end

  check_for_closed_prompt()
end

return check_for_closed_prompt_with_preference
