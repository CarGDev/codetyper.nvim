---@mod codetyper.agent.resume Resume context for agent sessions
---
--- Saves and loads agent state to allow continuing long-running tasks.

local M = {}

local utils = require("codetyper.utils")

--- Get the resume context directory
---@return string|nil
local function get_resume_dir()
  local root = utils.get_project_root() or vim.fn.getcwd()
  return root .. "/.coder/tmp"
end

--- Get the resume context file path
---@return string|nil
local function get_resume_path()
  local dir = get_resume_dir()
  if not dir then
    return nil
  end
  return dir .. "/agent_resume.json"
end

--- Ensure the resume directory exists
---@return boolean
local function ensure_resume_dir()
  local dir = get_resume_dir()
  if not dir then
    return false
  end
  return utils.ensure_dir(dir)
end

---@class ResumeContext
---@field conversation table[] Message history
---@field pending_tool_results table[] Pending results
---@field iteration number Current iteration count
---@field original_prompt string Original user prompt
---@field timestamp number When saved
---@field project_root string Project root path

--- Save the current agent state for resuming later
---@param conversation table[] Conversation history
---@param pending_results table[] Pending tool results
---@param iteration number Current iteration
---@param original_prompt string Original prompt
---@return boolean Success
function M.save(conversation, pending_results, iteration, original_prompt)
  if not ensure_resume_dir() then
    return false
  end

  local path = get_resume_path()
  if not path then
    return false
  end

  local context = {
    conversation = conversation,
    pending_tool_results = pending_results,
    iteration = iteration,
    original_prompt = original_prompt,
    timestamp = os.time(),
    project_root = utils.get_project_root() or vim.fn.getcwd(),
  }

  local ok, json = pcall(vim.json.encode, context)
  if not ok then
    utils.notify("Failed to encode resume context", vim.log.levels.ERROR)
    return false
  end

  local success = utils.write_file(path, json)
  if success then
    utils.notify("Agent state saved. Use /continue to resume.", vim.log.levels.INFO)
  end
  return success
end

--- Load saved agent state
---@return ResumeContext|nil
function M.load()
  local path = get_resume_path()
  if not path then
    return nil
  end

  local content = utils.read_file(path)
  if not content or content == "" then
    return nil
  end

  local ok, context = pcall(vim.json.decode, content)
  if not ok or not context then
    return nil
  end

  return context
end

--- Check if there's a saved resume context
---@return boolean
function M.has_saved_state()
  local path = get_resume_path()
  if not path then
    return false
  end
  return vim.fn.filereadable(path) == 1
end

--- Get info about saved state (for display)
---@return table|nil
function M.get_info()
  local context = M.load()
  if not context then
    return nil
  end

  local age_seconds = os.time() - (context.timestamp or 0)
  local age_str
  if age_seconds < 60 then
    age_str = age_seconds .. " seconds ago"
  elseif age_seconds < 3600 then
    age_str = math.floor(age_seconds / 60) .. " minutes ago"
  else
    age_str = math.floor(age_seconds / 3600) .. " hours ago"
  end

  return {
    prompt = context.original_prompt,
    iteration = context.iteration,
    messages = #context.conversation,
    saved_at = age_str,
    project = context.project_root,
  }
end

--- Clear saved resume context
---@return boolean
function M.clear()
  local path = get_resume_path()
  if not path then
    return false
  end

  if vim.fn.filereadable(path) == 1 then
    os.remove(path)
    return true
  end
  return false
end

return M
