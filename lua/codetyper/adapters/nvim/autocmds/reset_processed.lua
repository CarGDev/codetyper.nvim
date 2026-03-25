local utils = require("codetyper.support.utils")
local processed_prompts = require("codetyper.constants.constants").processed_prompts

--- Reset processed prompts for a buffer (useful for re-processing)
---@param bufnr? number Buffer number (default: current)
---@param silent? boolean Suppress notification (default: false)
local function reset_processed(bufnr, silent)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  for key, _ in pairs(processed_prompts) do
    if key:match("^" .. bufnr .. ":") then
      processed_prompts[key] = nil
    end
  end
  if not silent then
    utils.notify("Prompt history cleared - prompts can be re-processed")
  end
end

return reset_processed
