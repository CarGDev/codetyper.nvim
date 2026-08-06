-- Minimal init for headless plenary.busted test runs.
-- Usage: nvim --headless --noplugin -u tests/minimal_init.lua \
--          -c "PlenaryBustedDirectory tests/spec/ {minimal_init = 'tests/minimal_init.lua'}"

local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")

-- Locate plenary.nvim (common lazy.nvim / packer install locations)
local plenary_candidates = {
  vim.fn.expand("~/.local/share/nvim/lazy/plenary.nvim"),
  vim.fn.expand("~/.local/share/nvim/site/pack/packer/start/plenary.nvim"),
  vim.fn.expand("~/.local/share/nvim/site/pack/packer/opt/plenary.nvim"),
}

local plenary_found = false
for _, path in ipairs(plenary_candidates) do
  if vim.fn.isdirectory(path) == 1 then
    vim.opt.rtp:prepend(path)
    plenary_found = true
    break
  end
end

if not plenary_found then
  error("plenary.nvim not found. Install it or adjust tests/minimal_init.lua plenary_candidates.")
end

vim.opt.rtp:prepend(plugin_root)

vim.o.swapfile = false
vim.o.backup = false

require("plenary.busted")
