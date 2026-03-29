---@mod codetyper.agent.scope Tree-sitter scope resolution
---@brief [[
--- Resolves semantic scope for prompts using Tree-sitter.
--- Finds the smallest enclosing function/method/block for a given position.
---@brief ]]

local M = {}

---@class ScopeInfo
---@field type string "function"|"method"|"class"|"block"|"file"|"unknown"
---@field node_type string Tree-sitter node type
---@field range {start_row: number, start_col: number, end_row: number, end_col: number}
---@field text string The full text of the scope
---@field name string|nil Name of the function/class if available

--- Node types that represent function-like scopes per language
local params = require("codetyper.params.agents.scope")
local function_nodes = params.function_nodes
local class_nodes = params.class_nodes
local block_nodes = params.block_nodes

--- Check if Tree-sitter is available for buffer
---@param bufnr number
---@return boolean
function M.has_treesitter(bufnr)
  -- Try to get the language for this buffer
  local lang = nil

  -- Method 1: Use vim.treesitter (Neovim 0.9+)
  if vim.treesitter and vim.treesitter.language then
    local ft = vim.bo[bufnr].filetype
    if vim.treesitter.language.get_lang then
      lang = vim.treesitter.language.get_lang(ft)
    else
      lang = ft
    end
  end

  -- Method 2: Try nvim-treesitter parsers module
  if not lang then
    local ok, parsers = pcall(require, "nvim-treesitter.parsers")
    if ok and parsers then
      if parsers.get_buf_lang then
        lang = parsers.get_buf_lang(bufnr)
      elseif parsers.ft_to_lang then
        lang = parsers.ft_to_lang(vim.bo[bufnr].filetype)
      end
    end
  end

  -- Fallback to filetype
  if not lang then
    lang = vim.bo[bufnr].filetype
  end

  if not lang or lang == "" then
    return false
  end

  -- Check if parser is available
  local has_parser = pcall(vim.treesitter.get_parser, bufnr, lang)
  return has_parser
end

--- Get Tree-sitter node at position
---@param bufnr number
---@param row number 0-indexed
---@param col number 0-indexed
---@return TSNode|nil
local function get_node_at_pos(bufnr, row, col)
  -- Use the passed row/col (0-indexed) to find the node at that position,
  -- NOT the current cursor position (which may have moved after prompt window closed)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then
    return nil
  end

  local tree = parser:parse()[1]
  if not tree then
    return nil
  end

  local root = tree:root()
  return root:named_descendant_for_range(row, col, row, col)
end

--- Find enclosing scope node of specific types
---@param node TSNode
---@param node_types table<string, string>
---@return TSNode|nil, string|nil scope_type
local function find_enclosing_scope(node, node_types)
  local flog = require("codetyper.support.flog") -- TODO: remove after debugging
  local current = node
  while current do
    local node_type = current:type()
    if node_types[node_type] then
      flog.debug("scope", "find_enclosing_scope matched: " .. node_type) -- TODO: remove after debugging
      return current, node_types[node_type]
    end
    current = current:parent()
  end
  return nil, nil
end

--- Extract function/method name from node
---@param node TSNode
---@param bufnr number
---@return string|nil
local function get_scope_name(node, bufnr)
  local flog = require("codetyper.support.flog") -- TODO: remove after debugging
  local node_type = node:type()

  -- Log node info for debugging
  local children_types = {}
  for child in node:iter_children() do
    table.insert(children_types, child:type())
  end
  flog.debug("scope", string.format( -- TODO: remove after debugging
    "get_scope_name: node_type=%s children=[%s] parent_type=%s",
    node_type,
    table.concat(children_types, ", "),
    node:parent() and node:parent():type() or "nil"
  ))

  -- Try to find name child node via field
  local ok_field, name_nodes = pcall(node.field, node, "name")
  if ok_field and name_nodes and name_nodes[1] then
    local text = vim.treesitter.get_node_text(name_nodes[1], bufnr)
    flog.debug("scope", "found via field('name'): " .. tostring(text)) -- TODO: remove after debugging
    return text
  end

  -- Try direct children
  for child in node:iter_children() do
    local ct = child:type()
    if ct == "identifier" or ct == "property_identifier" then
      return vim.treesitter.get_node_text(child, bufnr)
    end
    -- Lua: function M.foo() — name is a dot_index_expression
    if ct == "dot_index_expression" or ct == "method_index_expression" then
      return vim.treesitter.get_node_text(child, bufnr)
    end
    -- JS/TS: object.method = function() — name is member_expression
    if ct == "member_expression" then
      return vim.treesitter.get_node_text(child, bufnr)
    end
  end

  -- Walk up: if parent is assignment or function_declaration wrapper
  local parent = node:parent()
  if parent then
    local pt = parent:type()
    flog.debug("scope", "trying parent: " .. pt) -- TODO: remove after debugging

    -- Check if parent has a name field (covers function_declaration with name)
    local ok_pfield, pname_nodes = pcall(parent.field, parent, "name")
    if ok_pfield and pname_nodes and pname_nodes[1] then
      local text = vim.treesitter.get_node_text(pname_nodes[1], bufnr)
      flog.debug("scope", "found via parent field('name'): " .. tostring(text)) -- TODO: remove after debugging
      return text
    end

    -- Try parent's direct identifier/dot_index children
    for child in parent:iter_children() do
      local ct = child:type()
      if ct == "identifier" or ct == "dot_index_expression" or ct == "member_expression" then
        return vim.treesitter.get_node_text(child, bufnr)
      end
    end
  end

  flog.warn("scope", "get_scope_name: no name found for " .. node_type) -- TODO: remove after debugging
  return nil
end

--- Resolve scope at position using Tree-sitter
---@param bufnr number Buffer number
---@param row number 1-indexed line number
---@param col number 1-indexed column number
---@return ScopeInfo
function M.resolve_scope(bufnr, row, col)
  -- Default to file scope
  local default_scope = {
    type = "file",
    node_type = "file",
    range = {
      start_row = 1,
      start_col = 0,
      end_row = vim.api.nvim_buf_line_count(bufnr),
      end_col = 0,
    },
    text = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n"),
    name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t"),
  }

  -- Check if Tree-sitter is available
  if not M.has_treesitter(bufnr) then
    -- Fall back to heuristic-based scope resolution
    return M.resolve_scope_heuristic(bufnr, row, col) or default_scope
  end

  -- Convert to 0-indexed for Tree-sitter
  local ts_row = row - 1
  local ts_col = col - 1

  -- Get node at position
  local node = get_node_at_pos(bufnr, ts_row, ts_col)
  if not node then
    return default_scope
  end

  -- Try to find function scope first
  local scope_node, scope_type = find_enclosing_scope(node, function_nodes)

  -- If no function, try class
  if not scope_node then
    scope_node, scope_type = find_enclosing_scope(node, class_nodes)
  end

  -- If no class, try block
  if not scope_node then
    scope_node, scope_type = find_enclosing_scope(node, block_nodes)
  end

  if not scope_node then
    return default_scope
  end

  -- Get range (convert back to 1-indexed)
  local start_row, start_col, end_row, end_col = scope_node:range()

  -- Get text
  local text = vim.treesitter.get_node_text(scope_node, bufnr)

  -- Get name
  local name = get_scope_name(scope_node, bufnr)

  return {
    type = scope_type,
    node_type = scope_node:type(),
    range = {
      start_row = start_row + 1,
      start_col = start_col,
      end_row = end_row + 1,
      end_col = end_col,
    },
    text = text,
    name = name,
  }
end

--- Heuristic fallback for scope resolution (no Tree-sitter)
---@param bufnr number
---@param row number 1-indexed
---@param col number 1-indexed
---@return ScopeInfo|nil
function M.resolve_scope_heuristic(bufnr, row, col)
  _ = col -- unused in heuristic
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local filetype = vim.bo[bufnr].filetype

  -- Language-specific function patterns
  local patterns = {
    lua = {
      start = "^%s*local%s+function%s+",
      start_alt = "^%s*function%s+",
      ending = "^%s*end%s*$",
    },
    python = {
      start = "^%s*def%s+",
      start_alt = "^%s*async%s+def%s+",
      ending = nil, -- Python uses indentation
    },
    javascript = {
      start = "^%s*export%s+function%s+",
      start_alt = "^%s*function%s+",
      start_alt2 = "^%s*export%s+const%s+%w+%s*=",
      start_alt3 = "^%s*const%s+%w+%s*=%s*",
      start_alt4 = "^%s*export%s+async%s+function%s+",
      start_alt5 = "^%s*async%s+function%s+",
      ending = "^%s*}%s*$",
    },
    typescript = {
      start = "^%s*export%s+function%s+",
      start_alt = "^%s*function%s+",
      start_alt2 = "^%s*export%s+const%s+%w+%s*=",
      start_alt3 = "^%s*const%s+%w+%s*=%s*",
      start_alt4 = "^%s*export%s+async%s+function%s+",
      start_alt5 = "^%s*async%s+function%s+",
      ending = "^%s*}%s*$",
    },
  }

  local lang_patterns = patterns[filetype]
  if not lang_patterns then
    return nil
  end

  -- Find function start (search backwards)
  local start_line = nil
  for i = row, 1, -1 do
    local line = lines[i]
    -- Check all start patterns
    if
      line:match(lang_patterns.start)
      or (lang_patterns.start_alt and line:match(lang_patterns.start_alt))
      or (lang_patterns.start_alt2 and line:match(lang_patterns.start_alt2))
      or (lang_patterns.start_alt3 and line:match(lang_patterns.start_alt3))
      or (lang_patterns.start_alt4 and line:match(lang_patterns.start_alt4))
      or (lang_patterns.start_alt5 and line:match(lang_patterns.start_alt5))
    then
      start_line = i
      break
    end
  end

  if not start_line then
    return nil
  end

  -- Find function end
  local end_line = nil
  if lang_patterns.ending then
    -- Brace/end based languages
    local depth = 0
    for i = start_line, #lines do
      local line = lines[i]
      -- Count braces or end keywords
      if filetype == "lua" then
        if line:match("function") or line:match("if") or line:match("for") or line:match("while") then
          depth = depth + 1
        end
        if line:match("^%s*end") then
          depth = depth - 1
          if depth <= 0 then
            end_line = i
            break
          end
        end
      else
        -- JavaScript/TypeScript brace counting
        for _ in line:gmatch("{") do
          depth = depth + 1
        end
        for _ in line:gmatch("}") do
          depth = depth - 1
        end
        if depth <= 0 and i > start_line then
          end_line = i
          break
        end
      end
    end
  else
    -- Python: use indentation
    local base_indent = #(lines[start_line]:match("^%s*") or "")
    for i = start_line + 1, #lines do
      local line = lines[i]
      if line:match("^%s*$") then
        goto continue
      end
      local indent = #(line:match("^%s*") or "")
      if indent <= base_indent then
        end_line = i - 1
        break
      end
      ::continue::
    end
    end_line = end_line or #lines
  end

  if not end_line then
    end_line = #lines
  end

  -- Extract text
  local scope_lines = {}
  for i = start_line, end_line do
    table.insert(scope_lines, lines[i])
  end

  -- Try to extract function name
  local name = nil
  local first_line = lines[start_line]
  name = first_line:match("function%s+([%w_]+)")
    or first_line:match("def%s+([%w_]+)")
    or first_line:match("const%s+([%w_]+)")

  return {
    type = "function",
    node_type = "heuristic",
    range = {
      start_row = start_line,
      start_col = 0,
      end_row = end_line,
      end_col = #lines[end_line],
    },
    text = table.concat(scope_lines, "\n"),
    name = name,
  }
end

--- Get scope for the current cursor position
---@return ScopeInfo
function M.resolve_scope_at_cursor()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  return M.resolve_scope(bufnr, cursor[1], cursor[2] + 1)
end

--- Check if position is inside a function/method
---@param bufnr number
---@param row number 1-indexed
---@param col number 1-indexed
---@return boolean
function M.is_in_function(bufnr, row, col)
  local scope = M.resolve_scope(bufnr, row, col)
  return scope.type == "function" or scope.type == "method"
end

--- Get all functions in buffer
---@param bufnr number
---@return ScopeInfo[]
function M.get_all_functions(bufnr)
  local functions = {}

  if not M.has_treesitter(bufnr) then
    return functions
  end

  local parser = vim.treesitter.get_parser(bufnr)
  if not parser then
    return functions
  end

  local tree = parser:parse()[1]
  if not tree then
    return functions
  end

  local root = tree:root()

  -- Query for all function nodes
  local lang = parser:lang()
  local query_string = [[
		(function_declaration) @func
		(function_definition) @func
		(method_definition) @func
		(arrow_function) @func
	]]

  local ok, query = pcall(vim.treesitter.query.parse, lang, query_string)
  if not ok then
    return functions
  end

  for _, node in query:iter_captures(root, bufnr, 0, -1) do
    local start_row, start_col, end_row, end_col = node:range()
    local text = vim.treesitter.get_node_text(node, bufnr)
    local name = get_scope_name(node, bufnr)

    table.insert(functions, {
      type = function_nodes[node:type()] or "function",
      node_type = node:type(),
      range = {
        start_row = start_row + 1,
        start_col = start_col,
        end_row = end_row + 1,
        end_col = end_col,
      },
      text = text,
      name = name,
    })
  end

  return functions
end

--- Resolve enclosing context for a selection range.
--- Handles partial selections inside a function, whole function selections,
--- and selections that span across multiple functions.
---@param bufnr number
---@param sel_start number 1-indexed start line of selection
---@param sel_end number 1-indexed end line of selection
---@return table context { type: string, scopes: ScopeInfo[], expanded_start: number, expanded_end: number }
function M.resolve_selection_context(bufnr, sel_start, sel_end)
  local all_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local total_lines = #all_lines

  local scope_start = M.resolve_scope(bufnr, sel_start, 1)
  local scope_end = M.resolve_scope(bufnr, sel_end, 1)

  local selected_lines = sel_end - sel_start + 1

  if selected_lines >= (total_lines * 0.8) then
    return {
      type = "file",
      scopes = {},
      expanded_start = 1,
      expanded_end = total_lines,
    }
  end

  -- Both ends resolve to the same function/method
  if
    scope_start.type ~= "file"
    and scope_end.type ~= "file"
    and scope_start.name == scope_end.name
    and scope_start.range.start_row == scope_end.range.start_row
  then
    local fn_start = scope_start.range.start_row
    local fn_end = scope_start.range.end_row
    local fn_lines = fn_end - fn_start + 1
    local is_whole_fn = selected_lines >= (fn_lines * 0.85)

    if is_whole_fn then
      return {
        type = "whole_function",
        scopes = { scope_start },
        expanded_start = fn_start,
        expanded_end = fn_end,
      }
    else
      return {
        type = "partial_function",
        scopes = { scope_start },
        expanded_start = sel_start,
        expanded_end = sel_end,
      }
    end
  end

  -- Selection spans across multiple functions or one end is file-level
  local affected = {}
  local functions = M.get_all_functions(bufnr)

  if #functions > 0 then
    for _, fn in ipairs(functions) do
      local fn_start = fn.range.start_row
      local fn_end = fn.range.end_row
      if fn_end >= sel_start and fn_start <= sel_end then
        table.insert(affected, fn)
      end
    end
  end

  if #affected > 0 then
    local exp_start = sel_start
    local exp_end = sel_end
    for _, fn in ipairs(affected) do
      exp_start = math.min(exp_start, fn.range.start_row)
      exp_end = math.max(exp_end, fn.range.end_row)
    end
    return {
      type = "multi_function",
      scopes = affected,
      expanded_start = exp_start,
      expanded_end = exp_end,
    }
  end

  -- Indentation-based fallback: walk outward to find the enclosing block
  local base_indent = math.huge
  for i = sel_start, math.min(sel_end, total_lines) do
    local line = all_lines[i]
    if line and not line:match("^%s*$") then
      local indent = #(line:match("^(%s*)") or "")
      base_indent = math.min(base_indent, indent)
    end
  end
  if base_indent == math.huge then
    base_indent = 0
  end

  local block_start = sel_start
  for i = sel_start - 1, 1, -1 do
    local line = all_lines[i]
    if line and not line:match("^%s*$") then
      local indent = #(line:match("^(%s*)") or "")
      if indent < base_indent then
        block_start = i
        break
      end
    end
  end

  local block_end = sel_end
  for i = sel_end + 1, total_lines do
    local line = all_lines[i]
    if line and not line:match("^%s*$") then
      local indent = #(line:match("^(%s*)") or "")
      if indent < base_indent then
        block_end = i
        break
      end
    end
  end

  local block_lines = {}
  for i = block_start, math.min(block_end, total_lines) do
    table.insert(block_lines, all_lines[i])
  end

  return {
    type = "indent_block",
    scopes = {
      {
        type = "block",
        node_type = "indentation",
        range = { start_row = block_start, end_row = block_end },
        text = table.concat(block_lines, "\n"),
        name = nil,
      },
    },
    expanded_start = block_start,
    expanded_end = block_end,
  }
end

return M
