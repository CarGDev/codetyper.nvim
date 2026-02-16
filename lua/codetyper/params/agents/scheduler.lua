---@mod codetyper.params.agents.scheduler Scheduler configuration
--- 99-style: multiple requests can run in parallel (thinking); user can keep typing.
--- Injection uses extmarks so position is preserved across edits.
local M = {}

M.config = {
	enabled = true,
	ollama_scout = true,
	escalation_threshold = 0.7,
	max_concurrent = 5, -- Allow multiple in-flight requests (like 99); user can type while thinking
	completion_delay_ms = 100,
	apply_delay_ms = 5000, -- Wait before applying code
	remote_provider = "copilot", -- Default fallback provider
}

return M
