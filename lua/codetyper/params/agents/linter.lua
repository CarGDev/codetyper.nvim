---@mod codetyper.params.agents.linter Linter configuration
local M = {}

M.config = {
	-- Auto-save file after code injection
	auto_save = true,
	-- Delay in ms to wait for LSP diagnostics to update
	diagnostic_delay_ms = 500,
	-- Severity levels to check (1=Error, 2=Warning, 3=Info, 4=Hint)
	min_severity = vim.diagnostic.severity.WARN,
	-- Auto-offer to fix lint errors
	auto_offer_fix = true,
}

return M
