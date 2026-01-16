---@mod codetyper.agent.tools Tool definitions for the agent system
---
--- Defines available tools that the LLM can use to interact with files and system.

local M = {}

--- Tool definitions in a provider-agnostic format
M.definitions = require("codetyper.params.agent.tools").definitions

--- Convert tool definitions to Claude API format
---@return table[] Tools in Claude's expected format
function M.to_claude_format()
  local tools = {}
  for _, tool in pairs(M.definitions) do
    table.insert(tools, {
      name = tool.name,
      description = tool.description,
      input_schema = tool.parameters,
    })
  end
  return tools
end

--- Convert tool definitions to OpenAI API format
---@return table[] Tools in OpenAI's expected format
function M.to_openai_format()
  local tools = {}
  for _, tool in pairs(M.definitions) do
    table.insert(tools, {
      type = "function",
      ["function"] = {
        name = tool.name,
        description = tool.description,
        parameters = tool.parameters,
      },
    })
  end
  return tools
end

--- Convert tool definitions to prompt format for Ollama
---@return string Formatted tool descriptions for system prompt
function M.to_prompt_format()
  local prompts = require("codetyper.prompts.agent.tools").instructions
  local lines = {
    prompts.intro,
    "",
  }

  for _, tool in pairs(M.definitions) do
    table.insert(lines, "## " .. tool.name)
    table.insert(lines, tool.description)
    table.insert(lines, "")
    table.insert(lines, "Parameters:")
    for prop_name, prop in pairs(tool.parameters.properties) do
      local required = vim.tbl_contains(tool.parameters.required or {}, prop_name)
      local req_str = required and " (required)" or " (optional)"
      table.insert(lines, "  - " .. prop_name .. ": " .. prop.description .. req_str)
    end
    table.insert(lines, "")
  end

  table.insert(lines, "---")
  table.insert(lines, "")
  table.insert(lines, prompts.header)
  table.insert(lines, prompts.example)
  table.insert(lines, "")
  table.insert(lines, prompts.footer)

  return table.concat(lines, "\n")
end

--- Get a list of tool names
---@return string[]
function M.get_tool_names()
  local names = {}
  for name, _ in pairs(M.definitions) do
    table.insert(names, name)
  end
  return names
end

--- Optional setup function for future extensibility
---@param opts table|nil Configuration options
function M.setup(opts)
  -- Currently a no-op. Plugins or tests may call setup(); keep for compatibility.
end

return M

