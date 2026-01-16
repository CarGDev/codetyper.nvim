---@mod codetyper.indexer.scanner File scanner for project indexing
---@brief [[
--- Discovers indexable files, detects project type, and parses dependencies.
---@brief ]]

local M = {}

local utils = require("codetyper.support.utils")

--- Project type markers
local PROJECT_MARKERS = {
	node = { "package.json" },
	rust = { "Cargo.toml" },
	go = { "go.mod" },
	python = { "pyproject.toml", "setup.py", "requirements.txt" },
	lua = { "init.lua", ".luarc.json" },
	ruby = { "Gemfile" },
	java = { "pom.xml", "build.gradle" },
	csharp = { "*.csproj", "*.sln" },
}

--- File extension to language mapping
local EXTENSION_LANGUAGE = {
	lua = "lua",
	ts = "typescript",
	tsx = "typescriptreact",
	js = "javascript",
	jsx = "javascriptreact",
	py = "python",
	go = "go",
	rs = "rust",
	rb = "ruby",
	java = "java",
	c = "c",
	cpp = "cpp",
	h = "c",
	hpp = "cpp",
	cs = "csharp",
}

--- Default ignore patterns
local DEFAULT_IGNORES = {
	"^%.", -- Hidden files/folders
	"^node_modules$",
	"^__pycache__$",
	"^%.git$",
	"^%.coder$",
	"^dist$",
	"^build$",
	"^target$",
	"^vendor$",
	"^%.next$",
	"^%.nuxt$",
	"^coverage$",
	"%.min%.js$",
	"%.min%.css$",
	"%.map$",
	"%.lock$",
	"%-lock%.json$",
}

--- Detect project type from root markers
---@param root string Project root path
---@return string Project type
function M.detect_project_type(root)
	for project_type, markers in pairs(PROJECT_MARKERS) do
		for _, marker in ipairs(markers) do
			local path = root .. "/" .. marker
			if marker:match("^%*") then
				-- Glob pattern
				local pattern = marker:gsub("^%*", "")
				local entries = vim.fn.glob(root .. "/*" .. pattern, false, true)
				if #entries > 0 then
					return project_type
				end
			else
				if utils.file_exists(path) then
					return project_type
				end
			end
		end
	end
	return "unknown"
end

--- Parse project dependencies
---@param root string Project root path
---@param project_type string Project type
---@return {dependencies: table<string, string>, dev_dependencies: table<string, string>}
function M.parse_dependencies(root, project_type)
	local deps = {
		dependencies = {},
		dev_dependencies = {},
	}

	if project_type == "node" then
		deps = M.parse_package_json(root)
	elseif project_type == "rust" then
		deps = M.parse_cargo_toml(root)
	elseif project_type == "go" then
		deps = M.parse_go_mod(root)
	elseif project_type == "python" then
		deps = M.parse_python_deps(root)
	end

	return deps
end

--- Parse package.json for Node.js projects
---@param root string Project root path
---@return {dependencies: table, dev_dependencies: table}
function M.parse_package_json(root)
	local path = root .. "/package.json"
	local content = utils.read_file(path)
	if not content then
		return { dependencies = {}, dev_dependencies = {} }
	end

	local ok, pkg = pcall(vim.json.decode, content)
	if not ok or not pkg then
		return { dependencies = {}, dev_dependencies = {} }
	end

	return {
		dependencies = pkg.dependencies or {},
		dev_dependencies = pkg.devDependencies or {},
	}
end

--- Parse Cargo.toml for Rust projects
---@param root string Project root path
---@return {dependencies: table, dev_dependencies: table}
function M.parse_cargo_toml(root)
	local path = root .. "/Cargo.toml"
	local content = utils.read_file(path)
	if not content then
		return { dependencies = {}, dev_dependencies = {} }
	end

	local deps = {}
	local dev_deps = {}
	local in_deps = false
	local in_dev_deps = false

	for line in content:gmatch("[^\n]+") do
		if line:match("^%[dependencies%]") then
			in_deps = true
			in_dev_deps = false
		elseif line:match("^%[dev%-dependencies%]") then
			in_deps = false
			in_dev_deps = true
		elseif line:match("^%[") then
			in_deps = false
			in_dev_deps = false
		elseif in_deps or in_dev_deps then
			local name, version = line:match('^([%w_%-]+)%s*=%s*"([^"]+)"')
			if not name then
				name = line:match("^([%w_%-]+)%s*=")
				version = "workspace"
			end
			if name then
				if in_deps then
					deps[name] = version or "unknown"
				else
					dev_deps[name] = version or "unknown"
				end
			end
		end
	end

	return { dependencies = deps, dev_dependencies = dev_deps }
end

--- Parse go.mod for Go projects
---@param root string Project root path
---@return {dependencies: table, dev_dependencies: table}
function M.parse_go_mod(root)
	local path = root .. "/go.mod"
	local content = utils.read_file(path)
	if not content then
		return { dependencies = {}, dev_dependencies = {} }
	end

	local deps = {}
	local in_require = false

	for line in content:gmatch("[^\n]+") do
		if line:match("^require%s*%(") then
			in_require = true
		elseif line:match("^%)") then
			in_require = false
		elseif in_require then
			local module, version = line:match("^%s*([%w%.%-%_/]+)%s+([%w%.%-]+)")
			if module then
				deps[module] = version
			end
		else
			local module, version = line:match("^require%s+([%w%.%-%_/]+)%s+([%w%.%-]+)")
			if module then
				deps[module] = version
			end
		end
	end

	return { dependencies = deps, dev_dependencies = {} }
end

--- Parse Python dependencies (pyproject.toml or requirements.txt)
---@param root string Project root path
---@return {dependencies: table, dev_dependencies: table}
function M.parse_python_deps(root)
	local deps = {}
	local dev_deps = {}

	-- Try pyproject.toml first
	local pyproject = root .. "/pyproject.toml"
	local content = utils.read_file(pyproject)

	if content then
		-- Simple parsing for dependencies
		local in_deps = false
		local in_dev = false

		for line in content:gmatch("[^\n]+") do
			if line:match("^%[project%.dependencies%]") or line:match("^dependencies%s*=") then
				in_deps = true
				in_dev = false
			elseif line:match("dev") and line:match("dependencies") then
				in_deps = false
				in_dev = true
			elseif line:match("^%[") then
				in_deps = false
				in_dev = false
			elseif in_deps or in_dev then
				local name = line:match('"([%w_%-]+)')
				if name then
					if in_deps then
						deps[name] = "latest"
					else
						dev_deps[name] = "latest"
					end
				end
			end
		end
	end

	-- Fallback to requirements.txt
	local req_file = root .. "/requirements.txt"
	content = utils.read_file(req_file)

	if content then
		for line in content:gmatch("[^\n]+") do
			if not line:match("^#") and not line:match("^%s*$") then
				local name, version = line:match("^([%w_%-]+)==([%d%.]+)")
				if not name then
					name = line:match("^([%w_%-]+)")
					version = "latest"
				end
				if name then
					deps[name] = version or "latest"
				end
			end
		end
	end

	return { dependencies = deps, dev_dependencies = dev_deps }
end

--- Check if a file/directory should be ignored
---@param name string File or directory name
---@param config table Indexer configuration
---@return boolean
function M.should_ignore(name, config)
	-- Check default patterns
	for _, pattern in ipairs(DEFAULT_IGNORES) do
		if name:match(pattern) then
			return true
		end
	end

	-- Check config excluded dirs
	if config and config.excluded_dirs then
		for _, dir in ipairs(config.excluded_dirs) do
			if name == dir then
				return true
			end
		end
	end

	return false
end

--- Check if a file should be indexed
---@param filepath string Full file path
---@param config table Indexer configuration
---@return boolean
function M.should_index(filepath, config)
	local name = vim.fn.fnamemodify(filepath, ":t")
	local ext = vim.fn.fnamemodify(filepath, ":e")

	-- Check if it's a coder file
	if utils.is_coder_file(filepath) then
		return false
	end

	-- Check file size
	if config and config.max_file_size then
		local stat = vim.loop.fs_stat(filepath)
		if stat and stat.size > config.max_file_size then
			return false
		end
	end

	-- Check extension
	if config and config.index_extensions then
		local valid_ext = false
		for _, allowed_ext in ipairs(config.index_extensions) do
			if ext == allowed_ext then
				valid_ext = true
				break
			end
		end
		if not valid_ext then
			return false
		end
	end

	-- Check ignore patterns
	if M.should_ignore(name, config) then
		return false
	end

	return true
end

--- Get all indexable files in the project
---@param root string Project root path
---@param config table Indexer configuration
---@return string[] List of file paths
function M.get_indexable_files(root, config)
	local files = {}

	local function scan_dir(path)
		local handle = vim.loop.fs_scandir(path)
		if not handle then
			return
		end

		while true do
			local name, type = vim.loop.fs_scandir_next(handle)
			if not name then
				break
			end

			local full_path = path .. "/" .. name

			if M.should_ignore(name, config) then
				goto continue
			end

			if type == "directory" then
				scan_dir(full_path)
			elseif type == "file" then
				if M.should_index(full_path, config) then
					table.insert(files, full_path)
				end
			end

			::continue::
		end
	end

	scan_dir(root)
	return files
end

--- Get language from file extension
---@param filepath string File path
---@return string Language name
function M.get_language(filepath)
	local ext = vim.fn.fnamemodify(filepath, ":e")
	return EXTENSION_LANGUAGE[ext] or ext
end

--- Read .gitignore patterns
---@param root string Project root
---@return string[] Patterns
function M.read_gitignore(root)
	local patterns = {}
	local path = root .. "/.gitignore"
	local content = utils.read_file(path)

	if not content then
		return patterns
	end

	for line in content:gmatch("[^\n]+") do
		-- Skip comments and empty lines
		if not line:match("^#") and not line:match("^%s*$") then
			-- Convert gitignore pattern to Lua pattern (simplified)
			local pattern = line:gsub("^/", "^"):gsub("%*%*", ".*"):gsub("%*", "[^/]*"):gsub("%?", ".")
			table.insert(patterns, pattern)
		end
	end

	return patterns
end

return M
