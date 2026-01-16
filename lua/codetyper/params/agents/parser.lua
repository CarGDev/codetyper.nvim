---@mod codetyper.params.agents.parser Parser regex patterns
local M = {}

M.patterns = {
    fenced_json = "```json%s*(%b{})%s*```",
    inline_json = '(%{"tool"%s*:%s*"[^"]+"%s*,%s*"parameters"%s*:%s*%b{}%})',
}

M.defaults = {
    stop_reason = "end_turn",
    tool_stop_reason = "tool_use",
    replacement_text = "[Tool call]",
}

return M