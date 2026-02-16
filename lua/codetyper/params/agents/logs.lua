---@mod codetyper.params.agents.logs Log parameters
local M = {}

M.icons = {
    start = "->",
    success = "OK",
    error = "ERR",
    approval = "??",
    approved = "YES",
    rejected = "NO",
}

M.level_icons = {
    info = "i",
    debug = ".",
    request = ">",
    response = "<",
    tool = "T",
    error = "!",
    warning = "?",
    success = "i",
    queue = "Q",
    patch = "P",
}

M.thinking_types = { "thinking", "reason", "action", "task", "result" }

M.thinking_prefixes = {
      thinking = "⏺",
      reason = "⏺",
      action = "⏺",
      task = "✶",
      result = "",
}

return M