local queue = require("codetyper.core.events.queue")

--- Get the total number of pending + processing queue items
---@return number
local function active_count()
  return queue.pending_count() + queue.processing_count()
end

return active_count
