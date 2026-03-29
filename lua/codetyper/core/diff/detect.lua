local M = {}

--- Parse lines and find all conflict regions
---@param lines string[] Buffer lines
---@return table[] conflicts List of conflict positions
function M.detect_conflicts(lines)
  local conflicts = {}
  local current_conflict = nil

  for i, line in ipairs(lines) do
    if line:match("^<<<<<<<") then
      current_conflict = {
        start_line = i,
        current_start = i,
        current_end = nil,
        separator = nil,
        incoming_start = nil,
        incoming_end = nil,
        end_line = nil,
      }
    elseif line:match("^=======") and current_conflict then
      current_conflict.current_end = i - 1
      current_conflict.separator = i
      current_conflict.incoming_start = i + 1
    elseif line:match("^>>>>>>>") and current_conflict then
      current_conflict.incoming_end = i - 1
      current_conflict.end_line = i
      table.insert(conflicts, current_conflict)
      current_conflict = nil
    end
  end

  return conflicts
end

--- Get the conflict at a given cursor position
---@param conflicts table[] List of conflict positions
---@param cursor_line number Current line (1-indexed)
---@return table|nil conflict The conflict at cursor, or nil
function M.get_conflict_at_cursor(conflicts, cursor_line)
  for _, conflict in ipairs(conflicts) do
    if cursor_line >= conflict.start_line and cursor_line <= conflict.end_line then
      return conflict
    end
  end

  return nil
end

return M
