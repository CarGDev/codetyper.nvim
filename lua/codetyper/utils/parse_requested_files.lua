--- Parse requested file paths from LLM response and resolve to full paths
---@param response string LLM response text
---@return string[] resolved_paths List of resolved absolute file paths
local function parse_requested_files(response)
  if not response or response == "" then
    return {}
  end

  local cwd = vim.fn.getcwd()
  local candidates = {}
  local seen = {}

  for path in response:gmatch("`([%w%._%-%/]+%.[%w_]+)`") do
    if not seen[path] then
      table.insert(candidates, path)
      seen[path] = true
    end
  end
  for path in response:gmatch("([%w%._%-%/]+%.[%w_]+)") do
    if not seen[path] then
      table.insert(candidates, path)
      seen[path] = true
    end
  end

  local resolved = {}
  for _, candidate_path in ipairs(candidates) do
    local full_path = nil
    if candidate_path:sub(1, 1) == "/" and vim.fn.filereadable(candidate_path) == 1 then
      full_path = candidate_path
    else
      local relative_path = cwd .. "/" .. candidate_path
      if vim.fn.filereadable(relative_path) == 1 then
        full_path = relative_path
      else
        local filename = candidate_path:match("[^/]+$") or candidate_path
        local glob_matches = vim.fn.globpath(cwd, "**/" .. filename, false, true)
        if glob_matches and #glob_matches > 0 then
          full_path = glob_matches[1]
        end
      end
    end
    if full_path and vim.fn.filereadable(full_path) == 1 then
      table.insert(resolved, full_path)
    end
  end

  return resolved
end

return parse_requested_files
