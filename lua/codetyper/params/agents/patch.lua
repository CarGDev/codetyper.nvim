---@mod codetyper.params.agents.patch Patch configuration
local M = {}

M.config = {
	snapshot_range = 5, -- Lines above/below prompt to snapshot
	clean_interval_ms = 60000, -- Check for stale patches every minute
	max_age_ms = 3600000, -- 1 hour TTL
	staleness_check = true,
	use_search_replace_parser = true, -- Enable new parsing logic
}

return M
