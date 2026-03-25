local now = require("codetyper.utils.get_now")

--- Begin the throbbing animation
---@param self Throbber
local function start(self)
  self.start_time = now()
  self.section_time = self.opts.throb_time
  self.state = "throbbing"
  self:_run()
end

return start
