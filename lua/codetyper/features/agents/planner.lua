---@mod codetyper.agent.planner Multi-phase agent planner
---@brief [[
--- Orchestrates agent workflow through three phases:
--- 1. Discovery - Learn about the project/codebase
--- 2. Planning - Create detailed implementation plan
--- 3. Execution - Execute the approved plan
---@brief ]]

local M = {}

---@alias AgentPhase "discovery" | "planning" | "execution" | "complete"

---@class PlanStep
---@field id string Step identifier
---@field description string What this step does
---@field tool string Tool to use (edit, write, bash, etc.)
---@field params table Tool parameters
---@field status "pending" | "in_progress" | "completed" | "failed"
---@field result? string Step result
---@field error? string Error if failed

---@class AgentPlan
---@field task string Original task description
---@field discovery_summary string What was learned in discovery
---@field steps PlanStep[] Plan steps
---@field created_at number Plan creation timestamp
---@field approved boolean Whether plan is approved by user

---@class PlannerState
---@field phase AgentPhase Current phase
---@field task string Original task
---@field plan? AgentPlan The plan
---@field discovery_notes string[] Notes from discovery
---@field on_phase_change? fun(phase: AgentPhase) Called when phase changes
---@field on_plan_ready? fun(plan: AgentPlan) Called when plan is created
---@field on_step_complete? fun(step: PlanStep) Called when step completes

local logs = require("codetyper.adapters.nvim.ui.logs")

---Create a new planner state
---@param task string The task to accomplish
---@param opts? table Options
---@return PlannerState
function M.create(task, opts)
  opts = opts or {}

  return {
    phase = "discovery",
    task = task,
    discovery_notes = {},
    on_phase_change = opts.on_phase_change,
    on_plan_ready = opts.on_plan_ready,
    on_step_complete = opts.on_step_complete,
  }
end

---Get tools allowed in discovery phase (read-only)
---@return string[]
function M.get_discovery_tools()
  return {
    "view",
    "read",
    "grep",
    "glob",
    "list",
    "search_files",
    "list_directory",
  }
end

---Get tools allowed in planning phase (read-only + thinking)
---@return string[]
function M.get_planning_tools()
  return {
    "view",
    "read",
    "grep",
    "glob",
    "list",
  }
end

---Get tools allowed in execution phase (full access)
---@return string[]
function M.get_execution_tools()
  return {
    "view",
    "read",
    "grep",
    "glob",
    "edit",
    "write",
    "bash",
    "delete",
    "list",
    "search_files",
  }
end

---Build discovery phase system prompt
---@param task string The task
---@param brain_knowledge? string Existing long-term knowledge about the project
---@return string
function M.build_discovery_prompt(task, brain_knowledge)
  local prompt_parts = {
    "You are in DISCOVERY phase. Your goal is to explore and understand the codebase before creating a plan.",
    "",
    string.format("TASK: %s", task),
    "",
  }

  -- Include existing brain knowledge if available
  if brain_knowledge and brain_knowledge ~= "" then
    table.insert(prompt_parts, "EXISTING PROJECT KNOWLEDGE:")
    table.insert(prompt_parts, brain_knowledge)
    table.insert(prompt_parts, "")
  end

  table.insert(
    prompt_parts,
    [[YOUR OBJECTIVES:
1. Explore the project structure and understand the codebase organization
2. Find relevant files, patterns, and conventions
3. Identify dependencies and existing implementations
4. Understand the testing approach
5. Note any constraints or requirements from .coder/rules/
6. Update long-term knowledge about the project

AVAILABLE TOOLS (read-only):
- view: Read file contents
- grep: Search for patterns in files
- glob: Find files by pattern
- list_directory: List directory contents
- search_files: Search for files by name or content

LEARNING NEW KNOWLEDGE:
When you discover important project information, use these markers to update long-term memory:
- [LEARN:structure:directory/path] Purpose description
- [LEARN:pattern:pattern_name] Pattern description
- [LEARN:file:path/to/file] File purpose
- [LEARN:architecture:aspect] How it works
- [LEARN:testing:] Testing approach
- [LEARN:dependency:package_name] Dependency note

IMPORTANT:
- You CANNOT make changes yet - this is discovery only
- Take thorough notes about what you find
- Use [LEARN:] markers to update project knowledge
- Focus on understanding before planning
- When ready, respond with "DISCOVERY_COMPLETE:" followed by a summary

Start by exploring the codebase to understand how to accomplish this task.]]
  )

  return table.concat(prompt_parts, "\n")
end

---Build planning phase system prompt
---@param task string The task
---@param discovery_summary string Summary from discovery
---@return string
function M.build_planning_prompt(task, discovery_summary)
  return string.format(
    [[You are in PLANNING phase. Create a detailed implementation plan based on your discovery.

TASK: %s

DISCOVERY SUMMARY:
%s

YOUR OBJECTIVES:
1. Create a step-by-step implementation plan
2. Break down the task into small, manageable steps
3. Identify which files need to be created/modified
4. Specify the order of operations
5. Include testing steps

PLAN FORMAT:
Respond with "PLAN:" followed by a JSON array of steps:
[
  {
    "id": "step-1",
    "description": "Clear description of what this step does",
    "tool": "edit" | "write" | "bash",
    "params": { /* tool-specific parameters */ }
  },
  ...
]

REQUIREMENTS:
- Each step should be atomic and independent
- Include clear descriptions
- Specify exact file paths
- Include tests if required
- Order steps logically

Create the plan now.]],
    task,
    discovery_summary
  )
end

---Build execution phase system prompt
---@param task string The task
---@param plan AgentPlan The approved plan
---@return string
function M.build_execution_prompt(task, plan)
  local steps_text = {}
  for i, step in ipairs(plan.steps) do
    table.insert(
      steps_text,
      string.format("%d. [%s] %s", i, step.status, step.description)
    )
  end

  return string.format(
    [[You are in EXECUTION phase. Execute the approved plan step by step.

TASK: %s

APPROVED PLAN:
%s

YOUR OBJECTIVES:
1. Execute each pending step in order
2. Verify each step completes successfully
3. Handle errors and retry if needed
4. Report progress after each step

EXECUTION RULES:
- Execute steps in the specified order
- Do not skip steps
- If a step fails, stop and report the error
- Verify changes work before proceeding

Begin executing the plan. Report after each step.]],
    task,
    table.concat(steps_text, "\n")
  )
end

---Transition to a new phase
---@param state PlannerState
---@param new_phase AgentPhase
function M.transition_phase(state, new_phase)
  logs.add({
    type = "phase",
    message = string.format("Phase: %s → %s", state.phase, new_phase),
  })

  state.phase = new_phase

  if state.on_phase_change then
    state.on_phase_change(new_phase)
  end
end

---Parse discovery completion from agent response
---@param content string Agent response
---@return string? summary Discovery summary if found
function M.parse_discovery_complete(content)
  local summary = content:match("DISCOVERY_COMPLETE:%s*(.+)")
  if summary then
    return summary:gsub("^%s+", ""):gsub("%s+$", "")
  end
  return nil
end

---Parse plan from agent response
---@param content string Agent response
---@return PlanStep[]? steps Plan steps if found
function M.parse_plan(content)
  -- Look for PLAN: followed by JSON array
  local json_match = content:match("PLAN:%s*(%b[])")
  if not json_match then
    -- Also try to find standalone JSON array
    json_match = content:match("(%b[])")
  end

  if json_match then
    local ok, steps = pcall(vim.json.decode, json_match)
    if ok and type(steps) == "table" then
      -- Validate and normalize steps
      local normalized = {}
      for i, step in ipairs(steps) do
        if type(step) == "table" and step.description and step.tool then
          table.insert(normalized, {
            id = step.id or string.format("step-%d", i),
            description = step.description,
            tool = step.tool,
            params = step.params or {},
            status = "pending",
          })
        end
      end
      return #normalized > 0 and normalized or nil
    end
  end

  return nil
end

---Create a plan from parsed steps
---@param task string Original task
---@param discovery_summary string Discovery summary
---@param steps PlanStep[] Plan steps
---@return AgentPlan
function M.create_plan(task, discovery_summary, steps)
  return {
    task = task,
    discovery_summary = discovery_summary,
    steps = steps,
    created_at = os.time(),
    approved = false,
  }
end

---Get the next pending step in plan
---@param plan AgentPlan
---@return PlanStep? step Next pending step or nil if all complete
function M.get_next_step(plan)
  for _, step in ipairs(plan.steps) do
    if step.status == "pending" then
      return step
    end
  end
  return nil
end

---Mark a step as in progress
---@param plan AgentPlan
---@param step_id string
function M.start_step(plan, step_id)
  for _, step in ipairs(plan.steps) do
    if step.id == step_id then
      step.status = "in_progress"
      logs.add({
        type = "step",
        message = string.format("Starting: %s", step.description),
      })
      return
    end
  end
end

---Mark a step as completed
---@param plan AgentPlan
---@param step_id string
---@param result string Step result
---@param on_complete? fun(step: PlanStep)
function M.complete_step(plan, step_id, result, on_complete)
  for _, step in ipairs(plan.steps) do
    if step.id == step_id then
      step.status = "completed"
      step.result = result
      logs.add({
        type = "step",
        message = string.format("✓ Completed: %s", step.description),
      })

      if on_complete then
        on_complete(step)
      end
      return
    end
  end
end

---Mark a step as failed
---@param plan AgentPlan
---@param step_id string
---@param error string Error message
function M.fail_step(plan, step_id, error)
  for _, step in ipairs(plan.steps) do
    if step.id == step_id then
      step.status = "failed"
      step.error = error
      logs.add({
        type = "error",
        message = string.format("✗ Failed: %s - %s", step.description, error),
      })
      return
    end
  end
end

---Check if plan is complete
---@param plan AgentPlan
---@return boolean complete True if all steps completed
---@return number completed Number of completed steps
---@return number total Total number of steps
function M.is_plan_complete(plan)
  local completed = 0
  local total = #plan.steps

  for _, step in ipairs(plan.steps) do
    if step.status == "completed" then
      completed = completed + 1
    end
  end

  return completed == total, completed, total
end

---Get plan progress summary
---@param plan AgentPlan
---@return string summary Human-readable progress
function M.get_progress_summary(plan)
  local complete, completed, total = M.is_plan_complete(plan)

  if complete then
    return string.format("Plan complete: %d/%d steps", completed, total)
  else
    local pending = 0
    local failed = 0
    for _, step in ipairs(plan.steps) do
      if step.status == "pending" then
        pending = pending + 1
      elseif step.status == "failed" then
        failed = failed + 1
      end
    end

    return string.format(
      "Progress: %d/%d steps (pending: %d, failed: %d)",
      completed,
      total,
      pending,
      failed
    )
  end
end

---Format plan for user approval
---@param plan AgentPlan
---@return string formatted Formatted plan for display
function M.format_plan_for_approval(plan)
  local lines = {
    "# Implementation Plan",
    "",
    "## Task",
    plan.task,
    "",
    "## Discovery Summary",
    plan.discovery_summary,
    "",
    "## Steps",
  }

  for i, step in ipairs(plan.steps) do
    table.insert(lines, string.format("%d. **%s**", i, step.description))
    table.insert(lines, string.format("   - Tool: `%s`", step.tool))
    if step.params and next(step.params) then
      table.insert(lines, string.format("   - Params: %s", vim.inspect(step.params)))
    end
    table.insert(lines, "")
  end

  table.insert(lines, "---")
  table.insert(lines, "Approve this plan? (y/n)")

  return table.concat(lines, "\n")
end

return M
