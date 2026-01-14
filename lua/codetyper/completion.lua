---@mod codetyper.completion Insert mode completion for file references
---
--- Provides completion for @filename inside /@ @/ tags.

local M = {}

local parser = require("codetyper.parser")
local utils = require("codetyper.utils")

--- Get list of files for completion
---@param prefix string Prefix to filter files
---@return table[] List of completion items
local function get_file_completions(prefix)
  local cwd = vim.fn.getcwd()
  local files = {}

  -- Use vim.fn.glob to find files matching the prefix
  local pattern = prefix .. "*"

  -- Search in current directory
  local matches = vim.fn.glob(cwd .. "/" .. pattern, false, true)

  -- Search with ** for all subdirectories
  local deep_matches = vim.fn.glob(cwd .. "/**/" .. pattern, false, true)
  for _, m in ipairs(deep_matches) do
    table.insert(matches, m)
  end

  -- Also search specific directories if prefix doesn't have path
  if not prefix:find("/") then
    local search_dirs = { "src", "lib", "lua", "app", "components", "utils", "tests" }
    for _, dir in ipairs(search_dirs) do
      local dir_path = cwd .. "/" .. dir
      if vim.fn.isdirectory(dir_path) == 1 then
        local dir_matches = vim.fn.glob(dir_path .. "/**/" .. pattern, false, true)
        for _, m in ipairs(dir_matches) do
          table.insert(matches, m)
        end
      end
    end
  end

  -- Convert to relative paths and deduplicate
  local seen = {}
  for _, match in ipairs(matches) do
    local rel_path = match:sub(#cwd + 2) -- Remove cwd/ prefix
    -- Skip directories, coder files, and hidden/generated files
    if vim.fn.isdirectory(match) == 0
      and not utils.is_coder_file(match)
      and not rel_path:match("^%.")
      and not rel_path:match("node_modules")
      and not rel_path:match("%.git/")
      and not rel_path:match("dist/")
      and not rel_path:match("build/")
      and not seen[rel_path]
    then
      seen[rel_path] = true
      table.insert(files, {
        word = rel_path,
        abbr = rel_path,
        kind = "File",
        menu = "[ref]",
      })
    end
  end

  -- Sort by length (shorter paths first)
  table.sort(files, function(a, b)
    return #a.word < #b.word
  end)

  -- Limit results
  local result = {}
  for i = 1, math.min(#files, 15) do
    result[i] = files[i]
  end

  return result
end

--- Show file completion popup
function M.show_file_completion()
  -- Check if we're in an open prompt tag
  local is_inside = parser.is_cursor_in_open_tag()
  if not is_inside then
    return false
  end

  -- Get the prefix being typed
  local prefix = parser.get_file_ref_prefix()
  if prefix == nil then
    return false
  end

  -- Get completions
  local items = get_file_completions(prefix)

  if #items == 0 then
    -- Try with empty prefix to show all files
    items = get_file_completions("")
  end

  if #items > 0 then
    -- Calculate start column (position right after @)
    local cursor = vim.api.nvim_win_get_cursor(0)
    local col = cursor[2] - #prefix + 1  -- 1-indexed for complete()

    -- Show completion popup
    vim.fn.complete(col, items)
    return true
  end

  return false
end

--- Setup completion for file references (works on ALL files)
function M.setup()
  local group = vim.api.nvim_create_augroup("CoderCompletion", { clear = true })

  -- Trigger completion on @ in insert mode (works on ALL files)
  vim.api.nvim_create_autocmd("InsertCharPre", {
    group = group,
    pattern = "*",
    callback = function()
      -- Skip special buffers
      if vim.bo.buftype ~= "" then
        return
      end

      if vim.v.char == "@" then
        -- Schedule completion popup after the @ is inserted
        vim.schedule(function()
          -- Check we're in an open tag
          local is_inside = parser.is_cursor_in_open_tag()
          if not is_inside then
            return
          end

          -- Check we're not typing @/ (closing tag)
          local cursor = vim.api.nvim_win_get_cursor(0)
          local line = vim.api.nvim_get_current_line()
          local next_char = line:sub(cursor[2] + 2, cursor[2] + 2)

          if next_char == "/" then
            return
          end

          -- Show file completion
          M.show_file_completion()
        end)
      end
    end,
    desc = "Trigger file completion on @ inside prompt tags",
  })

  -- Also allow manual trigger with <C-x><C-f> style keybinding in insert mode
  vim.keymap.set("i", "<C-x>@", function()
    M.show_file_completion()
  end, { silent = true, desc = "Coder: Complete file reference" })
end

return M
