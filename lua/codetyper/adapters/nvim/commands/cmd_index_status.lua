local utils = require("codetyper.support.utils")

--- Show index status
local function cmd_index_status()
  local indexer = require("codetyper.features.indexer")
  local memory = require("codetyper.features.indexer.memory")

  local status = indexer.get_status()
  local mem_stats = memory.get_stats()

  local lines = {
    "Project Index Status",
    "====================",
    "",
  }

  if status.indexed then
    table.insert(lines, "Status: Indexed")
    table.insert(lines, "Project Type: " .. (status.project_type or "unknown"))
    table.insert(lines, "Last Indexed: " .. os.date("%Y-%m-%d %H:%M:%S", status.last_indexed))
    table.insert(lines, "")
    table.insert(lines, "Stats:")
    table.insert(lines, "  Files: " .. (status.stats.files or 0))
    table.insert(lines, "  Functions: " .. (status.stats.functions or 0))
    table.insert(lines, "  Classes: " .. (status.stats.classes or 0))
    table.insert(lines, "  Exports: " .. (status.stats.exports or 0))
  else
    table.insert(lines, "Status: Not indexed")
    table.insert(lines, "Run :CoderIndexProject to index")
  end

  table.insert(lines, "")
  table.insert(lines, "Memories:")
  table.insert(lines, "  Patterns: " .. mem_stats.patterns)
  table.insert(lines, "  Conventions: " .. mem_stats.conventions)
  table.insert(lines, "  Symbols: " .. mem_stats.symbols)

  utils.notify(table.concat(lines, "\n"))
end

return cmd_index_status
