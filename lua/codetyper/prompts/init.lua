---@mod codetyper.prompts Prompt templates for Codetyper.nvim
---
--- This module provides all prompt templates used by the plugin.
--- Prompts are organized by functionality and can be customized.

local M = {}

-- Load all prompt modules
M.system = require("codetyper.prompts.system")
M.code = require("codetyper.prompts.code")
M.ask = require("codetyper.prompts.ask")
M.refactor = require("codetyper.prompts.refactor")
M.document = require("codetyper.prompts.document")
M.agent = require("codetyper.prompts.agent")

--- Get a prompt by category and name
---@param category string Category name (system, code, ask, refactor, document)
---@param name string Prompt name
---@param vars? table Variables to substitute in the prompt
---@return string Formatted prompt
function M.get(category, name, vars)
  local prompts = M[category]
  if not prompts then
    error("Unknown prompt category: " .. category)
  end

  local prompt = prompts[name]
  if not prompt then
    error("Unknown prompt: " .. category .. "." .. name)
  end

  -- Substitute variables if provided
  if vars then
    for key, value in pairs(vars) do
      prompt = prompt:gsub("{{" .. key .. "}}", tostring(value))
    end
  end

  return prompt
end

--- List all available prompts
---@return table Available prompts by category
function M.list()
  local result = {}
  for category, prompts in pairs(M) do
    if type(prompts) == "table" and category ~= "list" and category ~= "get" then
      result[category] = {}
      for name, _ in pairs(prompts) do
        table.insert(result[category], name)
      end
    end
  end
  return result
end

return M
