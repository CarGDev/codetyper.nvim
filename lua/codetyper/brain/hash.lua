--- Brain Hashing Utilities
--- Content-addressable storage with 8-character hashes

local M = {}

--- Simple DJB2 hash algorithm (fast, good distribution)
---@param str string String to hash
---@return number Hash value
local function djb2(str)
  local hash = 5381
  for i = 1, #str do
    hash = ((hash * 33) + string.byte(str, i)) % 0x100000000
  end
  return hash
end

--- Convert number to hex string
---@param num number Number to convert
---@param len number Desired length
---@return string Hex string
local function to_hex(num, len)
  local hex = string.format("%x", num)
  if #hex < len then
    hex = string.rep("0", len - #hex) .. hex
  end
  return hex:sub(-len)
end

--- Compute 8-character hash from string
---@param content string Content to hash
---@return string 8-character hex hash
function M.compute(content)
  if not content or content == "" then
    return "00000000"
  end
  local hash = djb2(content)
  return to_hex(hash, 8)
end

--- Compute hash from table (JSON-serialized)
---@param tbl table Table to hash
---@return string 8-character hex hash
function M.compute_table(tbl)
  local ok, json = pcall(vim.json.encode, tbl)
  if not ok then
    return "00000000"
  end
  return M.compute(json)
end

--- Generate unique node ID
---@param node_type string Node type prefix
---@param content? string Optional content for hash
---@return string Node ID (n_<timestamp>_<hash>)
function M.node_id(node_type, content)
  local ts = os.time()
  local hash_input = (content or "") .. tostring(ts) .. tostring(math.random(100000))
  local hash = M.compute(hash_input):sub(1, 6)
  return string.format("n_%s_%d_%s", node_type, ts, hash)
end

--- Generate unique edge ID
---@param source_id string Source node ID
---@param target_id string Target node ID
---@return string Edge ID (e_<source_hash>_<target_hash>)
function M.edge_id(source_id, target_id)
  local src_hash = M.compute(source_id):sub(1, 4)
  local tgt_hash = M.compute(target_id):sub(1, 4)
  return string.format("e_%s_%s", src_hash, tgt_hash)
end

--- Generate delta hash
---@param changes table[] Delta changes
---@param parent string|nil Parent delta hash
---@param timestamp number Delta timestamp
---@return string 8-character delta hash
function M.delta_hash(changes, parent, timestamp)
  local content = (parent or "root") .. tostring(timestamp)
  for _, change in ipairs(changes or {}) do
    content = content .. (change.op or "") .. (change.path or "")
  end
  return M.compute(content)
end

--- Hash file path for storage
---@param filepath string File path
---@return string 8-character hash
function M.path_hash(filepath)
  return M.compute(filepath)
end

--- Check if two hashes match
---@param hash1 string First hash
---@param hash2 string Second hash
---@return boolean True if matching
function M.matches(hash1, hash2)
  return hash1 == hash2
end

--- Generate random hash (for testing/temporary IDs)
---@return string 8-character random hash
function M.random()
  local chars = "0123456789abcdef"
  local result = ""
  for _ = 1, 8 do
    local idx = math.random(1, #chars)
    result = result .. chars:sub(idx, idx)
  end
  return result
end

return M
