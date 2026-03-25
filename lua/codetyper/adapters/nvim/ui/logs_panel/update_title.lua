local state = require("codetyper.state.state")
local logs = require("codetyper.adapters.nvim.ui.logs")

--- Update the panel title with token counts and provider info
local function update_title()
  if not state.win or not vim.api.nvim_win_is_valid(state.win) then
    return
  end

  local prompt_tokens, response_tokens = logs.get_token_totals()
  local provider, _ = logs.get_provider_info()

  if provider and state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    vim.bo[state.buf].modifiable = true
    local title = string.format("%s | %d/%d tokens", (provider or ""):upper(), prompt_tokens, response_tokens)
    vim.api.nvim_buf_set_lines(state.buf, 0, 1, false, { title })
    vim.bo[state.buf].modifiable = false
  end
end

return update_title
