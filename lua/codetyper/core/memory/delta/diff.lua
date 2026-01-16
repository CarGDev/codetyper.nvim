--- Brain Delta Diff Computation
--- Field-level diff algorithms for delta versioning

local hash = require("codetyper.core.memory.hash")

local M = {}

--- Compute diff between two values
---@param before any Before value
---@param after any After value
---@param path? string Current path
---@return table[] Diff entries
function M.compute(before, after, path)
  path = path or ""
  local diffs = {}

  local before_type = type(before)
  local after_type = type(after)

  -- Handle nil cases
  if before == nil and after == nil then
    return diffs
  end

  if before == nil then
    table.insert(diffs, {
      path = path,
      op = "add",
      value = after,
    })
    return diffs
  end

  if after == nil then
    table.insert(diffs, {
      path = path,
      op = "delete",
      value = before,
    })
    return diffs
  end

  -- Type change
  if before_type ~= after_type then
    table.insert(diffs, {
      path = path,
      op = "replace",
      from = before,
      to = after,
    })
    return diffs
  end

  -- Tables (recursive)
  if before_type == "table" then
    -- Get all keys
    local keys = {}
    for k in pairs(before) do
      keys[k] = true
    end
    for k in pairs(after) do
      keys[k] = true
    end

    for k in pairs(keys) do
      local sub_path = path == "" and tostring(k) or (path .. "." .. tostring(k))
      local sub_diffs = M.compute(before[k], after[k], sub_path)
      for _, d in ipairs(sub_diffs) do
        table.insert(diffs, d)
      end
    end

    return diffs
  end

  -- Primitive comparison
  if before ~= after then
    table.insert(diffs, {
      path = path,
      op = "replace",
      from = before,
      to = after,
    })
  end

  return diffs
end

--- Apply a diff to a value
---@param base any Base value
---@param diffs table[] Diff entries
---@return any Result value
function M.apply(base, diffs)
  local result = vim.deepcopy(base) or {}

  for _, diff in ipairs(diffs) do
    M.apply_single(result, diff)
  end

  return result
end

--- Apply a single diff entry
---@param target table Target table
---@param diff table Diff entry
function M.apply_single(target, diff)
  local path = diff.path
  local parts = vim.split(path, ".", { plain = true })

  if #parts == 0 or parts[1] == "" then
    -- Root-level change
    if diff.op == "add" or diff.op == "replace" then
      for k, v in pairs(diff.value or diff.to or {}) do
        target[k] = v
      end
    end
    return
  end

  -- Navigate to parent
  local current = target
  for i = 1, #parts - 1 do
    local key = parts[i]
    -- Try numeric key
    local num_key = tonumber(key)
    key = num_key or key

    if current[key] == nil then
      current[key] = {}
    end
    current = current[key]
  end

  -- Apply to final key
  local final_key = parts[#parts]
  local num_key = tonumber(final_key)
  final_key = num_key or final_key

  if diff.op == "add" then
    current[final_key] = diff.value
  elseif diff.op == "delete" then
    current[final_key] = nil
  elseif diff.op == "replace" then
    current[final_key] = diff.to
  end
end

--- Reverse a diff (for rollback)
---@param diffs table[] Diff entries
---@return table[] Reversed diffs
function M.reverse(diffs)
  local reversed = {}

  for i = #diffs, 1, -1 do
    local diff = diffs[i]
    local rev = {
      path = diff.path,
    }

    if diff.op == "add" then
      rev.op = "delete"
      rev.value = diff.value
    elseif diff.op == "delete" then
      rev.op = "add"
      rev.value = diff.value
    elseif diff.op == "replace" then
      rev.op = "replace"
      rev.from = diff.to
      rev.to = diff.from
    end

    table.insert(reversed, rev)
  end

  return reversed
end

--- Compact diffs (combine related changes)
---@param diffs table[] Diff entries
---@return table[] Compacted diffs
function M.compact(diffs)
  local by_path = {}

  for _, diff in ipairs(diffs) do
    local existing = by_path[diff.path]
    if existing then
      -- Combine: keep first "from", use last "to"
      if diff.op == "replace" then
        existing.to = diff.to
      elseif diff.op == "delete" then
        existing.op = "delete"
        existing.to = nil
      end
    else
      by_path[diff.path] = vim.deepcopy(diff)
    end
  end

  -- Convert back to array, filter out no-ops
  local result = {}
  for _, diff in pairs(by_path) do
    -- Skip if add then delete (net no change)
    if not (diff.op == "delete" and diff.from == nil) then
      table.insert(result, diff)
    end
  end

  return result
end

--- Create a minimal diff summary for storage
---@param diffs table[] Diff entries
---@return table Summary
function M.summarize(diffs)
  local adds = 0
  local deletes = 0
  local replaces = 0
  local paths = {}

  for _, diff in ipairs(diffs) do
    if diff.op == "add" then
      adds = adds + 1
    elseif diff.op == "delete" then
      deletes = deletes + 1
    elseif diff.op == "replace" then
      replaces = replaces + 1
    end

    -- Extract top-level path
    local parts = vim.split(diff.path, ".", { plain = true })
    if parts[1] then
      paths[parts[1]] = true
    end
  end

  return {
    adds = adds,
    deletes = deletes,
    replaces = replaces,
    paths = vim.tbl_keys(paths),
    total = adds + deletes + replaces,
  }
end

--- Check if two states are equal (no diff)
---@param state1 any First state
---@param state2 any Second state
---@return boolean
function M.equals(state1, state2)
  local diffs = M.compute(state1, state2)
  return #diffs == 0
end

--- Get hash of diff for deduplication
---@param diffs table[] Diff entries
---@return string Hash
function M.hash(diffs)
  return hash.compute_table(diffs)
end

return M
