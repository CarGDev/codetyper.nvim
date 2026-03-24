local M = {}

-- Get current codetyper configuration at call time
function M.get_config()
  local ok, codetyper = pcall(require, "codetyper")
  if ok and codetyper.get_config then
    return codetyper.get_config() or {}
  end
  -- Fall back to defaults if codetyper isn't available
  local defaults = require("codetyper.config.defaults")
  return defaults.get_defaults()
end

return M
