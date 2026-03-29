local transform = require("codetyper.core.transform")

--- Setup default keymaps for transform commands
local function setup_keymaps()
  vim.keymap.set("v", "<leader>ctt", function()
    transform.cmd_transform_selection()
  end, {
    silent = true,
    desc = "Coder: Transform selection with prompt",
  })
  vim.keymap.set("n", "<leader>ctt", function()
    transform.cmd_transform_selection()
  end, {
    silent = true,
    desc = "Coder: Open prompt window",
  })

  vim.keymap.set("n", "<leader>ter", function()
    local terminal = require("codetyper.window.terminal")
    terminal.toggle()
  end, {
    silent = true,
    desc = "Coder: Toggle terminal",
  })
end

return setup_keymaps
