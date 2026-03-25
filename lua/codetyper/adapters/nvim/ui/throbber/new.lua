local Throbber = require("codetyper.adapters.nvim.ui.throbber.class")
local throb_icons = require("codetyper.constants.constants").throb_icons
local throb_time = require("codetyper.constants.constants").throb_time
local cooldown_time = require("codetyper.constants.constants").cooldown_time

Throbber._run = require("codetyper.adapters.nvim.ui.throbber.run")
Throbber.start = require("codetyper.adapters.nvim.ui.throbber.start")
Throbber.stop = require("codetyper.adapters.nvim.ui.throbber.stop")

---@param cb fun(icon: string)
---@param opts? { throb_time?: number, cooldown_time?: number }
---@return Throbber
local function new(cb, opts)
  opts = opts or {}
  local throb_time_ms = opts.throb_time or throb_time
  local cooldown_ms = opts.cooldown_time or cooldown_time
  local icon_set = throb_icons[math.random(#throb_icons)]
  return setmetatable({
    state = "init",
    start_time = 0,
    section_time = throb_time_ms,
    opts = { throb_time = throb_time_ms, cooldown_time = cooldown_ms },
    cb = cb,
    icon_set = icon_set,
  }, Throbber)
end

return new
