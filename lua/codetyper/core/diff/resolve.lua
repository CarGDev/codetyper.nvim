local M = {}

--- Extract "ours" (original) lines from a conflict
---@param lines string[] All buffer lines
---@param conflict table Conflict position data
---@return string[] keep_lines Lines to keep
function M.extract_ours(lines, conflict)
  local keep_lines = {}
  if conflict.current_start and conflict.current_end then
    for i = conflict.current_start + 1, conflict.current_end do
      table.insert(keep_lines, lines[i])
    end
  end
  return keep_lines
end

--- Extract "theirs" (incoming/AI) lines from a conflict
---@param lines string[] All buffer lines
---@param conflict table Conflict position data
---@return string[] keep_lines Lines to keep
function M.extract_theirs(lines, conflict)
  local keep_lines = {}
  if conflict.incoming_start and conflict.incoming_end then
    for i = conflict.incoming_start, conflict.incoming_end do
      table.insert(keep_lines, lines[i])
    end
  end
  return keep_lines
end

--- Extract "both" (current + incoming) lines from a conflict
---@param lines string[] All buffer lines
---@param conflict table Conflict position data
---@return string[] keep_lines Lines to keep
function M.extract_both(lines, conflict)
  local keep_lines = {}

  if conflict.current_start and conflict.current_end then
    for i = conflict.current_start + 1, conflict.current_end do
      table.insert(keep_lines, lines[i])
    end
  end

  if conflict.incoming_start and conflict.incoming_end then
    for i = conflict.incoming_start, conflict.incoming_end do
      table.insert(keep_lines, lines[i])
    end
  end

  return keep_lines
end

--- Build a conflict block from current and new lines
---@param current_lines string[] Original lines
---@param new_lines string[] Incoming lines
---@param markers table { current_start: string, separator: string, incoming_end: string }
---@param label? string Optional label for the incoming section
---@return string[] conflict_block Lines forming the conflict block
function M.build_conflict_block(current_lines, new_lines, markers, label)
  local conflict_block = {}
  table.insert(conflict_block, markers.current_start)
  for _, line in ipairs(current_lines) do
    table.insert(conflict_block, line)
  end
  table.insert(conflict_block, markers.separator)
  for _, line in ipairs(new_lines) do
    table.insert(conflict_block, line)
  end
  table.insert(conflict_block, label and (">>>>>>> " .. label) or markers.incoming_end)
  return conflict_block
end

--- Count lines in each section of a conflict
---@param conflict table Conflict position data
---@return number current_count Lines in current section
---@return number incoming_count Lines in incoming section
function M.count_sections(conflict)
  local current_count = conflict.current_end
      and conflict.current_start
      and (conflict.current_end - conflict.current_start)
    or 0
  local incoming_count = conflict.incoming_end
      and conflict.incoming_start
      and (conflict.incoming_end - conflict.incoming_start + 1)
    or 0
  return current_count, incoming_count
end

--- Build preview text for a section of lines
---@param lines string[] All buffer lines
---@param start_line number Start line index
---@param end_line number End line index
---@param max_preview_lines? number Max lines to show (default 3)
---@return string preview Formatted preview string
function M.build_preview(lines, start_line, end_line, max_preview_lines)
  max_preview_lines = max_preview_lines or 3
  local preview_lines = {}
  for i = start_line, math.min(end_line, start_line + max_preview_lines - 1) do
    if lines[i] then
      table.insert(preview_lines, "  " .. lines[i]:sub(1, 50))
    end
  end
  if end_line - start_line >= max_preview_lines then
    table.insert(preview_lines, "  ...")
  end
  return table.concat(preview_lines, "\n")
end

return M
