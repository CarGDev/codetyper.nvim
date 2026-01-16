--- Brain Delta Commit Operations
--- Git-like commit creation and management

local storage = require("codetyper.core.memory.storage")
local hash_mod = require("codetyper.core.memory.hash")
local diff_mod = require("codetyper.core.memory.delta.diff")
local types = require("codetyper.core.memory.types")

local M = {}

--- Create a new delta commit
---@param changes table[] Changes to commit
---@param message string Commit message
---@param trigger? string Trigger source
---@return Delta|nil Created delta
function M.create(changes, message, trigger)
  if not changes or #changes == 0 then
    return nil
  end

  local now = os.time()
  local head = storage.get_head()

  -- Create delta object
  local delta = {
    h = hash_mod.delta_hash(changes, head, now),
    p = head,
    ts = now,
    ch = {},
    m = {
      msg = message or "Unnamed commit",
      trig = trigger or "manual",
    },
  }

  -- Process changes
  for _, change in ipairs(changes) do
    table.insert(delta.ch, {
      op = change.op,
      path = change.path,
      bh = change.bh,
      ah = change.ah,
      diff = change.diff,
    })
  end

  -- Save delta
  storage.save_delta(delta)

  -- Update HEAD
  storage.set_head(delta.h)

  -- Update meta
  local meta = storage.get_meta()
  storage.update_meta({ dc = meta.dc + 1 })

  return delta
end

--- Get a delta by hash
---@param delta_hash string Delta hash
---@return Delta|nil
function M.get(delta_hash)
  return storage.get_delta(delta_hash)
end

--- Get the current HEAD delta
---@return Delta|nil
function M.get_head()
  local head_hash = storage.get_head()
  if not head_hash then
    return nil
  end
  return M.get(head_hash)
end

--- Get delta history (ancestry chain)
---@param limit? number Max entries
---@param from_hash? string Starting hash (default: HEAD)
---@return Delta[]
function M.get_history(limit, from_hash)
  limit = limit or 50
  local history = {}
  local current_hash = from_hash or storage.get_head()

  while current_hash and #history < limit do
    local delta = M.get(current_hash)
    if not delta then
      break
    end

    table.insert(history, delta)
    current_hash = delta.p
  end

  return history
end

--- Check if a delta exists
---@param delta_hash string Delta hash
---@return boolean
function M.exists(delta_hash)
  return M.get(delta_hash) ~= nil
end

--- Get the path from one delta to another
---@param from_hash string Start delta hash
---@param to_hash string End delta hash
---@return Delta[]|nil Path of deltas, or nil if no path
function M.get_path(from_hash, to_hash)
  -- Build ancestry from both sides
  local from_ancestry = {}
  local current = from_hash
  while current do
    from_ancestry[current] = true
    local delta = M.get(current)
    if not delta then
      break
    end
    current = delta.p
  end

  -- Walk from to_hash back to find common ancestor
  local path = {}
  current = to_hash
  while current do
    local delta = M.get(current)
    if not delta then
      break
    end

    table.insert(path, 1, delta)

    if from_ancestry[current] then
      -- Found common ancestor
      return path
    end

    current = delta.p
  end

  return nil
end

--- Get all changes between two deltas
---@param from_hash string|nil Start delta hash (nil = beginning)
---@param to_hash string End delta hash
---@return table[] Combined changes
function M.get_changes_between(from_hash, to_hash)
  local path = {}
  local current = to_hash

  while current and current ~= from_hash do
    local delta = M.get(current)
    if not delta then
      break
    end
    table.insert(path, 1, delta)
    current = delta.p
  end

  -- Collect all changes
  local changes = {}
  for _, delta in ipairs(path) do
    for _, change in ipairs(delta.ch) do
      table.insert(changes, change)
    end
  end

  return changes
end

--- Compute reverse changes for rollback
---@param delta Delta Delta to reverse
---@return table[] Reverse changes
function M.compute_reverse(delta)
  local reversed = {}

  for i = #delta.ch, 1, -1 do
    local change = delta.ch[i]
    local rev = {
      path = change.path,
    }

    if change.op == types.DELTA_OPS.ADD then
      rev.op = types.DELTA_OPS.DELETE
      rev.bh = change.ah
    elseif change.op == types.DELTA_OPS.DELETE then
      rev.op = types.DELTA_OPS.ADD
      rev.ah = change.bh
    elseif change.op == types.DELTA_OPS.MODIFY then
      rev.op = types.DELTA_OPS.MODIFY
      rev.bh = change.ah
      rev.ah = change.bh
      if change.diff then
        rev.diff = diff_mod.reverse(change.diff)
      end
    end

    table.insert(reversed, rev)
  end

  return reversed
end

--- Squash multiple deltas into one
---@param delta_hashes string[] Delta hashes to squash
---@param message string Squash commit message
---@return Delta|nil Squashed delta
function M.squash(delta_hashes, message)
  if #delta_hashes == 0 then
    return nil
  end

  -- Collect all changes in order
  local all_changes = {}
  for _, delta_hash in ipairs(delta_hashes) do
    local delta = M.get(delta_hash)
    if delta then
      for _, change in ipairs(delta.ch) do
        table.insert(all_changes, change)
      end
    end
  end

  -- Compact the changes
  local compacted = diff_mod.compact(all_changes)

  return M.create(compacted, message, "squash")
end

--- Get summary of a delta
---@param delta Delta Delta to summarize
---@return table Summary
function M.summarize(delta)
  local adds = 0
  local mods = 0
  local dels = 0
  local paths = {}

  for _, change in ipairs(delta.ch) do
    if change.op == types.DELTA_OPS.ADD then
      adds = adds + 1
    elseif change.op == types.DELTA_OPS.MODIFY then
      mods = mods + 1
    elseif change.op == types.DELTA_OPS.DELETE then
      dels = dels + 1
    end

    -- Extract category from path
    local parts = vim.split(change.path, ".", { plain = true })
    if parts[1] then
      paths[parts[1]] = true
    end
  end

  return {
    hash = delta.h,
    parent = delta.p,
    timestamp = delta.ts,
    message = delta.m.msg,
    trigger = delta.m.trig,
    stats = {
      adds = adds,
      modifies = mods,
      deletes = dels,
      total = adds + mods + dels,
    },
    categories = vim.tbl_keys(paths),
  }
end

--- Format delta for display
---@param delta Delta Delta to format
---@return string[] Lines
function M.format(delta)
  local summary = M.summarize(delta)
  local lines = {
    string.format("commit %s", delta.h),
    string.format("Date:   %s", os.date("%Y-%m-%d %H:%M:%S", delta.ts)),
    string.format("Parent: %s", delta.p or "(none)"),
    "",
    "    " .. (delta.m.msg or "No message"),
    "",
    string.format(" %d additions, %d modifications, %d deletions", summary.stats.adds, summary.stats.modifies, summary.stats.deletes),
  }

  return lines
end

return M
