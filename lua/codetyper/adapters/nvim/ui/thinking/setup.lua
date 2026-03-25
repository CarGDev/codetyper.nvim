local close = require("codetyper.adapters.nvim.ui.thinking.close")

--- Register autocmds for cleanup on exit
local function setup()
  local group = vim.api.nvim_create_augroup("CodetyperThinking", { clear = true })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      close()
    end,
    desc = "Close thinking window before exiting Neovim",
  })
end

return setup
