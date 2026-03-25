local utils = require("codetyper.support.utils")

--- Show learned memories
local function cmd_memories()
  local memory = require("codetyper.features.indexer.memory")

  local all = memory.get_all()
  local lines = {
    "Learned Memories",
    "================",
    "",
    "Patterns:",
  }

  local pattern_count = 0
  for _, mem in pairs(all.patterns) do
    pattern_count = pattern_count + 1
    if pattern_count <= 10 then
      table.insert(lines, "  - " .. (mem.content or ""):sub(1, 60))
    end
  end
  if pattern_count > 10 then
    table.insert(lines, "  ... and " .. (pattern_count - 10) .. " more")
  elseif pattern_count == 0 then
    table.insert(lines, "  (none)")
  end

  table.insert(lines, "")
  table.insert(lines, "Conventions:")

  local conv_count = 0
  for _, mem in pairs(all.conventions) do
    conv_count = conv_count + 1
    if conv_count <= 10 then
      table.insert(lines, "  - " .. (mem.content or ""):sub(1, 60))
    end
  end
  if conv_count > 10 then
    table.insert(lines, "  ... and " .. (conv_count - 10) .. " more")
  elseif conv_count == 0 then
    table.insert(lines, "  (none)")
  end

  utils.notify(table.concat(lines, "\n"))
end

return cmd_memories
