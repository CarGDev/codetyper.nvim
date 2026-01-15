---@mod codetyper.agent.permissions Permission manager for agent actions
---
--- Manages permissions for bash commands and file operations with
--- allow, allow-session, allow-list, and reject options.

local M = {}

---@class PermissionState
---@field session_allowed table<string, boolean> Commands allowed for this session
---@field allow_list table<string, boolean> Patterns always allowed
---@field deny_list table<string, boolean> Patterns always denied

local state = {
	session_allowed = {},
	allow_list = {},
	deny_list = {},
}

--- Dangerous command patterns that should never be auto-allowed
local DANGEROUS_PATTERNS = {
	"^rm%s+%-rf",
	"^rm%s+%-r%s+/",
	"^rm%s+/",
	"^sudo%s+rm",
	"^chmod%s+777",
	"^chmod%s+%-R",
	"^chown%s+%-R",
	"^dd%s+",
	"^mkfs",
	"^fdisk",
	"^format",
	":.*>%s*/dev/",
	"^curl.*|.*sh",
	"^wget.*|.*sh",
	"^eval%s+",
	"`;.*`",
	"%$%(.*%)",
	"fork%s*bomb",
}

--- Safe command patterns that can be auto-allowed
local SAFE_PATTERNS = {
	"^ls%s",
	"^ls$",
	"^cat%s",
	"^head%s",
	"^tail%s",
	"^grep%s",
	"^find%s",
	"^pwd$",
	"^echo%s",
	"^wc%s",
	"^which%s",
	"^type%s",
	"^file%s",
	"^stat%s",
	"^git%s+status",
	"^git%s+log",
	"^git%s+diff",
	"^git%s+branch",
	"^git%s+show",
	"^npm%s+list",
	"^npm%s+ls",
	"^npm%s+outdated",
	"^yarn%s+list",
	"^cargo%s+check",
	"^cargo%s+test",
	"^go%s+test",
	"^go%s+build",
	"^make%s+test",
	"^make%s+check",
}

---@alias PermissionLevel "allow"|"allow_session"|"allow_list"|"reject"

---@class PermissionResult
---@field allowed boolean Whether action is allowed
---@field reason string Reason for the decision
---@field auto boolean Whether this was an automatic decision

--- Check if a command matches a pattern
---@param command string The command to check
---@param pattern string The pattern to match
---@return boolean
local function matches_pattern(command, pattern)
	return command:match(pattern) ~= nil
end

--- Check if command is dangerous
---@param command string The command to check
---@return boolean, string|nil dangerous, reason
local function is_dangerous(command)
	for _, pattern in ipairs(DANGEROUS_PATTERNS) do
		if matches_pattern(command, pattern) then
			return true, "Matches dangerous pattern: " .. pattern
		end
	end
	return false, nil
end

--- Check if command is safe
---@param command string The command to check
---@return boolean
local function is_safe(command)
	for _, pattern in ipairs(SAFE_PATTERNS) do
		if matches_pattern(command, pattern) then
			return true
		end
	end
	return false
end

--- Normalize command for comparison (trim, lowercase first word)
---@param command string
---@return string
local function normalize_command(command)
	return vim.trim(command)
end

--- Check permission for a bash command
---@param command string The command to check
---@return PermissionResult
function M.check_bash_permission(command)
	local normalized = normalize_command(command)

	-- Check deny list first
	for pattern, _ in pairs(state.deny_list) do
		if matches_pattern(normalized, pattern) then
			return {
				allowed = false,
				reason = "Command in deny list",
				auto = true,
			}
		end
	end

	-- Check if command is dangerous
	local dangerous, reason = is_dangerous(normalized)
	if dangerous then
		return {
			allowed = false,
			reason = reason,
			auto = false, -- Require explicit approval for dangerous commands
		}
	end

	-- Check session allowed
	if state.session_allowed[normalized] then
		return {
			allowed = true,
			reason = "Allowed for this session",
			auto = true,
		}
	end

	-- Check allow list patterns
	for pattern, _ in pairs(state.allow_list) do
		if matches_pattern(normalized, pattern) then
			return {
				allowed = true,
				reason = "Matches allow list pattern",
				auto = true,
			}
		end
	end

	-- Check if command is inherently safe
	if is_safe(normalized) then
		return {
			allowed = true,
			reason = "Safe read-only command",
			auto = true,
		}
	end

	-- Otherwise, require explicit permission
	return {
		allowed = false,
		reason = "Requires approval",
		auto = false,
	}
end

--- Grant permission for a command
---@param command string The command
---@param level PermissionLevel The permission level
function M.grant_permission(command, level)
	local normalized = normalize_command(command)

	if level == "allow_session" then
		state.session_allowed[normalized] = true
	elseif level == "allow_list" then
		-- Add as pattern (escape special chars for exact match)
		local pattern = "^" .. vim.pesc(normalized) .. "$"
		state.allow_list[pattern] = true
	end
end

--- Add a pattern to the allow list
---@param pattern string Lua pattern to allow
function M.add_to_allow_list(pattern)
	state.allow_list[pattern] = true
end

--- Add a pattern to the deny list
---@param pattern string Lua pattern to deny
function M.add_to_deny_list(pattern)
	state.deny_list[pattern] = true
end

--- Clear session permissions
function M.clear_session()
	state.session_allowed = {}
end

--- Reset all permissions
function M.reset()
	state.session_allowed = {}
	state.allow_list = {}
	state.deny_list = {}
end

--- Get current permission state (for debugging)
---@return PermissionState
function M.get_state()
	return vim.deepcopy(state)
end

return M
