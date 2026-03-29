--- Execute agent file operations — create files, modify buffers, manage imports
local flog = require("codetyper.support.flog") -- TODO: remove after debugging

local M = {}

--- Create a new file with content
---@param path string Absolute file path
---@param content string File content
---@return boolean success
---@return string|nil error
function M.create_file(path, content)
  -- Ensure directory exists
  local dir = vim.fn.fnamemodify(path, ":h")
  vim.fn.mkdir(dir, "p")

  local f = io.open(path, "w")
  if not f then
    return false, "Cannot create file: " .. path
  end
  f:write(content)
  f:close()

  flog.info("agent.exec", "created: " .. path) -- TODO: remove after debugging

  -- Open the new file in a vertical split so user can review it alongside the original
  vim.schedule(function()
    vim.cmd("vsplit " .. vim.fn.fnameescape(path))
    vim.notify("Created: " .. vim.fn.fnamemodify(path, ":~:."), vim.log.levels.INFO)
  end)

  return true
end

--- Modify a file using search/replace
---@param path string Absolute file path
---@param search string Exact code to find
---@param replace string Replacement code
---@return boolean success
---@return string|nil error
function M.modify_file(path, search, replace)
  -- Read current content
  local ok_read, lines = pcall(vim.fn.readfile, path)
  if not ok_read or not lines then
    return false, "Cannot read file: " .. path
  end

  local content = table.concat(lines, "\n")

  -- Find and replace (exact match)
  local escaped_search = search:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
  local new_content, count = content:gsub(escaped_search, replace, 1)

  if count == 0 then
    -- Try with normalized whitespace (trim trailing spaces per line)
    local norm_content = content:gsub(" +\n", "\n")
    local norm_search = search:gsub(" +\n", "\n")
    local norm_escaped = norm_search:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    new_content, count = norm_content:gsub(norm_escaped, replace, 1)

    if count == 0 then
      flog.warn("agent.exec", "SEARCH text not found in " .. path) -- TODO: remove after debugging
      return false, "SEARCH text not found in file: " .. vim.fn.fnamemodify(path, ":t")
    end
  end

  -- Write back
  local new_lines = vim.split(new_content, "\n", { plain = true })
  local f = io.open(path, "w")
  if not f then
    return false, "Cannot write file: " .. path
  end
  f:write(new_content)
  f:close()

  flog.info("agent.exec", "modified: " .. path) -- TODO: remove after debugging

  -- Reload buffer if open
  vim.schedule(function()
    local bufnr = vim.fn.bufnr(path)
    if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)
    end
    vim.notify("Modified: " .. vim.fn.fnamemodify(path, ":~:."), vim.log.levels.INFO)
  end)

  return true
end

--- Delete a file
---@param path string Absolute file path
---@return boolean success
---@return string|nil error
function M.delete_file(path)
  local ok, err = os.remove(path)
  if not ok then
    return false, "Cannot delete: " .. (err or path)
  end

  flog.info("agent.exec", "deleted: " .. path) -- TODO: remove after debugging

  vim.schedule(function()
    -- Close buffer if open
    local bufnr = vim.fn.bufnr(path)
    if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
    vim.notify("Deleted: " .. vim.fn.fnamemodify(path, ":~:."), vim.log.levels.INFO)
  end)

  return true
end

--- Execute a list of file operations
---@param operations table[] FileOperation list from parse_response
---@return number applied Count of successful operations
---@return number failed Count of failed operations
---@return string[] errors List of error messages
function M.execute(operations)
  local applied = 0
  local failed = 0
  local errors = {}

  for _, op in ipairs(operations) do
    local ok, err

    if op.action == "create" then
      ok, err = M.create_file(op.path, op.content)
    elseif op.action == "modify" then
      ok, err = M.modify_file(op.path, op.search, op.replace)
    elseif op.action == "delete" then
      ok, err = M.delete_file(op.path)
    else
      ok = false
      err = "Unknown action: " .. tostring(op.action)
    end

    if ok then
      applied = applied + 1
    else
      failed = failed + 1
      table.insert(errors, err or "Unknown error")
      flog.error("agent.exec", err or "Unknown error") -- TODO: remove after debugging
    end
  end

  flog.info("agent.exec", string.format("done: %d applied, %d failed", applied, failed)) -- TODO: remove after debugging

  if applied > 0 then
    vim.schedule(function()
      vim.notify(
        string.format("Agent: %d operation%s applied", applied, applied > 1 and "s" or ""),
        vim.log.levels.INFO
      )
    end)
  end
  if failed > 0 then
    vim.schedule(function()
      vim.notify(
        string.format("Agent: %d operation%s failed:\n%s", failed, failed > 1 and "s" or "", table.concat(errors, "\n")),
        vim.log.levels.WARN
      )
    end)
  end

  return applied, failed, errors
end

return M
