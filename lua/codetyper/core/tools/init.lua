---@mod codetyper.agent.tools Tool definitions for the agent system
---
--- Defines available tools that the LLM can use to interact with files and system.

local M = {}

--- Tool definitions in a provider-agnostic format
M.definitions = require("codetyper.params.agents.tools").definitions

--- Registry for tool implementations
local registry = require("codetyper.core.tools.registry")

--- Get a tool by name (delegates to registry)
---@param name string Tool name
---@return CoderTool|nil
function M.get(name)
  -- Ensure tools are loaded
  if not registry.get(name) then
    registry.load_builtins()
  end
  return registry.get(name)
end

--- Register a tool (delegates to registry)
---@param tool CoderTool Tool to register
function M.register(tool)
  registry.register(tool)
end

--- Get all registered tools
---@return table<string, CoderTool>
function M.get_all()
  if vim.tbl_count(registry.get_all()) == 0 then
    registry.load_builtins()
  end
  return registry.get_all()
end

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
  -- Inline tool instructions (prompts moved to Python agent)
  local intro = "You have access to the following tools. To use a tool, respond with a JSON block."
  local header = "To call a tool, output a JSON block like this:"
  local example = '```json\n{"tool": "tool_name", "parameters": {"param1": "value1"}}\n```'
  local footer = "After receiving tool results, continue your response or call another tool.\nWhen you're done, just respond normally without any tool calls."

  local lines = {
    intro,
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
  table.insert(lines, header)
  table.insert(lines, example)
  table.insert(lines, "")
  table.insert(lines, footer)

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

