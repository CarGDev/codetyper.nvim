--- Resolve file dependencies: what this file imports and who imports this file
local M = {}

--- Extract require/import statements from file content
---@param content string File content
---@param language string File language/extension
---@return string[] List of module paths this file imports
local function extract_imports(content, language)
  local imports = {}
  local seen = {}

  -- Lua: require("module") or require "module"
  for mod in content:gmatch('require%s*%(?%s*["\']([^"\']+)["\']') do
    if not seen[mod] then
      seen[mod] = true
      imports[#imports + 1] = mod
    end
  end

  -- JS/TS: import ... from "module" or require("module")
  if language == "javascript" or language == "typescript"
    or language == "tsx" or language == "jsx"
    or language == "js" or language == "ts" then
    for mod in content:gmatch('from%s+["\']([^"\']+)["\']') do
      if not seen[mod] then
        seen[mod] = true
        imports[#imports + 1] = mod
      end
    end
  end

  -- Python: import X or from X import Y
  if language == "python" or language == "py" then
    for mod in content:gmatch('import%s+([%w%.]+)') do
      if not seen[mod] then
        seen[mod] = true
        imports[#imports + 1] = mod
      end
    end
    for mod in content:gmatch('from%s+([%w%.]+)%s+import') do
      if not seen[mod] then
        seen[mod] = true
        imports[#imports + 1] = mod
      end
    end
  end

  -- Go: import "path" or "path"
  if language == "go" then
    for mod in content:gmatch('"([%w%./%-]+)"') do
      if mod:find("/") and not seen[mod] then
        seen[mod] = true
        imports[#imports + 1] = mod
      end
    end
  end

  return imports
end

--- Convert a file path to its likely require module name
--- e.g. lua/codetyper/core/transform.lua -> codetyper.core.transform
---@param filepath string
---@return string[] Possible module names to grep for
local function filepath_to_module_names(filepath)
  local names = {}

  -- Get relative path from cwd
  local cwd = vim.fn.getcwd()
  local rel = filepath
  if filepath:sub(1, #cwd) == cwd then
    rel = filepath:sub(#cwd + 2)
  end

  -- Strip leading lua/ for Lua modules
  local lua_path = rel:gsub("^lua/", "")
  -- Strip extension
  local no_ext = lua_path:gsub("%.[^%.]+$", "")
  -- Strip /init suffix
  local no_init = no_ext:gsub("/init$", "")

  -- Lua dot-notation: codetyper.core.transform
  local dot_name = no_ext:gsub("/", ".")
  names[#names + 1] = dot_name
  if no_init ~= no_ext then
    names[#names + 1] = no_init:gsub("/", ".")
  end

  -- Also add the relative path for JS/TS/Python style imports
  names[#names + 1] = no_ext
  -- Basename for simple imports
  local basename = vim.fn.fnamemodify(rel, ":t:r")
  names[#names + 1] = basename

  return names
end

--- Find files in the project that import/require a given file
---@param filepath string Absolute path to the file
---@return table[] List of {file, line, match} tables
function M.find_importers(filepath)
  local module_names = filepath_to_module_names(filepath)
  local results = {}
  local seen_files = {}
  local cwd = vim.fn.getcwd()

  for _, mod_name in ipairs(module_names) do
    -- Escape dots for grep pattern
    local pattern = mod_name:gsub("%.", "%%.")
    -- Use vim.fn.systemlist for a fast grep
    local cmd = string.format(
      "grep -rn --include='*.lua' --include='*.ts' --include='*.tsx' "
      .. "--include='*.js' --include='*.jsx' --include='*.py' --include='*.go' "
      .. "--include='*.rs' --include='*.rb' "
      .. "-e %s %s 2>/dev/null | head -50",
      vim.fn.shellescape(mod_name),
      vim.fn.shellescape(cwd)
    )
    local grep_results = vim.fn.systemlist(cmd)

    for _, line in ipairs(grep_results) do
      local file, lnum, match = line:match("^(.+):(%d+):(.+)$")
      if file and file ~= filepath and not seen_files[file .. ":" .. (lnum or "")] then
        seen_files[file .. ":" .. (lnum or "")] = true
        -- Make path relative
        local rel_file = file
        if file:sub(1, #cwd) == cwd then
          rel_file = file:sub(#cwd + 2)
        end
        results[#results + 1] = {
          file = rel_file,
          line = tonumber(lnum),
          match = (match or ""):gsub("^%s+", ""),
        }
      end
    end
  end

  return results
end

--- Resolve full dependency context for a file
---@param filepath string Absolute path to the file
---@param content string|nil File content (if already available)
---@param language string File language
---@return table { imports: string[], importers: table[], filepath: string }
function M.resolve(filepath, content, language)
  if not content then
    local f = io.open(filepath, "r")
    if f then
      content = f:read("*a")
      f:close()
    else
      content = ""
    end
  end

  local imports = extract_imports(content, language)
  local importers = M.find_importers(filepath)

  return {
    filepath = filepath,
    imports = imports,
    importers = importers,
  }
end

--- Format dependency info as a context block for the LLM prompt
---@param deps table Output from resolve()
---@return string Formatted markdown context
function M.format_context(deps)
  local parts = {}

  local cwd = vim.fn.getcwd()
  local rel = deps.filepath
  if deps.filepath:sub(1, #cwd) == cwd then
    rel = deps.filepath:sub(#cwd + 2)
  end

  table.insert(parts, "**File dependency context for `" .. rel .. "`:**")
  table.insert(parts, "")

  -- What this file imports
  if #deps.imports > 0 then
    table.insert(parts, "**This file imports:**")
    for _, mod in ipairs(deps.imports) do
      table.insert(parts, "- `" .. mod .. "`")
    end
    table.insert(parts, "")
  end

  -- Who imports this file
  if #deps.importers > 0 then
    table.insert(parts, "**Files that import/require this file:**")
    for _, imp in ipairs(deps.importers) do
      table.insert(parts, string.format("- `%s` (line %d): `%s`", imp.file, imp.line, imp.match))
    end
    table.insert(parts, "")
  else
    table.insert(parts, "**No files found that import this file in the project.**")
    table.insert(parts, "")
  end

  return table.concat(parts, "\n")
end

return M
