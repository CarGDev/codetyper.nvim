local process_single_prompt = require("codetyper.adapters.nvim.autocmds.process_single_prompt")

--- Check and process all closed prompts in the buffer
local function check_all_prompts()
  local find_prompts_in_buffer = require("codetyper.parser.find_prompts_in_buffer")
  local bufnr = vim.api.nvim_get_current_buf()
  local current_file = vim.fn.expand("%:p")

  if current_file == "" then
    return
  end

  local prompts = find_prompts_in_buffer(bufnr)

  if #prompts == 0 then
    return
  end

  local codetyper = require("codetyper")
  local ct_config = codetyper.get_config()
  local scheduler_enabled = ct_config and ct_config.scheduler and ct_config.scheduler.enabled

  if not scheduler_enabled then
    return
  end

  for _, prompt in ipairs(prompts) do
    process_single_prompt(bufnr, prompt, current_file)
  end
end

return check_all_prompts
