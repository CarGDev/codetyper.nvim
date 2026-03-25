local now = require("codetyper.utils.get_now")
local tick_time = require("codetyper.constants.constants").tick_time

--- Internal tick loop: compute current icon, transition state, schedule next tick
---@param self Throbber
local function run(self)
  if self.state ~= "throbbing" and self.state ~= "cooldown" then
    return
  end
  local elapsed = now() - self.start_time
  local percent = math.min(1, elapsed / self.section_time)
  local icon_index = math.floor(percent * #self.icon_set) + 1
  icon_index = math.min(icon_index, #self.icon_set)
  local icon = self.icon_set[icon_index]

  if percent >= 1 then
    self.state = self.state == "cooldown" and "throbbing" or "cooldown"
    self.start_time = now()
    self.section_time = (self.state == "cooldown") and self.opts.cooldown_time or self.opts.throb_time
  end

  self.cb(icon)
  vim.defer_fn(function()
    self:_run()
  end, tick_time)
end

return run
