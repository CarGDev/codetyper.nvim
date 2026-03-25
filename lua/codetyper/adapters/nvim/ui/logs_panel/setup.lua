local close = require("codetyper.adapters.nvim.ui.logs_panel.close")

--- Setup autocmds for the logs panel
local function setup()
  local group = vim.api.nvim_create_augroup("CodetypeLogsPanel", { clear = true })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      close(true)
    end,
    desc = "Close logs panel before exiting Neovim",
  })

  vim.api.nvim_create_autocmd("QuitPre", {
    group = group,
    callback = function()
      local wins = vim.api.nvim_list_wins()
      local real_wins = 0
      for _, win in ipairs(wins) do
        local buf = vim.api.nvim_win_get_buf(win)
        local buftype = vim.bo[buf].buftype
        if buftype == "" or buftype == "help" then
          real_wins = real_wins + 1
        end
      end
      if real_wins <= 1 then
        close(true)
      end
    end,
    desc = "Close logs panel on quit",
  })
end

return setup
