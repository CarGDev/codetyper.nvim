---@mod codetyper.params.agents.worker Worker configuration and patterns
local M = {}

--- Patterns that indicate LLM needs more context (must be near start of response)
M.context_needed_patterns = {
	"I need to see",
	"Could you provide",
	"Please provide",
	"Can you show",
	"don't have enough context",
	"need more information",
	"cannot see the definition",
	"missing the implementation",
	"I would need to check",
	"please share",
	"Please upload",
	"could not find",
}

--- Default timeouts by provider type
M.default_timeouts = {
	openai = 60000, -- 60s
	anthropic = 90000, -- 90s
	google = 60000, -- 60s
	ollama = 120000, -- 120s (local models can be slower)
	copilot = 60000, -- 60s
	default = 60000,
}

return M
