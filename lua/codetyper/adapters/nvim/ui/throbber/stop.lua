--- Stop the throbbing animation
---@param self Throbber
local function stop(self)
  self.state = "stopped"
end

return stop
