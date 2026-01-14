-- Minimal init.lua for running tests
-- This sets up the minimum Neovim environment needed for testing

-- Add the plugin to the runtimepath
local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(plugin_root)

-- Add plenary for testing (if available)
local plenary_path = vim.fn.expand("~/.local/share/nvim/lazy/plenary.nvim")
if vim.fn.isdirectory(plenary_path) == 1 then
	vim.opt.rtp:prepend(plenary_path)
end

-- Alternative plenary paths
local alt_plenary_paths = {
	vim.fn.expand("~/.local/share/nvim/site/pack/*/start/plenary.nvim"),
	vim.fn.expand("~/.config/nvim/plugged/plenary.nvim"),
	"/opt/homebrew/share/nvim/site/pack/packer/start/plenary.nvim",
}

for _, path in ipairs(alt_plenary_paths) do
	local expanded = vim.fn.glob(path)
	if expanded ~= "" and vim.fn.isdirectory(expanded) == 1 then
		vim.opt.rtp:prepend(expanded)
		break
	end
end

-- Set up test environment
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.writebackup = false

-- Initialize codetyper with test defaults
require("codetyper").setup({
	llm = {
		provider = "ollama",
		ollama = {
			host = "http://localhost:11434",
			model = "test-model",
		},
	},
	scheduler = {
		enabled = false, -- Disable scheduler during tests
	},
	auto_gitignore = false,
	auto_open_ask = false,
})
