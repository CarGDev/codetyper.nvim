local utils = require("codetyper.support.utils")

--- Index the entire project
local function cmd_index_project()
  local indexer = require("codetyper.features.indexer")

  utils.notify("Indexing project...", vim.log.levels.INFO)

  indexer.index_project(function(index)
    if index then
      local msg = string.format(
        "Indexed: %d files, %d functions, %d classes, %d exports",
        index.stats.files,
        index.stats.functions,
        index.stats.classes,
        index.stats.exports
      )
      utils.notify(msg, vim.log.levels.INFO)
    else
      utils.notify("Failed to index project", vim.log.levels.ERROR)
    end
  end)
end

return cmd_index_project
