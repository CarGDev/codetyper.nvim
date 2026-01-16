---@mod codetyper.ask.explorer Project exploration for Ask mode
---@brief [[
--- Performs comprehensive project exploration when explaining a project.
--- Shows progress, indexes files, and builds brain context.
---@brief ]]

local M = {}

local utils = require("codetyper.support.utils")

---@class ExplorationState
---@field is_exploring boolean
---@field files_scanned number
---@field total_files number
---@field current_file string|nil
---@field findings table
---@field on_log fun(msg: string, level: string)|nil

local state = {
	is_exploring = false,
	files_scanned = 0,
	total_files = 0,
	current_file = nil,
	findings = {},
	on_log = nil,
}

--- File extensions to analyze
local ANALYZABLE_EXTENSIONS = {
	lua = true,
	ts = true,
	tsx = true,
	js = true,
	jsx = true,
	py = true,
	go = true,
	rs = true,
	rb = true,
	java = true,
	c = true,
	cpp = true,
	h = true,
	hpp = true,
	json = true,
	yaml = true,
	yml = true,
	toml = true,
	md = true,
	xml = true,
}

--- Directories to skip
local SKIP_DIRS = {
	-- Version control
	[".git"] = true,
	[".svn"] = true,
	[".hg"] = true,

	-- IDE/Editor
	[".idea"] = true,
	[".vscode"] = true,
	[".cursor"] = true,
	[".cursorignore"] = true,
	[".claude"] = true,
	[".zed"] = true,

	-- Project tooling
	[".coder"] = true,
	[".github"] = true,
	[".gitlab"] = true,
	[".husky"] = true,

	-- Build outputs
	dist = true,
	build = true,
	out = true,
	target = true,
	bin = true,
	obj = true,
	[".build"] = true,
	[".output"] = true,

	-- Dependencies
	node_modules = true,
	vendor = true,
	[".vendor"] = true,
	packages = true,
	bower_components = true,
	jspm_packages = true,

	-- Cache/temp
	[".cache"] = true,
	[".tmp"] = true,
	[".temp"] = true,
	__pycache__ = true,
	[".pytest_cache"] = true,
	[".mypy_cache"] = true,
	[".ruff_cache"] = true,
	[".tox"] = true,
	[".nox"] = true,
	[".eggs"] = true,
	["*.egg-info"] = true,

	-- Framework specific
	[".next"] = true,
	[".nuxt"] = true,
	[".svelte-kit"] = true,
	[".vercel"] = true,
	[".netlify"] = true,
	[".serverless"] = true,
	[".turbo"] = true,

	-- Testing/coverage
	coverage = true,
	[".nyc_output"] = true,
	htmlcov = true,

	-- Logs
	logs = true,
	log = true,

	-- OS files
	[".DS_Store"] = true,
	Thumbs_db = true,
}

--- Files to skip (patterns)
local SKIP_FILES = {
	-- Lock files
	"package%-lock%.json",
	"yarn%.lock",
	"pnpm%-lock%.yaml",
	"Gemfile%.lock",
	"Cargo%.lock",
	"poetry%.lock",
	"Pipfile%.lock",
	"composer%.lock",
	"go%.sum",
	"flake%.lock",
	"%.lock$",
	"%-lock%.json$",
	"%-lock%.yaml$",

	-- Generated files
	"%.min%.js$",
	"%.min%.css$",
	"%.bundle%.js$",
	"%.chunk%.js$",
	"%.map$",
	"%.d%.ts$",

	-- Binary/media (shouldn't match anyway but be safe)
	"%.png$",
	"%.jpg$",
	"%.jpeg$",
	"%.gif$",
	"%.ico$",
	"%.svg$",
	"%.woff",
	"%.ttf$",
	"%.eot$",
	"%.pdf$",
	"%.zip$",
	"%.tar",
	"%.gz$",

	-- Config that's not useful
	"%.env",
	"%.env%.",
}

--- Log a message during exploration
---@param msg string
---@param level? string "info"|"debug"|"file"|"progress"
local function log(msg, level)
	level = level or "info"
	if state.on_log then
		state.on_log(msg, level)
	end
end

--- Check if file should be skipped
---@param filename string
---@return boolean
local function should_skip_file(filename)
	for _, pattern in ipairs(SKIP_FILES) do
		if filename:match(pattern) then
			return true
		end
	end
	return false
end

--- Check if directory should be skipped
---@param dirname string
---@return boolean
local function should_skip_dir(dirname)
	-- Direct match
	if SKIP_DIRS[dirname] then
		return true
	end
	-- Pattern match for .cursor* etc
	if dirname:match("^%.cursor") then
		return true
	end
	return false
end

--- Get all files in project
---@param root string Project root
---@return string[] files
local function get_project_files(root)
	local files = {}

	local function scan_dir(dir)
		local handle = vim.loop.fs_scandir(dir)
		if not handle then
			return
		end

		while true do
			local name, type = vim.loop.fs_scandir_next(handle)
			if not name then
				break
			end

			local full_path = dir .. "/" .. name

			if type == "directory" then
				if not should_skip_dir(name) then
					scan_dir(full_path)
				end
			elseif type == "file" then
				if not should_skip_file(name) then
					local ext = name:match("%.([^%.]+)$")
					if ext and ANALYZABLE_EXTENSIONS[ext:lower()] then
						table.insert(files, full_path)
					end
				end
			end
		end
	end

	scan_dir(root)
	return files
end

--- Analyze a single file
---@param filepath string
---@return table|nil analysis
local function analyze_file(filepath)
	local content = utils.read_file(filepath)
	if not content or content == "" then
		return nil
	end

	local ext = filepath:match("%.([^%.]+)$") or ""
	local lines = vim.split(content, "\n")

	local analysis = {
		path = filepath,
		extension = ext,
		lines = #lines,
		size = #content,
		imports = {},
		exports = {},
		functions = {},
		classes = {},
		summary = "",
	}

	-- Extract key patterns based on file type
	for i, line in ipairs(lines) do
		-- Imports/requires
		local import = line:match('import%s+.*%s+from%s+["\']([^"\']+)["\']')
			or line:match('require%(["\']([^"\']+)["\']%)')
			or line:match("from%s+([%w_.]+)%s+import")
		if import then
			table.insert(analysis.imports, { source = import, line = i })
		end

		-- Function definitions
		local func = line:match("^%s*function%s+([%w_:%.]+)%s*%(")
			or line:match("^%s*local%s+function%s+([%w_]+)%s*%(")
			or line:match("^%s*def%s+([%w_]+)%s*%(")
			or line:match("^%s*func%s+([%w_]+)%s*%(")
			or line:match("^%s*async%s+function%s+([%w_]+)%s*%(")
			or line:match("^%s*public%s+.*%s+([%w_]+)%s*%(")
		if func then
			table.insert(analysis.functions, { name = func, line = i })
		end

		-- Class definitions
		local class = line:match("^%s*class%s+([%w_]+)")
			or line:match("^%s*public%s+class%s+([%w_]+)")
			or line:match("^%s*interface%s+([%w_]+)")
		if class then
			table.insert(analysis.classes, { name = class, line = i })
		end

		-- Exports
		local exp = line:match("^%s*export%s+.*%s+([%w_]+)")
			or line:match("^%s*module%.exports%s*=")
			or line:match("^return%s+M")
		if exp then
			table.insert(analysis.exports, { name = exp, line = i })
		end
	end

	-- Create summary
	local parts = {}
	if #analysis.functions > 0 then
		table.insert(parts, #analysis.functions .. " functions")
	end
	if #analysis.classes > 0 then
		table.insert(parts, #analysis.classes .. " classes")
	end
	if #analysis.imports > 0 then
		table.insert(parts, #analysis.imports .. " imports")
	end
	analysis.summary = table.concat(parts, ", ")

	return analysis
end

--- Detect project type from files
---@param root string
---@return string type, table info
local function detect_project_type(root)
	local info = {
		name = vim.fn.fnamemodify(root, ":t"),
		type = "unknown",
		framework = nil,
		language = nil,
	}

	-- Check for common project files
	if utils.file_exists(root .. "/package.json") then
		info.type = "node"
		info.language = "JavaScript/TypeScript"
		local content = utils.read_file(root .. "/package.json")
		if content then
			local ok, pkg = pcall(vim.json.decode, content)
			if ok then
				info.name = pkg.name or info.name
				if pkg.dependencies then
					if pkg.dependencies.react then
						info.framework = "React"
					elseif pkg.dependencies.vue then
						info.framework = "Vue"
					elseif pkg.dependencies.next then
						info.framework = "Next.js"
					elseif pkg.dependencies.express then
						info.framework = "Express"
					end
				end
			end
		end
	elseif utils.file_exists(root .. "/pom.xml") then
		info.type = "maven"
		info.language = "Java"
		local content = utils.read_file(root .. "/pom.xml")
		if content and content:match("spring%-boot") then
			info.framework = "Spring Boot"
		end
	elseif utils.file_exists(root .. "/Cargo.toml") then
		info.type = "rust"
		info.language = "Rust"
	elseif utils.file_exists(root .. "/go.mod") then
		info.type = "go"
		info.language = "Go"
	elseif utils.file_exists(root .. "/requirements.txt") or utils.file_exists(root .. "/pyproject.toml") then
		info.type = "python"
		info.language = "Python"
	elseif utils.file_exists(root .. "/init.lua") or utils.file_exists(root .. "/plugin/") then
		info.type = "neovim-plugin"
		info.language = "Lua"
	end

	return info.type, info
end

--- Build project structure summary
---@param files string[]
---@param root string
---@return table structure
local function build_structure(files, root)
	local structure = {
		directories = {},
		by_extension = {},
		total_files = #files,
	}

	for _, file in ipairs(files) do
		local relative = file:gsub("^" .. vim.pesc(root) .. "/", "")
		local dir = vim.fn.fnamemodify(relative, ":h")
		local ext = file:match("%.([^%.]+)$") or "unknown"

		structure.directories[dir] = (structure.directories[dir] or 0) + 1
		structure.by_extension[ext] = (structure.by_extension[ext] or 0) + 1
	end

	return structure
end

--- Explore project and build context
---@param root string Project root
---@param on_log fun(msg: string, level: string) Log callback
---@param on_complete fun(result: table) Completion callback
function M.explore(root, on_log, on_complete)
	if state.is_exploring then
		on_log("⚠️  Already exploring...", "warning")
		return
	end

	state.is_exploring = true
	state.on_log = on_log
	state.findings = {}

	-- Start exploration
	log("⏺ Exploring project structure...", "info")
	log("", "info")

	-- Detect project type
	log("  Detect(Project type)", "progress")
	local project_type, project_info = detect_project_type(root)
	log("  ⎿  " .. project_info.language .. " (" .. (project_info.framework or project_type) .. ")", "debug")

	state.findings.project = project_info

	-- Get all files
	log("", "info")
	log("  Scan(Project files)", "progress")
	local files = get_project_files(root)
	state.total_files = #files
	log("  ⎿  Found " .. #files .. " analyzable files", "debug")

	-- Build structure
	local structure = build_structure(files, root)
	state.findings.structure = structure

	-- Show directory breakdown
	log("", "info")
	log("  Structure(Directories)", "progress")
	local sorted_dirs = {}
	for dir, count in pairs(structure.directories) do
		table.insert(sorted_dirs, { dir = dir, count = count })
	end
	table.sort(sorted_dirs, function(a, b)
		return a.count > b.count
	end)
	for i, entry in ipairs(sorted_dirs) do
		if i <= 5 then
			log("  ⎿  " .. entry.dir .. " (" .. entry.count .. " files)", "debug")
		end
	end
	if #sorted_dirs > 5 then
		log("  ⎿  +" .. (#sorted_dirs - 5) .. " more directories", "debug")
	end

	-- Analyze files asynchronously
	log("", "info")
	log("  Analyze(Source files)", "progress")

	state.files_scanned = 0
	local analyses = {}
	local key_files = {}

	-- Process files in batches to avoid blocking
	local batch_size = 10
	local current_batch = 0

	local function process_batch()
		local start_idx = current_batch * batch_size + 1
		local end_idx = math.min(start_idx + batch_size - 1, #files)

		for i = start_idx, end_idx do
			local file = files[i]
			local relative = file:gsub("^" .. vim.pesc(root) .. "/", "")

			state.files_scanned = state.files_scanned + 1
			state.current_file = relative

			local analysis = analyze_file(file)
			if analysis then
				analysis.relative_path = relative
				table.insert(analyses, analysis)

				-- Track key files (many functions/classes)
				if #analysis.functions >= 3 or #analysis.classes >= 1 then
					table.insert(key_files, {
						path = relative,
						functions = #analysis.functions,
						classes = #analysis.classes,
						summary = analysis.summary,
					})
				end
			end

			-- Log some files
			if i <= 3 or (i % 20 == 0) then
				log("  ⎿  " .. relative .. ": " .. (analysis and analysis.summary or "(empty)"), "file")
			end
		end

		-- Progress update
		local progress = math.floor((state.files_scanned / state.total_files) * 100)
		if progress % 25 == 0 and progress > 0 then
			log("  ⎿  " .. progress .. "% complete (" .. state.files_scanned .. "/" .. state.total_files .. ")", "debug")
		end

		current_batch = current_batch + 1

		if end_idx < #files then
			-- Schedule next batch
			vim.defer_fn(process_batch, 10)
		else
			-- Complete
			finish_exploration(root, analyses, key_files, on_complete)
		end
	end

	-- Start processing
	vim.defer_fn(process_batch, 10)
end

--- Finish exploration and store results
---@param root string
---@param analyses table
---@param key_files table
---@param on_complete fun(result: table)
function finish_exploration(root, analyses, key_files, on_complete)
	log("  ⎿  +" .. (#analyses - 3) .. " more files analyzed", "debug")

	-- Show key files
	if #key_files > 0 then
		log("", "info")
		log("  KeyFiles(Important components)", "progress")
		table.sort(key_files, function(a, b)
			return (a.functions + a.classes * 2) > (b.functions + b.classes * 2)
		end)
		for i, kf in ipairs(key_files) do
			if i <= 5 then
				log("  ⎿  " .. kf.path .. ": " .. kf.summary, "file")
			end
		end
		if #key_files > 5 then
			log("  ⎿  +" .. (#key_files - 5) .. " more key files", "debug")
		end
	end

	state.findings.analyses = analyses
	state.findings.key_files = key_files

	-- Store in brain if available
	local ok_brain, brain = pcall(require, "codetyper.brain")
	if ok_brain and brain.is_initialized() then
		log("", "info")
		log("  Store(Brain context)", "progress")

		-- Store project pattern
		brain.learn({
			type = "pattern",
			file = root,
			content = {
				summary = "Project: " .. state.findings.project.name,
				detail = state.findings.project.language
					.. " "
					.. (state.findings.project.framework or state.findings.project.type),
				code = nil,
			},
			context = {
				file = root,
				language = state.findings.project.language,
			},
		})

		-- Store key file patterns
		for i, kf in ipairs(key_files) do
			if i <= 10 then
				brain.learn({
					type = "pattern",
					file = root .. "/" .. kf.path,
					content = {
						summary = kf.path .. " - " .. kf.summary,
						detail = kf.summary,
					},
					context = {
						file = kf.path,
					},
				})
			end
		end

		log("  ⎿  Stored " .. math.min(#key_files, 10) + 1 .. " patterns in brain", "debug")
	end

	-- Store in indexer if available
	local ok_indexer, indexer = pcall(require, "codetyper.indexer")
	if ok_indexer then
		log("  Index(Project index)", "progress")
		indexer.index_project(function(index)
			log("  ⎿  Indexed " .. (index.stats.files or 0) .. " files", "debug")
		end)
	end

	log("", "info")
	log("✓ Exploration complete!", "info")
	log("", "info")

	-- Build result
	local result = {
		project = state.findings.project,
		structure = state.findings.structure,
		key_files = key_files,
		total_files = state.total_files,
		analyses = analyses,
	}

	state.is_exploring = false
	state.on_log = nil

	on_complete(result)
end

--- Check if exploration is in progress
---@return boolean
function M.is_exploring()
	return state.is_exploring
end

--- Get exploration progress
---@return number scanned, number total
function M.get_progress()
	return state.files_scanned, state.total_files
end

--- Build context string from exploration result
---@param result table Exploration result
---@return string context
function M.build_context(result)
	local parts = {}

	-- Project info
	table.insert(parts, "## Project: " .. result.project.name)
	table.insert(parts, "- Type: " .. result.project.type)
	table.insert(parts, "- Language: " .. (result.project.language or "Unknown"))
	if result.project.framework then
		table.insert(parts, "- Framework: " .. result.project.framework)
	end
	table.insert(parts, "- Files: " .. result.total_files)
	table.insert(parts, "")

	-- Structure
	table.insert(parts, "## Structure")
	if result.structure and result.structure.by_extension then
		for ext, count in pairs(result.structure.by_extension) do
			table.insert(parts, "- ." .. ext .. ": " .. count .. " files")
		end
	end
	table.insert(parts, "")

	-- Key components
	if result.key_files and #result.key_files > 0 then
		table.insert(parts, "## Key Components")
		for i, kf in ipairs(result.key_files) do
			if i <= 10 then
				table.insert(parts, "- " .. kf.path .. ": " .. kf.summary)
			end
		end
	end

	return table.concat(parts, "\n")
end

return M
