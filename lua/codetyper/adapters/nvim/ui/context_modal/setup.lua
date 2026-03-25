local close = require("codetyper.adapters.nvim.ui.context_modal.close")

--- Setup autocmds for the context modal
local function setup()
  local group = vim.api.nvim_create_augroup("CodetypeContextModal", { clear = true })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      close()
    end,
    desc = "Close context modal before exiting Neovim",
  })
end

return setup
