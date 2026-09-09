local flog = require("codetyper.support.flog")
local imports = require("codetyper.core.agent.tools.imports")

local M = {}

local function result(imports_added, body_lines, imports_merged, error)
  return {
    imports_added = imports_added,
    body_lines = body_lines,
    imports_merged = imports_merged,
    error = error,
  }
end

local function replace_range(lines, start_0, end_0, replacement)
  local output = {}
  for index = 1, start_0 do
    table.insert(output, lines[index])
  end
  for _, line in ipairs(replacement) do
    table.insert(output, line)
  end
  for index = end_0 + 1, #lines do
    table.insert(output, lines[index])
  end
  return output
end

local function insert_at(lines, index, replacement)
  local output = vim.deepcopy(lines)
  for offset, line in ipairs(replacement) do
    table.insert(output, index + offset - 1, line)
  end
  return output
end

local function same_lines(left, right)
  if #left ~= #right then
    return false
  end
  for index, line in ipairs(left) do
    if line ~= right[index] then
      return false
    end
  end
  return true
end

local function adjusted_line(line, insertion_positions)
  for _, insertion_at in ipairs(insertion_positions) do
    if insertion_at <= line then
      line = line + 1
    end
  end
  return line
end

--- Inject code with strategy and range (used by patch system)
---@param bufnr number Buffer number
---@param code string Generated code
---@param opts table|nil { strategy = "replace"|"insert"|"append", range = { start_line, end_line } (1-based) }
---@return table { imports_added: number, body_lines: number, imports_merged: boolean }
function M.inject(bufnr, code, opts)
  opts = opts or {}
  local strategy = opts.strategy or "replace"
  local range = opts.range

  -- Guard against nil or non-string code
  if code == nil then
    flog.error("inject", "code is nil, aborting")
    return result(0, 0, false, "code is nil")
  end
  if type(code) ~= "string" then
    flog.error("inject", "code is " .. type(code) .. ", converting to string")
    code = tostring(code)
  end

  -- Empty code means "delete this range" — produce zero replacement lines
  -- instead of a single blank placeholder line (vim.split("", "\n") -> {""}).
  local lines = code == "" and {} or vim.split(code, "\n", { plain = true })

  -- Ensure every element is a string (protect against E5101)
  for i, line in ipairs(lines) do
    if type(line) ~= "string" then
      lines[i] = tostring(line)
    end
  end

  local body_lines = #lines

  if not vim.api.nvim_buf_is_valid(bufnr) then
    flog.error("inject", "buffer " .. tostring(bufnr) .. " is invalid")
    return result(0, 0, false, "buffer is invalid")
  end

  local line_count = vim.api.nvim_buf_line_count(bufnr)

  flog.info(
    "inject",
    string.format(
      "strategy=%s range=%s bufnr=%d line_count=%d code_lines=%d",
      strategy,
      range and (range.start_line .. "-" .. (range.end_line or "nil")) or "nil",
      bufnr,
      line_count,
      body_lines
    )
  )
  flog.debug("inject", "code_preview: " .. code:sub(1, 200):gsub("\n", "\\n")) -- TODO: remove after debugging

  local target_path = vim.api.nvim_buf_get_name(bufnr)
  local extraction, extraction_error = imports.extract(code, {
    path = target_path,
    filetype = vim.bo[bufnr].filetype,
  })
  if not extraction then
    flog.error("inject", extraction_error)
    return result(0, 0, false, extraction_error)
  end

  local source_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local planned_lines = source_lines
  local imports_added = 0
  local insertion_positions = {}
  for _, statement in ipairs(extraction.statements) do
    local plan, plan_error = imports.plan({
      root = opts.root,
      bufnr = bufnr,
      filetype = vim.bo[bufnr].filetype,
      statement = statement,
      lines = planned_lines,
      target_kind = "memory",
    })
    if not plan then
      flog.error("inject", plan_error)
      return result(0, 0, false, plan_error)
    end
    planned_lines = plan.lines
    if plan.imports_added > 0 then
      imports_added = imports_added + plan.imports_added
      table.insert(insertion_positions, plan.insert_at)
    end
  end

  local extracted_body_lines = extraction.body_lines
  local has_extracted_imports = #extraction.statements > 0
  if has_extracted_imports then
    body_lines = #extracted_body_lines
    if body_lines > 0 then
      local adjusted_range = range
      if range and range.start_line then
        adjusted_range = {
          start_line = adjusted_line(range.start_line, insertion_positions),
          end_line = range.end_line and adjusted_line(range.end_line, insertion_positions) or nil,
        }
      end
      if strategy == "replace" and adjusted_range and adjusted_range.start_line and adjusted_range.end_line then
        local start_0 = math.max(0, adjusted_range.start_line - 1)
        local end_0 = math.min(#planned_lines, adjusted_range.end_line)
        if end_0 < start_0 then
          end_0 = start_0
        end
        planned_lines = replace_range(planned_lines, start_0, end_0, extracted_body_lines)
      elseif strategy == "insert" and adjusted_range and adjusted_range.start_line then
        local at_0 = math.max(0, math.min(adjusted_range.start_line - 1, #planned_lines))
        planned_lines = insert_at(planned_lines, at_0 + 1, extracted_body_lines)
      else
        planned_lines = insert_at(planned_lines, #planned_lines + 1, extracted_body_lines)
      end
    end

    if not vim.bo[bufnr].modifiable then
      return result(0, 0, false, "buffer is not modifiable")
    end
    if not same_lines(source_lines, planned_lines) then
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, planned_lines)
    end
    return result(imports_added, body_lines, imports_added > 0, nil)
  end

  if strategy == "replace" and range and range.start_line and range.end_line then
    local start_0 = math.max(0, range.start_line - 1)
    local end_0 = math.min(line_count, range.end_line)
    if end_0 < start_0 then
      end_0 = start_0
    end
    flog.info("inject", string.format("replace: buf_set_lines(%d, %d, %d)", bufnr, start_0, end_0))
    vim.api.nvim_buf_set_lines(bufnr, start_0, end_0, false, lines)
  elseif strategy == "insert" and range and range.start_line then
    local at_0 = math.max(0, math.min(range.start_line - 1, line_count))
    flog.info("inject", string.format("insert: buf_set_lines(%d, %d, %d)", bufnr, at_0, at_0))
    vim.api.nvim_buf_set_lines(bufnr, at_0, at_0, false, lines)
  else
    flog.info("inject", string.format("append: buf_set_lines(%d, %d, %d)", bufnr, line_count, line_count))
    vim.api.nvim_buf_set_lines(bufnr, line_count, line_count, false, lines)
  end

  return result(0, body_lines, false, nil)
end

return M
