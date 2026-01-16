---@mod codetyper.params.agent.scheduler Scheduler configuration
local M = {}

M.config = {
	enabled = true,
	ollama_scout = true,
	escalation_threshold = 0.7,
	max_concurrent = 2,
	completion_delay_ms = 100,
	apply_delay_ms = 5000, -- Wait before applying code
	remote_provider = "copilot", -- Default fallback provider
}

return M
