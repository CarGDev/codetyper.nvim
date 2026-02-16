---@mod codetyper.ui.throbber Animated thinking spinner (99-style)
---@brief [[
--- Unicode throbber icons, runs a timer and calls cb(icon) every tick.
---@brief ]]

local M = {}

local throb_icons = {
	{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
	{ "◐", "◓", "◑", "◒" },
	{ "⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷" },
	{ "◰", "◳", "◲", "◱" },
	{ "◜", "◠", "◝", "◞", "◡", "◟" },
}

local throb_time = 1200
local cooldown_time = 100
local tick_time = 100

local function now()
	return vim.uv and vim.uv.now() or (os.clock() * 1000)
end

---@class Throbber
---@field state "init"|"throbbing"|"cooldown"|"stopped"
---@field start_time number
---@field section_time number
---@field opts { throb_time: number, cooldown_time: number }
---@field cb fun(icon: string)
---@field icon_set string[]
---@field _run fun(self: Throbber)

local Throbber = {}
Throbber.__index = Throbber

---@param cb fun(icon: string)
---@param opts? { throb_time?: number, cooldown_time?: number }
---@return Throbber
function M.new(cb, opts)
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

function Throbber:_run()
	if self.state ~= "throbbing" and self.state ~= "cooldown" then
		return
	end
	local elapsed = now() - self.start_time
	local percent = math.min(1, elapsed / self.section_time)
	local idx = math.floor(percent * #self.icon_set) + 1
	idx = math.min(idx, #self.icon_set)
	local icon = self.icon_set[idx]

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

function Throbber:start()
	self.start_time = now()
	self.section_time = self.opts.throb_time
	self.state = "throbbing"
	self:_run()
end

function Throbber:stop()
	self.state = "stopped"
end

return M
