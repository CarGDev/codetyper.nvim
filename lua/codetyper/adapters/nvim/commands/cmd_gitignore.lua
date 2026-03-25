--- Force update gitignore
local function cmd_gitignore()
  local gitignore = require("codetyper.support.gitignore")
  gitignore.force_update()
end

return cmd_gitignore
