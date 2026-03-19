---@mod codetyper.preferences User preferences management
---@brief [[
--- Manages user preferences stored in .codetyper/preferences.json
--- Allows per-project configuration of plugin behavior.
---@brief ]]

local M = {}

local utils = require("codetyper.support.utils")

---@class CoderPreferences

--- Default preferences
local defaults = {
	auto_process = nil, -- nil means "not yet decided"
	asked_auto_process = false,
}

--- Cached preferences per project
---@type table<string, CoderPreferences>
local cache = {}

--- Get the preferences file path for current project
---@return string
local function get_preferences_path()
	local cwd = vim.fn.getcwd()
	return cwd .. "/.codetyper/preferences.json"
end

--- Ensure .codetyper directory exists
local function ensure_coder_dir()
	local cwd = vim.fn.getcwd()
	local coder_dir = cwd .. "/.codetyper"
	if vim.fn.isdirectory(coder_dir) == 0 then
		vim.fn.mkdir(coder_dir, "p")
	end
end

--- Load preferences from file
---@return CoderPreferences
function M.load()
	local cwd = vim.fn.getcwd()

	-- Check cache first
	if cache[cwd] then
		return cache[cwd]
	end

	local path = get_preferences_path()
	local prefs = vim.deepcopy(defaults)

	if utils.file_exists(path) then
		local content = utils.read_file(path)
		if content then
			local ok, decoded = pcall(vim.json.decode, content)
			if ok and decoded then
				-- Merge with defaults
				for k, v in pairs(decoded) do
					prefs[k] = v
				end
			end
		end
	end

	-- Cache it
	cache[cwd] = prefs
	return prefs
end

--- Save preferences to file
---@param prefs CoderPreferences
function M.save(prefs)
	local cwd = vim.fn.getcwd()
	ensure_coder_dir()

	local path = get_preferences_path()
	local ok, encoded = pcall(vim.json.encode, prefs)
	if ok then
		utils.write_file(path, encoded)
		-- Update cache
		cache[cwd] = prefs
	end
end

--- Get a specific preference
---@param key string
---@return any
function M.get(key)
	local prefs = M.load()
	return prefs[key]
end

--- Set a specific preference
---@param key string
---@param value any
function M.set(key, value)
	local prefs = M.load()
	prefs[key] = value
	M.save(prefs)
end

--- Check if auto-process is enabled
---@return boolean|nil Returns true/false if set, nil if not yet decided
function M.is_auto_process_enabled()
	return M.get("auto_process")
end

--- Set auto-process preference
---@param enabled boolean
function M.set_auto_process(enabled)
	M.set("auto_process", enabled)
	M.set("asked_auto_process", true)
end

--- Check if we've already asked the user about auto-process
---@return boolean
function M.has_asked_auto_process()
	return M.get("asked_auto_process") == true
end

--- Clear cached preferences (useful when changing projects)
function M.clear_cache()
	cache = {}
end

--- Toggle auto-process mode
function M.toggle_auto_process()
	local current = M.is_auto_process_enabled()
	local new_value = not current
	M.set_auto_process(new_value)
	local mode = new_value and "automatic" or "manual"
	vim.notify("Codetyper: Switched to " .. mode .. " mode", vim.log.levels.INFO)
end

return M
