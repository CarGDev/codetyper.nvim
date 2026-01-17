---@mod codetyper.detector.triggers
---
--- Simple trigger utilities for prompt detection. Configuration-driven.

local M = {}

local function get_config()
  local ok, codetyper = pcall(require, "codetyper")
  if ok and codetyper.get_config then
    return codetyper.get_config()
  end
  return { patterns = { open_tag = "/@", close_tag = "@/" } }
end

function M.is_trigger(char)
  local cfg = get_config()
  local open = cfg.patterns.open_tag or "/@"
  return char == open:sub(1,1)
end

function M.get_trigger_pattern()
  local cfg = get_config()
  return cfg.patterns or { open_tag = "/@", close_tag = "@/" }
end

return M
