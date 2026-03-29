--- TODO: remove after debugging — File-only logger for /tmp/codetyper.tmp.log
local LOG_PATH = "/tmp/codetyper.tmp.log"

---@param level string
---@param module string
---@param message string
local function write(level, module, message)
  local f = io.open(LOG_PATH, "a")
  if not f then
    -- fallback: try creating it
    f = io.open(LOG_PATH, "w")
  end
  if f then
    f:write(string.format("[%s] [%s] [%s] %s\n", os.date("%H:%M:%S"), level, module, message))
    f:flush()
    f:close()
  end
end

-- Write immediately on module load so we know require works
write("INFO", "flog", "=== flog module loaded ===")

local M = {}

function M.info(module, message)
  write("INFO", module, message)
end

function M.warn(module, message)
  write("WARN", module, message)
end

function M.error(module, message)
  write("ERR", module, message)
end

function M.debug(module, message)
  write("DBG", module, message)
end

return M
