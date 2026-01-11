-- Codetyper.nvim - AI-powered coding partner for Neovim
-- Plugin loader

-- Prevent loading twice
if vim.g.loaded_codetyper then
  return
end
vim.g.loaded_codetyper = true

-- Minimum Neovim version check
if vim.fn.has("nvim-0.8.0") == 0 then
  vim.api.nvim_err_writeln("Codetyper.nvim requires Neovim 0.8.0 or higher")
  return
end

-- Initialize .coder folder and tree.log on project open
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    -- Delay slightly to ensure cwd is set
    vim.defer_fn(function()
      local tree = require("codetyper.tree")
      tree.setup()
      
      -- Also ensure gitignore is updated
      local gitignore = require("codetyper.gitignore")
      gitignore.ensure_ignored()
    end, 100)
  end,
  desc = "Initialize Codetyper .coder folder on startup",
})

-- Also initialize on directory change
vim.api.nvim_create_autocmd("DirChanged", {
  callback = function()
    vim.defer_fn(function()
      local tree = require("codetyper.tree")
      tree.setup()
      
      local gitignore = require("codetyper.gitignore")
      gitignore.ensure_ignored()
    end, 100)
  end,
  desc = "Initialize Codetyper .coder folder on directory change",
})

-- Auto-initialize when opening a coder file (for nvim-tree, telescope, etc.)
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile", "BufEnter" }, {
  pattern = "*.coder.*",
  callback = function()
    -- Initialize plugin if not already done
    local codetyper = require("codetyper")
    if not codetyper.is_initialized() then
      codetyper.setup()
    end
  end,
  desc = "Auto-initialize Codetyper when opening coder files",
})

-- Lazy-load the plugin on first command usage
vim.api.nvim_create_user_command("Coder", function(opts)
  require("codetyper").setup()
  -- Re-execute the command now that plugin is loaded
  vim.cmd("Coder " .. (opts.args or ""))
end, {
  nargs = "?",
  complete = function()
    return {
      "open", "close", "toggle", "process", "status", "focus",
      "tree", "tree-view", "reset", "gitignore",
      "ask", "ask-close", "ask-toggle", "ask-clear",
    }
  end,
  desc = "Codetyper.nvim commands",
})

-- Lazy-load aliases
vim.api.nvim_create_user_command("CoderOpen", function()
  require("codetyper").setup()
  vim.cmd("CoderOpen")
end, { desc = "Open Coder view" })

vim.api.nvim_create_user_command("CoderClose", function()
  require("codetyper").setup()
  vim.cmd("CoderClose")
end, { desc = "Close Coder view" })

vim.api.nvim_create_user_command("CoderToggle", function()
  require("codetyper").setup()
  vim.cmd("CoderToggle")
end, { desc = "Toggle Coder view" })

vim.api.nvim_create_user_command("CoderProcess", function()
  require("codetyper").setup()
  vim.cmd("CoderProcess")
end, { desc = "Process prompt and generate code" })

vim.api.nvim_create_user_command("CoderTree", function()
  require("codetyper").setup()
  vim.cmd("CoderTree")
end, { desc = "Refresh tree.log" })

vim.api.nvim_create_user_command("CoderTreeView", function()
  require("codetyper").setup()
  vim.cmd("CoderTreeView")
end, { desc = "View tree.log" })

-- Ask panel commands
vim.api.nvim_create_user_command("CoderAsk", function()
  require("codetyper").setup()
  vim.cmd("CoderAsk")
end, { desc = "Open Ask panel" })

vim.api.nvim_create_user_command("CoderAskToggle", function()
  require("codetyper").setup()
  vim.cmd("CoderAskToggle")
end, { desc = "Toggle Ask panel" })

vim.api.nvim_create_user_command("CoderAskClear", function()
  require("codetyper").setup()
  vim.cmd("CoderAskClear")
end, { desc = "Clear Ask history" })
