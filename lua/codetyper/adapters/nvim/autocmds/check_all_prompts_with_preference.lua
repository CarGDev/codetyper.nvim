local processed_prompts = require("codetyper.constants.constants").processed_prompts
local get_prompt_key = require("codetyper.adapters.nvim.autocmds.get_prompt_key")
local check_all_prompts = require("codetyper.adapters.nvim.autocmds.check_all_prompts")

--- Check all prompts with preference check
--- Only processes if there are unprocessed prompts and auto_process is enabled
local function check_all_prompts_with_preference()
  local preferences = require("codetyper.config.preferences")
  local find_prompts_in_buffer = require("codetyper.parser.find_prompts_in_buffer")

  local bufnr = vim.api.nvim_get_current_buf()
  local prompts = find_prompts_in_buffer(bufnr)
  if #prompts == 0 then
    return
  end

  local has_unprocessed = false
  for _, prompt in ipairs(prompts) do
    local prompt_key = get_prompt_key(bufnr, prompt)
    if not processed_prompts[prompt_key] then
      has_unprocessed = true
      break
    end
  end

  if not has_unprocessed then
    return
  end

  if auto_process then
    check_all_prompts()
  end
end

return check_all_prompts_with_preference
