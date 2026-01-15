---@mod codetyper.indexer Project indexer for Codetyper.nvim
---@brief [[
--- Indexes project structure, dependencies, and code symbols.
--- Stores knowledge in .coder/ directory for enriching LLM context.
---@brief ]]

local M = {}

local utils = require("codetyper.utils")

--- Index schema version for migrations
local INDEX_VERSION = 1

--- Index file name
local INDEX_FILE = "index.json"

--- Debounce timer for file indexing
local index_timer = nil
local INDEX_DEBOUNCE_MS = 500

--- Default indexer configuration
local default_config = {
	enabled = true,
	auto_index = true,
	index_on_open = false,
	max_file_size = 100000,
	excluded_dirs = { "node_modules", "dist", "build", ".git", ".coder", "__pycache__", "vendor", "target" },
	index_extensions = { "lua", "ts", "tsx", "js", "jsx", "py", "go", "rs", "rb", "java", "c", "cpp", "h", "hpp" },
	memory = {
		enabled = true,
		max_memories = 1000,
		prune_threshold = 0.1,
	},
}

--- Current configuration
---@type table
local config = vim.deepcopy(default_config)

--- Cached project index
---@type table<string, ProjectIndex>
local index_cache = {}

---@class ProjectIndex
---@field version number Index schema version
---@field project_root string Absolute path to project
---@field project_name string Project name
---@field project_type string "node"|"rust"|"go"|"python"|"lua"|"unknown"
---@field dependencies table<string, string> name -> version
---@field dev_dependencies table<string, string> name -> version
---@field files table<string, FileIndex> path -> FileIndex
---@field symbols table<string, string[]> symbol -> [file paths]
---@field last_indexed number Timestamp
---@field stats {files: number, functions: number, classes: number, exports: number}

---@class FileIndex
---@field path string Relative path from project root
---@field language string Detected language
---@field hash string Content hash for change detection
---@field exports Export[] Exported symbols
---@field imports Import[] Dependencies
---@field functions FunctionInfo[]
---@field classes ClassInfo[]
---@field last_indexed number Timestamp

---@class Export
---@field name string Symbol name
---@field type string "function"|"class"|"constant"|"type"|"variable"
---@field line number Line number

---@class Import
---@field source string Import source/module
---@field names string[] Imported names
---@field line number Line number

---@class FunctionInfo
---@field name string Function name
---@field params string[] Parameter names
---@field line number Start line
---@field end_line number End line
---@field docstring string|nil Documentation

---@class ClassInfo
---@field name string Class name
---@field methods string[] Method names
---@field line number Start line
---@field end_line number End line
---@field docstring string|nil Documentation

--- Get the index file path
---@return string|nil
local function get_index_path()
	local root = utils.get_project_root()
	if not root then
		return nil
	end
	return root .. "/.coder/" .. INDEX_FILE
end

--- Create empty index structure
---@return ProjectIndex
local function create_empty_index()
	local root = utils.get_project_root()
	return {
		version = INDEX_VERSION,
		project_root = root or "",
		project_name = root and vim.fn.fnamemodify(root, ":t") or "",
		project_type = "unknown",
		dependencies = {},
		dev_dependencies = {},
		files = {},
		symbols = {},
		last_indexed = os.time(),
		stats = {
			files = 0,
			functions = 0,
			classes = 0,
			exports = 0,
		},
	}
end

--- Load index from disk
---@return ProjectIndex|nil
function M.load_index()
	local root = utils.get_project_root()
	if not root then
		return nil
	end

	-- Check cache first
	if index_cache[root] then
		return index_cache[root]
	end

	local path = get_index_path()
	if not path then
		return nil
	end

	local content = utils.read_file(path)
	if not content then
		return nil
	end

	local ok, index = pcall(vim.json.decode, content)
	if not ok or not index then
		return nil
	end

	-- Validate version
	if index.version ~= INDEX_VERSION then
		-- Index needs migration or rebuild
		return nil
	end

	-- Cache it
	index_cache[root] = index
	return index
end

--- Save index to disk
---@param index ProjectIndex
---@return boolean
function M.save_index(index)
	local root = utils.get_project_root()
	if not root then
		return false
	end

	-- Ensure .coder directory exists
	local coder_dir = root .. "/.coder"
	utils.ensure_dir(coder_dir)

	local path = get_index_path()
	if not path then
		return false
	end

	local ok, encoded = pcall(vim.json.encode, index)
	if not ok then
		return false
	end

	local success = utils.write_file(path, encoded)
	if success then
		-- Update cache
		index_cache[root] = index
	end
	return success
end

--- Index the entire project
---@param callback? fun(index: ProjectIndex)
---@return ProjectIndex|nil
function M.index_project(callback)
	local scanner = require("codetyper.indexer.scanner")
	local analyzer = require("codetyper.indexer.analyzer")

	local index = create_empty_index()
	local root = utils.get_project_root()

	if not root then
		if callback then
			callback(index)
		end
		return index
	end

	-- Detect project type and parse dependencies
	index.project_type = scanner.detect_project_type(root)
	local deps = scanner.parse_dependencies(root, index.project_type)
	index.dependencies = deps.dependencies or {}
	index.dev_dependencies = deps.dev_dependencies or {}

	-- Get all indexable files
	local files = scanner.get_indexable_files(root, config)

	-- Index each file
	local total_functions = 0
	local total_classes = 0
	local total_exports = 0

	for _, filepath in ipairs(files) do
		local relative_path = filepath:gsub("^" .. vim.pesc(root) .. "/", "")
		local file_index = analyzer.analyze_file(filepath)

		if file_index then
			file_index.path = relative_path
			index.files[relative_path] = file_index

			-- Update symbol index
			for _, exp in ipairs(file_index.exports or {}) do
				if not index.symbols[exp.name] then
					index.symbols[exp.name] = {}
				end
				table.insert(index.symbols[exp.name], relative_path)
				total_exports = total_exports + 1
			end

			total_functions = total_functions + #(file_index.functions or {})
			total_classes = total_classes + #(file_index.classes or {})
		end
	end

	-- Update stats
	index.stats = {
		files = #files,
		functions = total_functions,
		classes = total_classes,
		exports = total_exports,
	}
	index.last_indexed = os.time()

	-- Save to disk
	M.save_index(index)

	-- Store memories
	local memory = require("codetyper.indexer.memory")
	memory.store_index_summary(index)

	-- Sync project summary to brain
	M.sync_project_to_brain(index, files, root)

	if callback then
		callback(index)
	end

	return index
end

--- Sync project index to brain
---@param index ProjectIndex
---@param files string[] List of file paths
---@param root string Project root
function M.sync_project_to_brain(index, files, root)
	local ok_brain, brain = pcall(require, "codetyper.brain")
	if not ok_brain or not brain.is_initialized or not brain.is_initialized() then
		return
	end

	-- Store project-level pattern
	brain.learn({
		type = "pattern",
		file = root,
		content = {
			summary = "Project: "
				.. index.project_name
				.. " ("
				.. index.project_type
				.. ") - "
				.. index.stats.files
				.. " files",
			detail = string.format(
				"%d functions, %d classes, %d exports",
				index.stats.functions,
				index.stats.classes,
				index.stats.exports
			),
		},
		context = {
			file = root,
			project_type = index.project_type,
			dependencies = index.dependencies,
		},
	})

	-- Store key file patterns (files with most functions/classes)
	local key_files = {}
	for path, file_index in pairs(index.files) do
		local score = #(file_index.functions or {}) + (#(file_index.classes or {}) * 2)
		if score >= 3 then
			table.insert(key_files, { path = path, index = file_index, score = score })
		end
	end

	table.sort(key_files, function(a, b)
		return a.score > b.score
	end)

	-- Store top 20 key files in brain
	for i, kf in ipairs(key_files) do
		if i > 20 then
			break
		end
		M.sync_to_brain(root .. "/" .. kf.path, kf.index)
	end
end

--- Index a single file (incremental update)
---@param filepath string
---@return FileIndex|nil
function M.index_file(filepath)
	local analyzer = require("codetyper.indexer.analyzer")
	local memory = require("codetyper.indexer.memory")
	local root = utils.get_project_root()

	if not root then
		return nil
	end

	-- Load existing index
	local index = M.load_index() or create_empty_index()

	-- Analyze file
	local file_index = analyzer.analyze_file(filepath)
	if not file_index then
		return nil
	end

	local relative_path = filepath:gsub("^" .. vim.pesc(root) .. "/", "")
	file_index.path = relative_path

	-- Remove old symbol references for this file
	for symbol, paths in pairs(index.symbols) do
		for i = #paths, 1, -1 do
			if paths[i] == relative_path then
				table.remove(paths, i)
			end
		end
		if #paths == 0 then
			index.symbols[symbol] = nil
		end
	end

	-- Add new file index
	index.files[relative_path] = file_index

	-- Update symbol index
	for _, exp in ipairs(file_index.exports or {}) do
		if not index.symbols[exp.name] then
			index.symbols[exp.name] = {}
		end
		table.insert(index.symbols[exp.name], relative_path)
	end

	-- Recalculate stats
	local total_functions = 0
	local total_classes = 0
	local total_exports = 0
	local file_count = 0

	for _, f in pairs(index.files) do
		file_count = file_count + 1
		total_functions = total_functions + #(f.functions or {})
		total_classes = total_classes + #(f.classes or {})
		total_exports = total_exports + #(f.exports or {})
	end

	index.stats = {
		files = file_count,
		functions = total_functions,
		classes = total_classes,
		exports = total_exports,
	}
	index.last_indexed = os.time()

	-- Save to disk
	M.save_index(index)

	-- Store file memory
	memory.store_file_memory(relative_path, file_index)

	-- Sync to brain if available
	M.sync_to_brain(filepath, file_index)

	return file_index
end

--- Sync file analysis to brain system
---@param filepath string Full file path
---@param file_index FileIndex File analysis
function M.sync_to_brain(filepath, file_index)
	local ok_brain, brain = pcall(require, "codetyper.brain")
	if not ok_brain or not brain.is_initialized or not brain.is_initialized() then
		return
	end

	-- Only store if file has meaningful content
	local funcs = file_index.functions or {}
	local classes = file_index.classes or {}
	if #funcs == 0 and #classes == 0 then
		return
	end

	-- Build summary
	local parts = {}
	if #funcs > 0 then
		local func_names = {}
		for i, f in ipairs(funcs) do
			if i <= 5 then
				table.insert(func_names, f.name)
			end
		end
		table.insert(parts, "functions: " .. table.concat(func_names, ", "))
		if #funcs > 5 then
			table.insert(parts, "(+" .. (#funcs - 5) .. " more)")
		end
	end
	if #classes > 0 then
		local class_names = {}
		for _, c in ipairs(classes) do
			table.insert(class_names, c.name)
		end
		table.insert(parts, "classes: " .. table.concat(class_names, ", "))
	end

	local filename = vim.fn.fnamemodify(filepath, ":t")
	local summary = filename .. " - " .. table.concat(parts, "; ")

	-- Learn this pattern in brain
	brain.learn({
		type = "pattern",
		file = filepath,
		content = {
			summary = summary,
			detail = #funcs .. " functions, " .. #classes .. " classes",
		},
		context = {
			file = file_index.path or filepath,
			language = file_index.language,
			functions = funcs,
			classes = classes,
			exports = file_index.exports,
			imports = file_index.imports,
		},
	})
end

--- Schedule file indexing with debounce
---@param filepath string
function M.schedule_index_file(filepath)
	if not config.enabled or not config.auto_index then
		return
	end

	-- Check if file should be indexed
	local scanner = require("codetyper.indexer.scanner")
	if not scanner.should_index(filepath, config) then
		return
	end

	-- Cancel existing timer
	if index_timer then
		index_timer:stop()
	end

	-- Schedule new index
	index_timer = vim.defer_fn(function()
		M.index_file(filepath)
		index_timer = nil
	end, INDEX_DEBOUNCE_MS)
end

--- Get relevant context for a prompt
---@param opts {file: string, intent: table|nil, prompt: string, scope: string|nil}
---@return table Context information
function M.get_context_for(opts)
	local memory = require("codetyper.indexer.memory")
	local index = M.load_index()

	local context = {
		project_type = "unknown",
		dependencies = {},
		relevant_files = {},
		relevant_symbols = {},
		patterns = {},
	}

	if not index then
		return context
	end

	context.project_type = index.project_type
	context.dependencies = index.dependencies

	-- Find relevant symbols from prompt
	local words = {}
	for word in opts.prompt:gmatch("%w+") do
		if #word > 2 then
			words[word:lower()] = true
		end
	end

	-- Match symbols
	for symbol, files in pairs(index.symbols) do
		if words[symbol:lower()] then
			context.relevant_symbols[symbol] = files
		end
	end

	-- Get file context if available
	if opts.file then
		local root = utils.get_project_root()
		if root then
			local relative_path = opts.file:gsub("^" .. vim.pesc(root) .. "/", "")
			local file_index = index.files[relative_path]
			if file_index then
				context.current_file = file_index
			end
		end
	end

	-- Get relevant memories
	context.patterns = memory.get_relevant(opts.prompt, 5)

	return context
end

--- Get index status
---@return table Status information
function M.get_status()
	local index = M.load_index()
	if not index then
		return {
			indexed = false,
			stats = nil,
			last_indexed = nil,
		}
	end

	return {
		indexed = true,
		stats = index.stats,
		last_indexed = index.last_indexed,
		project_type = index.project_type,
	}
end

--- Clear the project index
function M.clear()
	local root = utils.get_project_root()
	if root then
		index_cache[root] = nil
	end

	local path = get_index_path()
	if path and utils.file_exists(path) then
		os.remove(path)
	end
end

--- Setup the indexer with configuration
---@param opts? table Configuration options
function M.setup(opts)
	if opts then
		config = vim.tbl_deep_extend("force", config, opts)
	end

	-- Index on startup if configured
	if config.index_on_open then
		vim.defer_fn(function()
			M.index_project()
		end, 1000)
	end
end

--- Get current configuration
---@return table
function M.get_config()
	return vim.deepcopy(config)
end

return M
