---@mod codetyper.params.agents.search_replace Search/Replace patterns
local M = {}

M.patterns = {
    dash_style = "%-%-%-%-%-%-%-?%s*SEARCH%s*\n(.-)\n=======%s*\n(.-)\n%+%+%+%+%+%+%+?%s*REPLACE",
    claude_style = "<<<<<<<[%s]*SEARCH%s*\n(.-)\n=======%s*\n(.-)\n>>>>>>>[%s]*REPLACE",
    simple_style = "%[SEARCH%]%s*\n(.-)\n%[REPLACE%]%s*\n(.-)\n%[END%]",
    diff_block = "```diff\n(.-)\n```",
}

return M