---@mod codetyper.llm LLM interface for Codetyper.nvim

local M = {}

local utils = require("codetyper.utils")

--- Get the appropriate LLM client based on configuration
---@return table LLM client module
function M.get_client()
  local codetyper = require("codetyper")
  local config = codetyper.get_config()

  if config.llm.provider == "claude" then
    return require("codetyper.llm.claude")
  elseif config.llm.provider == "ollama" then
    return require("codetyper.llm.ollama")
  else
    error("Unknown LLM provider: " .. config.llm.provider)
  end
end

--- Generate code from a prompt
---@param prompt string The user's prompt
---@param context table Context information (file content, language, etc.)
---@param callback fun(response: string|nil, error: string|nil) Callback function
function M.generate(prompt, context, callback)
  local client = M.get_client()
  client.generate(prompt, context, callback)
end

--- Build the system prompt for code generation
---@param context table Context information
---@return string System prompt
function M.build_system_prompt(context)
  local prompts = require("codetyper.prompts")
  
  -- Select appropriate system prompt based on context
  local prompt_type = context.prompt_type or "code_generation"
  local system_prompts = prompts.system
  
  local system = system_prompts[prompt_type] or system_prompts.code_generation
  
  -- Substitute variables
  system = system:gsub("{{language}}", context.language or "unknown")
  system = system:gsub("{{filepath}}", context.file_path or "unknown")

  if context.file_content then
    system = system .. "\n\nExisting file content:\n```\n" .. context.file_content .. "\n```"
  end

  return system
end

--- Build context for LLM request
---@param target_path string Path to target file
---@param prompt_type string Type of prompt
---@return table Context object
function M.build_context(target_path, prompt_type)
  local content = utils.read_file(target_path)
  local ext = vim.fn.fnamemodify(target_path, ":e")

  -- Map extension to language
  local lang_map = {
    ts = "TypeScript",
    tsx = "TypeScript React",
    js = "JavaScript",
    jsx = "JavaScript React",
    py = "Python",
    lua = "Lua",
    go = "Go",
    rs = "Rust",
    rb = "Ruby",
    java = "Java",
    c = "C",
    cpp = "C++",
    cs = "C#",
  }

  return {
    file_content = content,
    language = lang_map[ext] or ext,
    extension = ext,
    prompt_type = prompt_type,
    file_path = target_path,
  }
end

--- Parse LLM response and extract code
---@param response string Raw LLM response
---@return string Extracted code
function M.extract_code(response)
  -- Remove markdown code blocks if present
  local code = response:gsub("```%w*\n?", ""):gsub("\n?```", "")

  -- Trim whitespace
  code = code:match("^%s*(.-)%s*$")

  return code
end

return M
