--- Build system prompt from context — variable substitution and mode-specific additions
local utils = require("codetyper.support.utils")
local lang_map = require("codetyper.support.langmap")

--- Build the system prompt for LLM request
---@param context table { prompt_type, language, file_path, file_content, project_root, cwd, ... }
---@return string system_prompt
local function build_system_prompt(context)
  local prompts = require("codetyper.prompts")

  local prompt_type = context.prompt_type or "code_generation"
  local system_prompts = prompts.system
  local system = system_prompts[prompt_type] or system_prompts.code_generation

  -- Variable substitution
  system = system:gsub("{{language}}", context.language or "unknown")
  system = system:gsub("{{filepath}}", context.file_path or "unknown")

  -- Agent mode: include project context
  if prompt_type == "agent" then
    local project_info = "\n\n## PROJECT CONTEXT\n"

    if context.project_root then
      project_info = project_info .. "- Project root: " .. context.project_root .. "\n"
    end
    if context.cwd then
      project_info = project_info .. "- Working directory: " .. context.cwd .. "\n"
    end
    if context.project_type then
      project_info = project_info .. "- Project type: " .. context.project_type .. "\n"
    end
    if context.project_stats then
      project_info = project_info
        .. string.format(
          "- Stats: %d files, %d functions, %d classes\n",
          context.project_stats.files or 0,
          context.project_stats.functions or 0,
          context.project_stats.classes or 0
        )
    end
    if context.file_path then
      project_info = project_info .. "- Current file: " .. context.file_path .. "\n"
    end

    return system .. project_info
  end

  -- Ask/explain mode: minimal additions
  if prompt_type == "ask" or prompt_type == "explain" then
    if context.file_path then
      system = system .. "\n\nContext: The user is working with " .. context.file_path
      if context.language then
        system = system .. " (" .. context.language .. ")"
      end
    end
    return system
  end

  -- Code generation mode: include file content for style matching
  if context.file_content and context.file_content ~= "" then
    system = system .. "\n\n===== EXISTING FILE CONTENT (analyze and match this style) =====\n"
    system = system .. context.file_content
    system = system .. "\n===== END OF EXISTING FILE =====\n"
    system = system .. "\nYour generated code MUST follow the exact patterns shown above."
  else
    system = system
      .. "\n\nThis is a new/empty file. Generate clean, idiomatic "
      .. (context.language or "code")
      .. " following best practices."
  end

  return system
end

return build_system_prompt
