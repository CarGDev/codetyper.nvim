---@mod codetyper.agent.tools Tool definitions for the agent system
---
--- Defines available tools that the LLM can use to interact with files and system.

local M = {}

--- Tool definitions in a provider-agnostic format
M.definitions = {
  read_file = {
    name = "read_file",
    description = "Read the contents of a file at the specified path",
    parameters = {
      type = "object",
      properties = {
        path = {
          type = "string",
          description = "Absolute or relative path to the file to read",
        },
      },
      required = { "path" },
    },
  },

  edit_file = {
    name = "edit_file",
    description = "Edit a file by replacing specific content. Provide the exact content to find and the replacement.",
    parameters = {
      type = "object",
      properties = {
        path = {
          type = "string",
          description = "Path to the file to edit",
        },
        find = {
          type = "string",
          description = "Exact content to find (must match exactly, including whitespace)",
        },
        replace = {
          type = "string",
          description = "Content to replace with",
        },
      },
      required = { "path", "find", "replace" },
    },
  },

  write_file = {
    name = "write_file",
    description = "Write content to a file, creating it if it doesn't exist or overwriting if it does",
    parameters = {
      type = "object",
      properties = {
        path = {
          type = "string",
          description = "Path to the file to write",
        },
        content = {
          type = "string",
          description = "Complete file content to write",
        },
      },
      required = { "path", "content" },
    },
  },

  bash = {
    name = "bash",
    description = "Execute a bash command and return the output. Use for git, npm, build tools, etc.",
    parameters = {
      type = "object",
      properties = {
        command = {
          type = "string",
          description = "The bash command to execute",
        },
        timeout = {
          type = "number",
          description = "Timeout in milliseconds (default: 30000)",
        },
      },
      required = { "command" },
    },
  },
}

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
  local lines = {
    "You have access to the following tools. To use a tool, respond with a JSON block.",
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
  table.insert(lines, "To call a tool, output a JSON block like this:")
  table.insert(lines, "```json")
  table.insert(lines, '{"tool": "tool_name", "parameters": {"param1": "value1"}}')
  table.insert(lines, "```")
  table.insert(lines, "")
  table.insert(lines, "After receiving tool results, continue your response or call another tool.")
  table.insert(lines, "When you're done, just respond normally without any tool calls.")

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

return M
