local constants = require("codetyper.constants.constants")
local get_prompt_key = require("codetyper.adapters.nvim.autocmds.get_prompt_key")
local check_all_prompts = require("codetyper.adapters.nvim.autocmds.check_all_prompts")

--- Check all prompts and process any unprocessed ones (only if autotrigger enabled)
local function check_all_prompts_with_preference()
  if not constants.autotrigger then
    return
  end

  local find_prompts_in_buffer = require("codetyper.parser.find_prompts_in_buffer")

  local bufnr = vim.api.nvim_get_current_buf()
  local prompts = find_prompts_in_buffer(bufnr)
  if #prompts == 0 then
    return
  end

  local has_unprocessed = false
  for _, prompt in ipairs(prompts) do
    local prompt_key = get_prompt_key(bufnr, prompt)
    if not constants.processed_prompts[prompt_key] then
      has_unprocessed = true
      break
    end
  end

  if not has_unprocessed then
    return
  end

  check_all_prompts()
end

return check_all_prompts_with_preference
