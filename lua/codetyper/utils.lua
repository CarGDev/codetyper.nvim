---@mod codetyper.utils Utility functions for Codetyper.nvim

local M = {}

--- Generate a unique ID
---@param prefix? string Prefix for the ID (default: "id")
---@return string Unique ID
function M.generate_id(prefix)
	prefix = prefix or "id"
	return prefix .. "_" .. string.format("%x", os.time()) .. "_" .. string.format("%x", math.random(0, 0xFFFF))
end

--- Get the project root directory
---@return string|nil Root directory path or nil if not found
function M.get_project_root()
  -- Try to find common root indicators
  local markers = { ".git", ".gitignore", "package.json", "Cargo.toml", "go.mod", "pyproject.toml" }

  local current = vim.fn.getcwd()

  for _, marker in ipairs(markers) do
    local found = vim.fn.findfile(marker, current .. ";")
    if found ~= "" then
      return vim.fn.fnamemodify(found, ":p:h")
    end
    found = vim.fn.finddir(marker, current .. ";")
    if found ~= "" then
      -- For directories, :p:h gives the dir itself, so we need :p:h:h to get parent
      return vim.fn.fnamemodify(found, ":p:h:h")
    end
  end

  return current
end

--- Check if current working directory IS a git repository root
--- Only returns true if .git folder exists directly in cwd (not in parent)
---@return boolean
function M.is_git_project()
  local cwd = vim.fn.getcwd()
  local git_path = cwd .. "/.git"
  -- Check if .git exists as a directory or file (for worktrees)
  return vim.fn.isdirectory(git_path) == 1 or vim.fn.filereadable(git_path) == 1
end

--- Get git root directory (only if cwd is a git root)
---@return string|nil Git root or nil if not a git project
function M.get_git_root()
  if M.is_git_project() then
    return vim.fn.getcwd()
  end
  return nil
end

--- Check if a file is a coder file
---@param filepath string File path to check
---@return boolean
function M.is_coder_file(filepath)
  return filepath:match("%.coder%.") ~= nil
end

--- Get the target file path from a coder file path
---@param coder_path string Path to the coder file
---@return string Target file path
function M.get_target_path(coder_path)
  -- Convert index.coder.ts -> index.ts
  return coder_path:gsub("%.coder%.", ".")
end

--- Get the coder file path from a target file path
---@param target_path string Path to the target file
---@return string Coder file path
function M.get_coder_path(target_path)
  -- Convert index.ts -> index.coder.ts
  local dir = vim.fn.fnamemodify(target_path, ":h")
  local name = vim.fn.fnamemodify(target_path, ":t:r")
  local ext = vim.fn.fnamemodify(target_path, ":e")

  if dir == "." then
    return name .. ".coder." .. ext
  end
  return dir .. "/" .. name .. ".coder." .. ext
end

--- Check if a file exists
---@param filepath string File path to check
---@return boolean
function M.file_exists(filepath)
  local stat = vim.loop.fs_stat(filepath)
  return stat ~= nil
end

--- Read file contents
---@param filepath string File path to read
---@return string|nil Contents or nil if error
function M.read_file(filepath)
  local file = io.open(filepath, "r")
  if not file then
    return nil
  end
  local content = file:read("*all")
  file:close()
  return content
end

--- Write content to file
---@param filepath string File path to write
---@param content string Content to write
---@return boolean Success status
function M.write_file(filepath, content)
  local file = io.open(filepath, "w")
  if not file then
    return false
  end
  file:write(content)
  file:close()
  return true
end

--- Create directory if it doesn't exist
---@param dirpath string Directory path
---@return boolean Success status
function M.ensure_dir(dirpath)
  if vim.fn.isdirectory(dirpath) == 0 then
    return vim.fn.mkdir(dirpath, "p") == 1
  end
  return true
end

--- Notify user with proper formatting
---@param msg string Message to display
---@param level? number Vim log level (default: INFO)
function M.notify(msg, level)
  level = level or vim.log.levels.INFO
  vim.notify("[Codetyper] " .. msg, level)
end

--- Get buffer filetype
---@param bufnr? number Buffer number (default: current)
---@return string Filetype
function M.get_filetype(bufnr)
  bufnr = bufnr or 0
  return vim.bo[bufnr].filetype
end

--- Escape pattern special characters
---@param str string String to escape
---@return string Escaped string
function M.escape_pattern(str)
  return str:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
end

--- Get visual selection text
--- Call this BEFORE leaving visual mode or use marks '< and '>
---@return table|nil Selection info {text: string, start_line: number, end_line: number, filepath: string} or nil
function M.get_visual_selection()
  local mode = vim.fn.mode()

  -- Get marks - works in visual mode or after visual selection
  local start_line = vim.fn.line("'<")
  local end_line = vim.fn.line("'>")
  local start_col = vim.fn.col("'<")
  local end_col = vim.fn.col("'>")

  -- If marks are not set (both 0), return nil
  if start_line == 0 and end_line == 0 then
    return nil
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)

  if #lines == 0 then
    return nil
  end

  -- Handle visual line mode - get full lines
  local text
  if mode == "V" or mode == "\22" then -- Visual line or Visual block
    text = table.concat(lines, "\n")
  else
    -- Character-wise visual mode - trim first and last line
    if #lines == 1 then
      text = lines[1]:sub(start_col, end_col)
    else
      lines[1] = lines[1]:sub(start_col)
      lines[#lines] = lines[#lines]:sub(1, end_col)
      text = table.concat(lines, "\n")
    end
  end

  local filepath = vim.fn.expand("%:p")
  local filename = vim.fn.expand("%:t")

  return {
    text = text,
    start_line = start_line,
    end_line = end_line,
    filepath = filepath,
    filename = filename,
    language = vim.bo[bufnr].filetype,
  }
end

--- Check bracket balance for common languages
---@param response string
---@return boolean balanced
function M.check_brackets(response)
	local pairs = {
		["{"] = "}",
		["["] = "]",
		["("] = ")",
	}

	local stack = {}

	for char in response:gmatch(".") do
		if pairs[char] then
			table.insert(stack, pairs[char])
		elseif char == "}" or char == "]" or char == ")" then
			if #stack == 0 or stack[#stack] ~= char then
				return false
			end
			table.remove(stack)
		end
	end

	return #stack == 0
end

--- Simple hash function for content
---@param content string
---@return string
function M.hash_content(content)
	local hash = vim.fn.sha256(content)
	-- If sha256 returns hex string, format %x might be wrong if it expects number?
	-- vim.fn.sha256 returns a hex string already.
	return hash
end

--- Check if a line is empty or a comment

---@param line string
---@param filetype string
---@return boolean
function M.is_empty_or_comment(line, filetype)
	local trimmed = line:match("^%s*(.-)%s*$")
	if trimmed == "" then
		return true
	end

	local ok, languages = pcall(require, "codetyper.params.agent.languages")
	if not ok then return false end

	local patterns = languages.comment_patterns[filetype] or languages.comment_patterns.javascript
	for _, pattern in ipairs(patterns) do
		if trimmed:match(pattern) then
			return true
		end
	end

	return false
end

--- Classify an import as "builtin", "local", or "third_party"
---@param imp string The import statement
---@param filetype string The filetype
---@return string category "builtin"|"local"|"third_party"
function M.classify_import(imp, filetype)
	local is_local = false
	local is_builtin = false

	if filetype == "javascript" or filetype == "typescript" or filetype == "ts" or filetype == "tsx" then
		-- Local: starts with . or ..
		is_local = imp:match("from%s+['\"]%.") or imp:match("require%(['\"]%.")
		-- Node builtin modules
		is_builtin = imp:match("from%s+['\"]node:") or imp:match("from%s+['\"]fs['\"]")
			or imp:match("from%s+['\"]path['\"]") or imp:match("from%s+['\"]http['\"]")
	elseif filetype == "python" or filetype == "py" then
		-- Local: relative imports
		is_local = imp:match("^from%s+%.") or imp:match("^import%s+%.")
		-- Python stdlib (simplified check)
		is_builtin = imp:match("^import%s+os") or imp:match("^import%s+sys")
			or imp:match("^from%s+os%s+") or imp:match("^from%s+sys%s+")
			or imp:match("^import%s+re") or imp:match("^import%s+json")
	elseif filetype == "lua" then
		-- Local: relative requires
		is_local = imp:match("require%(['\"]%.") or imp:match("require%s+['\"]%.")
	elseif filetype == "go" then
		-- Local: project imports (contain /)
		is_local = imp:match("['\"][^'\"]+/[^'\"]+['\"]") and not imp:match("github%.com")
	end

	if is_builtin then
		return "builtin"
	elseif is_local then
		return "local"
	else
		return "third_party"
	end
end

--- Check if a line ends a multi-line import
---@param line string
---@param filetype string
---@return boolean
function M.ends_multiline_import(line, filetype)
	-- Check for closing patterns
	if filetype == "javascript" or filetype == "typescript" or filetype == "ts" or filetype == "tsx" then
		-- ES6 imports end with 'from "..." ;' or just ';' or a line with just '}'
		if line:match("from%s+['\"][^'\"]+['\"]%s*;?%s*$") then
			return true
		end
		if line:match("}%s*from%s+['\"]") then
			return true
		end
		if line:match("^%s*}%s*;?%s*$") then
			return true
		end
		if line:match(";%s*$") then
			return true
		end
	elseif filetype == "python" or filetype == "py" then
		-- Python single-line import: doesn't end with \, (, or ,
		-- Examples: "from typing import List, Dict" or "import os"
		if not line:match("\\%s*$") and not line:match("%(%s*$") and not line:match(",%s*$") then
			return true
		end
		-- Python multiline imports end with closing paren
		if line:match("%)%s*$") then
			return true
		end
	elseif filetype == "go" then
		-- Go multi-line imports end with ')'
		if line:match("%)%s*$") then
			return true
		end
	elseif filetype == "rust" or filetype == "rs" then
		-- Rust use statements end with ';'
		if line:match(";%s*$") then
			return true
		end
	end

	return false
end

return M
