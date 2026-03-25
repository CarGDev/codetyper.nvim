--- Generate unified diff between two strings
---@param original string|nil
---@param modified string
---@param filepath string
---@return string[]
local function generate_diff_lines(original, modified, filepath)
  local lines = {}
  local filename = vim.fn.fnamemodify(filepath, ":t")

  if not original then
    -- New file
    table.insert(lines, "--- /dev/null")
    table.insert(lines, "+++ b/" .. filename)
    table.insert(lines, "@@ -0,0 +1," .. #vim.split(modified, "\n") .. " @@")
    for _, line in ipairs(vim.split(modified, "\n")) do
      table.insert(lines, "+" .. line)
    end
  else
    -- Modified file - use vim's diff
    table.insert(lines, "--- a/" .. filename)
    table.insert(lines, "+++ b/" .. filename)

    local orig_lines = vim.split(original, "\n")
    local mod_lines = vim.split(modified, "\n")

    -- Simple diff: show removed and added lines
    local max_lines = math.max(#orig_lines, #mod_lines)
    local context_start = 1
    local in_change = false

    for i = 1, max_lines do
      local orig = orig_lines[i] or ""
      local mod = mod_lines[i] or ""

      if orig ~= mod then
        if not in_change then
          table.insert(
            lines,
            string.format(
              "@@ -%d,%d +%d,%d @@",
              math.max(1, i - 2),
              math.min(5, #orig_lines - i + 3),
              math.max(1, i - 2),
              math.min(5, #mod_lines - i + 3)
            )
          )
          in_change = true
        end
        if orig ~= "" then
          table.insert(lines, "-" .. orig)
        end
        if mod ~= "" then
          table.insert(lines, "+" .. mod)
        end
      else
        if in_change then
          table.insert(lines, " " .. orig)
          in_change = false
        end
      end
    end
  end

  return lines
end

return generate_diff_lines
