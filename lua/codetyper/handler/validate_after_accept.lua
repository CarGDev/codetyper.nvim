local params = require("codetyper.params.agents.conflict")

--- Lazy load linter module
local function get_linter()
  return require("codetyper.features.agents.linter")
end

--- Run linter validation after accepting code changes
---@param bufnr number Buffer number
---@param start_line number Start line of changed region
---@param end_line number End line of changed region
---@param accepted_type string Type of acceptance ("theirs", "both")
local function validate_after_accept(bufnr, start_line, end_line, accepted_type)
  local config = params.config
  if not config.lint_after_accept then
    return
  end

  if accepted_type ~= "theirs" and accepted_type ~= "both" then
    return
  end

  local linter = get_linter()

  linter.validate_after_injection(bufnr, start_line, end_line, function(result)
    if not result then
      return
    end

    if result.has_errors and config.auto_fix_lint_errors then
      pcall(function()
        local logs_add = require("codetyper.adapters.nvim.ui.logs.add")
        logs_add({
          type = "info",
          message = "Auto-queuing fix for lint errors...",
        })
      end)
      linter.request_ai_fix(bufnr, result)
    end
  end)
end

return validate_after_accept
