---@mod codetyper.agent.memory Short-term working memory
---@brief [[
--- Ephemeral memory for current task execution.
--- Similar to working/short-term memory in the human brain.
--- Cleared when task completes.
---@brief ]]

local M = {}

---@class WorkingMemory
---@field task string Current task description
---@field phase string Current execution phase
---@field discoveries table[] Discovery findings (cleared after planning)
---@field plan? table Current execution plan
---@field context table Additional context for current task
---@field thoughts string[] Agent's reasoning/thoughts
---@field created_at number Memory creation timestamp

---@type WorkingMemory|nil
local current_memory = nil

---Create new working memory for a task
---@param task string The task to accomplish
---@return WorkingMemory
function M.create(task)
  current_memory = {
    task = task,
    phase = "discovery",
    discoveries = {},
    context = {},
    thoughts = {},
    created_at = os.time(),
  }

  return current_memory
end

---Get current working memory
---@return WorkingMemory|nil
function M.get()
  return current_memory
end

---Clear working memory (task complete)
function M.clear()
  current_memory = nil
end

---Check if working memory is active
---@return boolean
function M.is_active()
  return current_memory ~= nil
end

---Add a discovery finding
---@param category string Category (e.g., "file", "pattern", "architecture")
---@param finding string What was discovered
function M.add_discovery(category, finding)
  if not current_memory then
    return
  end

  table.insert(current_memory.discoveries, {
    category = category,
    finding = finding,
    timestamp = os.time(),
  })
end

---Get all discoveries
---@return table[] discoveries
function M.get_discoveries()
  if not current_memory then
    return {}
  end

  return current_memory.discoveries
end

---Clear discoveries (after planning phase starts)
function M.clear_discoveries()
  if current_memory then
    current_memory.discoveries = {}
  end
end

---Set the execution plan
---@param plan table The plan to execute
function M.set_plan(plan)
  if current_memory then
    current_memory.plan = plan
  end
end

---Get the current plan
---@return table|nil plan
function M.get_plan()
  if not current_memory then
    return nil
  end

  return current_memory.plan
end

---Update current phase
---@param phase string New phase
function M.set_phase(phase)
  if current_memory then
    current_memory.phase = phase
  end
end

---Get current phase
---@return string|nil phase
function M.get_phase()
  if not current_memory then
    return nil
  end

  return current_memory.phase
end

---Add agent thought/reasoning
---@param thought string What the agent is thinking
function M.add_thought(thought)
  if not current_memory then
    return
  end

  table.insert(current_memory.thoughts, {
    text = thought,
    timestamp = os.time(),
  })

  -- Keep only last 50 thoughts to avoid memory bloat
  if #current_memory.thoughts > 50 then
    table.remove(current_memory.thoughts, 1)
  end
end

---Get recent thoughts
---@param count? number Number of recent thoughts (default: 10)
---@return table[] thoughts
function M.get_recent_thoughts(count)
  count = count or 10

  if not current_memory then
    return {}
  end

  local thoughts = current_memory.thoughts
  local start_idx = math.max(1, #thoughts - count + 1)
  local recent = {}

  for i = start_idx, #thoughts do
    table.insert(recent, thoughts[i])
  end

  return recent
end

---Set context value
---@param key string Context key
---@param value any Context value
function M.set_context(key, value)
  if current_memory then
    current_memory.context[key] = value
  end
end

---Get context value
---@param key string Context key
---@return any value
function M.get_context(key)
  if not current_memory then
    return nil
  end

  return current_memory.context[key]
end

---Format working memory for LLM context
---@return string formatted Formatted memory as markdown
function M.format_for_context()
  if not current_memory then
    return "# No active working memory\n"
  end

  local sections = {}

  table.insert(sections, "# Working Memory (Current Task)")
  table.insert(sections, "")

  table.insert(sections, "## Current Task")
  table.insert(sections, current_memory.task)
  table.insert(sections, "")

  table.insert(sections, string.format("## Phase: %s", current_memory.phase))
  table.insert(sections, "")

  -- Discoveries (during discovery phase)
  if #current_memory.discoveries > 0 then
    table.insert(sections, "## Recent Discoveries")
    for _, disc in ipairs(current_memory.discoveries) do
      table.insert(sections, string.format("- [%s] %s", disc.category, disc.finding))
    end
    table.insert(sections, "")
  end

  -- Plan (during execution phase)
  if current_memory.plan then
    table.insert(sections, "## Current Plan")
    if current_memory.plan.steps then
      for i, step in ipairs(current_memory.plan.steps) do
        table.insert(
          sections,
          string.format("%d. [%s] %s", i, step.status or "pending", step.description)
        )
      end
    end
    table.insert(sections, "")
  end

  -- Recent thoughts
  local recent_thoughts = M.get_recent_thoughts(5)
  if #recent_thoughts > 0 then
    table.insert(sections, "## Recent Thoughts")
    for _, thought in ipairs(recent_thoughts) do
      table.insert(sections, string.format("- %s", thought.text))
    end
    table.insert(sections, "")
  end

  return table.concat(sections, "\n")
end

---Get memory summary
---@return string summary
function M.get_summary()
  if not current_memory then
    return "No active task"
  end

  local parts = {}
  table.insert(parts, string.format("Task: %s", current_memory.task:sub(1, 50)))
  table.insert(parts, string.format("Phase: %s", current_memory.phase))

  if #current_memory.discoveries > 0 then
    table.insert(parts, string.format("%d discoveries", #current_memory.discoveries))
  end

  if current_memory.plan and current_memory.plan.steps then
    local completed = 0
    for _, step in ipairs(current_memory.plan.steps) do
      if step.status == "completed" then
        completed = completed + 1
      end
    end
    table.insert(
      parts,
      string.format("Plan: %d/%d steps", completed, #current_memory.plan.steps)
    )
  end

  return table.concat(parts, " | ")
end

---Get task duration
---@return number|nil duration Duration in seconds
function M.get_duration()
  if not current_memory then
    return nil
  end

  return os.time() - current_memory.created_at
end

return M
