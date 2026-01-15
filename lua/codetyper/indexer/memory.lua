---@mod codetyper.indexer.memory Memory persistence manager
---@brief [[
--- Stores and retrieves learned patterns and memories in .coder/memories/.
--- Supports session history for learning from interactions.
---@brief ]]

local M = {}

local utils = require("codetyper.utils")

--- Memory directories
local MEMORIES_DIR = "memories"
local SESSIONS_DIR = "sessions"
local FILES_DIR = "files"

--- Memory files
local PATTERNS_FILE = "patterns.json"
local CONVENTIONS_FILE = "conventions.json"
local SYMBOLS_FILE = "symbols.json"

--- In-memory cache
local cache = {
	patterns = nil,
	conventions = nil,
	symbols = nil,
}

---@class Memory
---@field id string Unique identifier
---@field type "pattern"|"convention"|"session"|"interaction"
---@field content string The learned information
---@field context table Where/when learned
---@field weight number Importance score (0.0-1.0)
---@field created_at number Timestamp
---@field updated_at number Last update timestamp
---@field used_count number Times referenced

--- Get the memories base directory
---@return string|nil
local function get_memories_dir()
	local root = utils.get_project_root()
	if not root then
		return nil
	end
	return root .. "/.coder/" .. MEMORIES_DIR
end

--- Get the sessions directory
---@return string|nil
local function get_sessions_dir()
	local root = utils.get_project_root()
	if not root then
		return nil
	end
	return root .. "/.coder/" .. SESSIONS_DIR
end

--- Ensure memories directory exists
---@return boolean
local function ensure_memories_dir()
	local dir = get_memories_dir()
	if not dir then
		return false
	end
	utils.ensure_dir(dir)
	utils.ensure_dir(dir .. "/" .. FILES_DIR)
	return true
end

--- Ensure sessions directory exists
---@return boolean
local function ensure_sessions_dir()
	local dir = get_sessions_dir()
	if not dir then
		return false
	end
	return utils.ensure_dir(dir)
end

--- Generate a unique ID
---@return string
local function generate_id()
	return string.format("mem_%d_%s", os.time(), string.sub(tostring(math.random()), 3, 8))
end

--- Load a memory file
---@param filename string
---@return table
local function load_memory_file(filename)
	local dir = get_memories_dir()
	if not dir then
		return {}
	end

	local path = dir .. "/" .. filename
	local content = utils.read_file(path)
	if not content then
		return {}
	end

	local ok, data = pcall(vim.json.decode, content)
	if not ok or not data then
		return {}
	end

	return data
end

--- Save a memory file
---@param filename string
---@param data table
---@return boolean
local function save_memory_file(filename, data)
	if not ensure_memories_dir() then
		return false
	end

	local dir = get_memories_dir()
	if not dir then
		return false
	end

	local path = dir .. "/" .. filename
	local ok, encoded = pcall(vim.json.encode, data)
	if not ok then
		return false
	end

	return utils.write_file(path, encoded)
end

--- Hash a file path for storage
---@param filepath string
---@return string
local function hash_path(filepath)
	local hash = 0
	for i = 1, #filepath do
		hash = (hash * 31 + string.byte(filepath, i)) % 2147483647
	end
	return string.format("%08x", hash)
end

--- Load patterns from cache or disk
---@return table
function M.load_patterns()
	if cache.patterns then
		return cache.patterns
	end
	cache.patterns = load_memory_file(PATTERNS_FILE)
	return cache.patterns
end

--- Load conventions from cache or disk
---@return table
function M.load_conventions()
	if cache.conventions then
		return cache.conventions
	end
	cache.conventions = load_memory_file(CONVENTIONS_FILE)
	return cache.conventions
end

--- Load symbols from cache or disk
---@return table
function M.load_symbols()
	if cache.symbols then
		return cache.symbols
	end
	cache.symbols = load_memory_file(SYMBOLS_FILE)
	return cache.symbols
end

--- Store a new memory
---@param memory Memory
---@return boolean
function M.store_memory(memory)
	memory.id = memory.id or generate_id()
	memory.created_at = memory.created_at or os.time()
	memory.updated_at = os.time()
	memory.used_count = memory.used_count or 0
	memory.weight = memory.weight or 0.5

	local filename
	if memory.type == "pattern" then
		filename = PATTERNS_FILE
		cache.patterns = nil
	elseif memory.type == "convention" then
		filename = CONVENTIONS_FILE
		cache.conventions = nil
	else
		filename = PATTERNS_FILE
		cache.patterns = nil
	end

	local data = load_memory_file(filename)
	data[memory.id] = memory

	return save_memory_file(filename, data)
end

--- Store file-specific memory
---@param relative_path string Relative file path
---@param file_index table FileIndex data
---@return boolean
function M.store_file_memory(relative_path, file_index)
	if not ensure_memories_dir() then
		return false
	end

	local dir = get_memories_dir()
	if not dir then
		return false
	end

	local hash = hash_path(relative_path)
	local path = dir .. "/" .. FILES_DIR .. "/" .. hash .. ".json"

	local data = {
		path = relative_path,
		indexed_at = os.time(),
		functions = file_index.functions or {},
		classes = file_index.classes or {},
		exports = file_index.exports or {},
		imports = file_index.imports or {},
	}

	local ok, encoded = pcall(vim.json.encode, data)
	if not ok then
		return false
	end

	return utils.write_file(path, encoded)
end

--- Load file-specific memory
---@param relative_path string
---@return table|nil
function M.load_file_memory(relative_path)
	local dir = get_memories_dir()
	if not dir then
		return nil
	end

	local hash = hash_path(relative_path)
	local path = dir .. "/" .. FILES_DIR .. "/" .. hash .. ".json"

	local content = utils.read_file(path)
	if not content then
		return nil
	end

	local ok, data = pcall(vim.json.decode, content)
	if not ok then
		return nil
	end

	return data
end

--- Store index summary as memories
---@param index ProjectIndex
function M.store_index_summary(index)
	-- Store project type convention
	if index.project_type and index.project_type ~= "unknown" then
		M.store_memory({
			type = "convention",
			content = "Project uses " .. index.project_type .. " ecosystem",
			context = {
				project_root = index.project_root,
				detected_at = os.time(),
			},
			weight = 0.9,
		})
	end

	-- Store dependency patterns
	local dep_count = 0
	for _ in pairs(index.dependencies or {}) do
		dep_count = dep_count + 1
	end

	if dep_count > 0 then
		local deps_list = {}
		for name, _ in pairs(index.dependencies) do
			table.insert(deps_list, name)
		end

		M.store_memory({
			type = "pattern",
			content = "Project dependencies: " .. table.concat(deps_list, ", "),
			context = {
				dependency_count = dep_count,
			},
			weight = 0.7,
		})
	end

	-- Update symbol cache
	cache.symbols = nil
	save_memory_file(SYMBOLS_FILE, index.symbols or {})
end

--- Store session interaction
---@param interaction {prompt: string, response: string, file: string|nil, success: boolean}
function M.store_session(interaction)
	if not ensure_sessions_dir() then
		return
	end

	local dir = get_sessions_dir()
	if not dir then
		return
	end

	-- Use date-based session files
	local date = os.date("%Y-%m-%d")
	local path = dir .. "/" .. date .. ".json"

	local sessions = {}
	local content = utils.read_file(path)
	if content then
		local ok, data = pcall(vim.json.decode, content)
		if ok and data then
			sessions = data
		end
	end

	table.insert(sessions, {
		timestamp = os.time(),
		prompt = interaction.prompt,
		response = string.sub(interaction.response or "", 1, 500), -- Truncate
		file = interaction.file,
		success = interaction.success,
	})

	-- Limit session size
	if #sessions > 100 then
		sessions = { unpack(sessions, #sessions - 99) }
	end

	local ok, encoded = pcall(vim.json.encode, sessions)
	if ok then
		utils.write_file(path, encoded)
	end
end

--- Get relevant memories for a query
---@param query string Search query
---@param limit number Maximum results
---@return Memory[]
function M.get_relevant(query, limit)
	limit = limit or 10
	local results = {}

	-- Tokenize query
	local query_words = {}
	for word in query:lower():gmatch("%w+") do
		if #word > 2 then
			query_words[word] = true
		end
	end

	-- Search patterns
	local patterns = M.load_patterns()
	for _, memory in pairs(patterns) do
		local score = 0
		local content_lower = (memory.content or ""):lower()

		for word in pairs(query_words) do
			if content_lower:find(word, 1, true) then
				score = score + 1
			end
		end

		if score > 0 then
			memory.relevance_score = score * (memory.weight or 0.5)
			table.insert(results, memory)
		end
	end

	-- Search conventions
	local conventions = M.load_conventions()
	for _, memory in pairs(conventions) do
		local score = 0
		local content_lower = (memory.content or ""):lower()

		for word in pairs(query_words) do
			if content_lower:find(word, 1, true) then
				score = score + 1
			end
		end

		if score > 0 then
			memory.relevance_score = score * (memory.weight or 0.5)
			table.insert(results, memory)
		end
	end

	-- Sort by relevance
	table.sort(results, function(a, b)
		return (a.relevance_score or 0) > (b.relevance_score or 0)
	end)

	-- Limit results
	local limited = {}
	for i = 1, math.min(limit, #results) do
		limited[i] = results[i]
	end

	return limited
end

--- Update memory usage count
---@param memory_id string
function M.update_usage(memory_id)
	local patterns = M.load_patterns()
	if patterns[memory_id] then
		patterns[memory_id].used_count = (patterns[memory_id].used_count or 0) + 1
		patterns[memory_id].updated_at = os.time()
		save_memory_file(PATTERNS_FILE, patterns)
		cache.patterns = nil
		return
	end

	local conventions = M.load_conventions()
	if conventions[memory_id] then
		conventions[memory_id].used_count = (conventions[memory_id].used_count or 0) + 1
		conventions[memory_id].updated_at = os.time()
		save_memory_file(CONVENTIONS_FILE, conventions)
		cache.conventions = nil
	end
end

--- Get all memories
---@return {patterns: table, conventions: table, symbols: table}
function M.get_all()
	return {
		patterns = M.load_patterns(),
		conventions = M.load_conventions(),
		symbols = M.load_symbols(),
	}
end

--- Clear all memories
---@param pattern? string Optional pattern to match memory IDs
function M.clear(pattern)
	if not pattern then
		-- Clear all
		cache = { patterns = nil, conventions = nil, symbols = nil }
		save_memory_file(PATTERNS_FILE, {})
		save_memory_file(CONVENTIONS_FILE, {})
		save_memory_file(SYMBOLS_FILE, {})
		return
	end

	-- Clear matching pattern
	local patterns = M.load_patterns()
	for id in pairs(patterns) do
		if id:match(pattern) then
			patterns[id] = nil
		end
	end
	save_memory_file(PATTERNS_FILE, patterns)
	cache.patterns = nil

	local conventions = M.load_conventions()
	for id in pairs(conventions) do
		if id:match(pattern) then
			conventions[id] = nil
		end
	end
	save_memory_file(CONVENTIONS_FILE, conventions)
	cache.conventions = nil
end

--- Prune low-weight memories
---@param threshold number Weight threshold (default: 0.1)
function M.prune(threshold)
	threshold = threshold or 0.1

	local patterns = M.load_patterns()
	local pruned = 0
	for id, memory in pairs(patterns) do
		if (memory.weight or 0) < threshold and (memory.used_count or 0) == 0 then
			patterns[id] = nil
			pruned = pruned + 1
		end
	end
	if pruned > 0 then
		save_memory_file(PATTERNS_FILE, patterns)
		cache.patterns = nil
	end

	local conventions = M.load_conventions()
	for id, memory in pairs(conventions) do
		if (memory.weight or 0) < threshold and (memory.used_count or 0) == 0 then
			conventions[id] = nil
			pruned = pruned + 1
		end
	end
	if pruned > 0 then
		save_memory_file(CONVENTIONS_FILE, conventions)
		cache.conventions = nil
	end

	return pruned
end

--- Get memory statistics
---@return table
function M.get_stats()
	local patterns = M.load_patterns()
	local conventions = M.load_conventions()
	local symbols = M.load_symbols()

	local pattern_count = 0
	for _ in pairs(patterns) do
		pattern_count = pattern_count + 1
	end

	local convention_count = 0
	for _ in pairs(conventions) do
		convention_count = convention_count + 1
	end

	local symbol_count = 0
	for _ in pairs(symbols) do
		symbol_count = symbol_count + 1
	end

	return {
		patterns = pattern_count,
		conventions = convention_count,
		symbols = symbol_count,
		total = pattern_count + convention_count,
	}
end

return M
