---@mod codetyper.llm LLM interface for Codetyper.nvim

local M = {}

local extract_code = require("codetyper.core.llm.shared.extract_code")
local build_system_prompt = require("codetyper.core.llm.shared.build_system_prompt")

--- Get the appropriate LLM client based on configuration
---@param provider_name string|nil Override provider name
---@return table LLM client module
function M.get_client(provider_name)
  local provider = provider_name
  if not provider then
    local codetyper = require("codetyper")
    local config = codetyper.get_config()
    provider = config.llm.provider
  end

  if provider == "ollama" then
    return require("codetyper.core.llm.providers.ollama")
  elseif provider == "copilot" then
    return require("codetyper.core.llm.providers.copilot")
  else
    error("Unknown LLM provider: " .. provider .. ". Supported: ollama, copilot")
  end
end

--- Generate code from a prompt
---@param prompt string The user's prompt
---@param context table Context information
---@param callback fun(response: string|nil, error: string|nil) Callback function
function M.generate(prompt, context, callback)
  local client = M.get_client()
  client.generate(prompt, context, callback)
end

--- Smart generate with automatic provider selection
---@param prompt string The user's prompt
---@param context table Context information
---@param callback fun(response: string|nil, error: string|nil, metadata: table|nil) Callback
function M.smart_generate(prompt, context, callback)
  local selector = require("codetyper.core.llm.selector")
  selector.smart_generate(prompt, context, callback)
end

--- Get accuracy statistics for providers
---@return table Statistics for each provider
function M.get_accuracy_stats()
  local selector = require("codetyper.core.llm.selector")
  return selector.get_accuracy_stats()
end

--- Report user feedback on response quality
---@param provider string Which provider generated the response
---@param was_correct boolean Whether the response was good
function M.report_feedback(provider, was_correct)
  local selector = require("codetyper.core.llm.selector")
  selector.report_feedback(provider, was_correct)
end

--- Build the system prompt for code generation
---@param context table Context information
---@return string System prompt
M.build_system_prompt = build_system_prompt

--- Build context for LLM request
---@param target_path string Path to target file
---@param prompt_type string Type of prompt
---@return table Context object
function M.build_context(target_path, prompt_type)
  local utils = require("codetyper.support.utils")
  local lang_map = require("codetyper.support.langmap")
  local content = utils.read_file(target_path)
  local ext = vim.fn.fnamemodify(target_path, ":e")

  local context = {
    file_content = content,
    language = lang_map[ext] or ext,
    extension = ext,
    prompt_type = prompt_type,
    file_path = target_path,
  }

  if prompt_type == "agent" then
    local project_root = utils.get_project_root()
    context.project_root = project_root

    local ok_indexer, indexer = pcall(require, "codetyper.indexer")
    if ok_indexer then
      local status = indexer.get_status()
      if status.indexed then
        context.project_type = status.project_type
        context.project_stats = status.stats
      end
    end

    context.cwd = vim.fn.getcwd()
  end

  return context
end

--- Parse LLM response and extract code
---@param response string Raw LLM response
---@return string Extracted code
M.extract_code = extract_code

return M
