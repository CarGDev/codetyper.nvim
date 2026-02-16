-- Codetyper.nvim - AI-powered coding partner for Neovim
-- Plugin loader

local g = vim.g
local fn = vim.fn
local api = vim.api
local cmd = vim.cmd

-- Prevent loading twice
if g.loaded_codetyper then
	return
end
g.loaded_codetyper = true

-- Minimum Neovim version check
if fn.has("nvim-0.8.0") == 0 then
	api.nvim_err_writeln("Codetyper.nvim requires Neovim 0.8.0 or higher")
	return
end

--- Initialize codetyper plugin fully
--- Creates .coder folder, settings.json, tree.log, .gitignore
--- Also registers autocmds for /@ @/ prompt detection
---@return boolean success
local function init_coder_files()
	local ok, err = pcall(function()
		-- Full plugin initialization (includes config, commands, autocmds, tree, gitignore)
		local codetyper = require("codetyper")
		if not codetyper.is_initialized() then
			codetyper.setup()
		end
	end)

	if not ok then
		vim.notify("[Codetyper] Failed to initialize: " .. tostring(err), vim.log.levels.ERROR)
		return false
	end
	return true
end

-- Initialize .coder folder and tree.log on project open
api.nvim_create_autocmd("VimEnter", {
	callback = function()
		-- Delay slightly to ensure cwd is set
		vim.defer_fn(function()
			init_coder_files()
		end, 100)
	end,
	desc = "Initialize Codetyper .coder folder on startup",
})

-- Also initialize on directory change
api.nvim_create_autocmd("DirChanged", {
	callback = function()
		vim.defer_fn(function()
			init_coder_files()
		end, 100)
	end,
	desc = "Initialize Codetyper .coder folder on directory change",
})

-- Auto-initialize when opening a coder file (for nvim-tree, telescope, etc.)
api.nvim_create_autocmd({ "BufRead", "BufNewFile", "BufEnter" }, {
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
api.nvim_create_user_command("Coder", function(opts)
	require("codetyper").setup()
	-- Re-execute the command now that plugin is loaded
	cmd("Coder " .. (opts.args or ""))
end, {
	nargs = "?",
	complete = function()
		return {
			"open",
			"close",
			"toggle",
			"process",
			"status",
			"focus",
			"tree",
			"tree-view",
			"reset",
			"gitignore",
		}
	end,
	desc = "Codetyper.nvim commands",
})

-- Lazy-load aliases
api.nvim_create_user_command("CoderOpen", function()
	require("codetyper").setup()
	cmd("CoderOpen")
end, { desc = "Open Coder view" })

api.nvim_create_user_command("CoderClose", function()
	require("codetyper").setup()
	cmd("CoderClose")
end, { desc = "Close Coder view" })

api.nvim_create_user_command("CoderToggle", function()
	require("codetyper").setup()
	cmd("CoderToggle")
end, { desc = "Toggle Coder view" })

api.nvim_create_user_command("CoderProcess", function()
	require("codetyper").setup()
	cmd("CoderProcess")
end, { desc = "Process prompt and generate code" })

api.nvim_create_user_command("CoderTree", function()
	require("codetyper").setup()
	cmd("CoderTree")
end, { desc = "Refresh tree.log" })

api.nvim_create_user_command("CoderTreeView", function()
	require("codetyper").setup()
	cmd("CoderTreeView")
end, { desc = "View tree.log" })


