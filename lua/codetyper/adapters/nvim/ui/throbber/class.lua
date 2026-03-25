---@class Throbber
---@field state "init"|"throbbing"|"cooldown"|"stopped"
---@field start_time number
---@field section_time number
---@field opts { throb_time: number, cooldown_time: number }
---@field cb fun(icon: string)
---@field icon_set string[]
---@field _run fun(self: Throbber)

local Throbber = require("codetyper.constants.constants").Throbber
Throbber.__index = Throbber

return Throbber
