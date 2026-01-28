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
    "You are in DISCOVERY phase. Your goal is to THOROUGHLY explore and understand the codebase before creating a plan.",
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
    [[## Discovery Strategy

### Step 1: Understand Project Structure
- List root directory to see project layout
- Check for dependency files (package.json, Cargo.toml, pyproject.toml, etc.)
- Look for configuration files (.coder/rules/, .eslintrc, tsconfig.json, etc.)
- Identify the testing approach (test directories, test frameworks)

### Step 2: Find Relevant Code
- Search for files related to the task using multiple search terms
- If initial searches fail, try alternative terms (auth/login/session, button/btn, etc.)
- Look at imports to understand dependencies between modules
- Check for existing similar implementations to understand patterns

### Step 3: Deep Dive
- Read key files thoroughly - understand not just WHAT but HOW
- Look at existing tests to understand expected behavior
- Check for conventions in similar code (error handling, logging, naming)
- Note any constraints from project rules or configuration

## Available Tools (read-only)
- view: Read file contents
- grep: Search for patterns in files
- glob: Find files by pattern
- list_directory: List directory contents
- search_files: Search for files by name or content

## Search Best Practices
- Run multiple searches with different terms in parallel when possible
- If searching for "auth" fails, try "login", "user", "session", etc.
- Search for content that would BE IN the file, not just file names
- Look at 2-3 surrounding files to understand context

## Learning Markers
When you discover important project information, use these markers:
- [LEARN:structure:directory/path] Purpose description
- [LEARN:pattern:pattern_name] Pattern description
- [LEARN:file:path/to/file] File purpose
- [LEARN:architecture:aspect] How it works
- [LEARN:testing:] Testing approach
- [LEARN:dependency:package_name] Dependency note

## Completion Criteria
Before moving to planning, verify you know:
1. All files that will need modification
2. The patterns/conventions used in similar code
3. What dependencies are available
4. How testing is done (if applicable)
5. Any project-specific rules or constraints

When confident you have sufficient context, respond with:
"DISCOVERY_COMPLETE:" followed by a summary of what you learned.

DO NOT rush through discovery. Thorough understanding now prevents mistakes later.]]
  )

  return table.concat(prompt_parts, "\n")
end

---Build planning phase system prompt
---@param task string The task
---@param discovery_summary string Summary from discovery
---@return string
function M.build_planning_prompt(task, discovery_summary)
  return string.format(
    [[You are in PLANNING phase. Create a detailed, actionable implementation plan.

TASK: %s

DISCOVERY SUMMARY:
%s

## Planning Guidelines

### Step Granularity
- Each step should be ONE logical change
- Steps should be small enough to verify independently
- If a step requires multiple file changes, split it into multiple steps
- Order steps so each one builds on the previous

### Dependencies
- Create files before editing them
- Add imports before using them
- Run tests after making changes

### Common Patterns
1. **Adding a feature:**
   - Create new files (if needed)
   - Add imports to existing files
   - Implement the feature
   - Add/update tests
   - Run tests to verify

2. **Fixing a bug:**
   - Identify the root cause
   - Make the minimal fix
   - Add a test that would have caught it
   - Run tests to verify

3. **Refactoring:**
   - Make changes in small steps
   - Run tests after each step
   - Don't change behavior and structure simultaneously

## Plan Format

Respond with "PLAN:" followed by a JSON array:

```json
[
  {
    "id": "step-1",
    "description": "Clear description including the file and what changes",
    "tool": "write",
    "params": {
      "path": "path/to/new/file.ts",
      "content": "// Content will be generated during execution"
    }
  },
  {
    "id": "step-2",
    "description": "Add import for new module to main.ts",
    "tool": "edit",
    "params": {
      "path": "path/to/main.ts"
    }
  },
  {
    "id": "step-3",
    "description": "Run tests to verify changes work",
    "tool": "bash",
    "params": {
      "command": "npm test"
    }
  }
]
```

## Available Tools
- **write**: Create new file (params: path, content)
- **edit**: Modify existing file (params: path)
- **bash**: Run shell command (params: command)
- **delete**: Remove file (params: path)

## Requirements
✓ Include exact file paths discovered earlier
✓ Order steps logically (create before edit, edit before test)
✓ Include verification steps (tests, builds) where appropriate
✓ Make descriptions specific enough to execute without ambiguity

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

## Execution Guidelines

### Before Each Step
1. Read the file you're about to modify (unless creating new)
2. Understand the current state before making changes
3. Plan the exact change you'll make

### Making Edits
- Use EXACT string matching - copy text character-for-character from the file
- Include enough context to uniquely identify the location
- If edit fails, RE-READ the file and try again
- Preserve existing formatting and indentation

### After Each Step
- Verify the change was applied correctly
- If there's a test step coming, ensure current changes are ready for testing
- Report what was done and any issues encountered

### Error Handling
- If a step fails, STOP and analyze why
- Don't blindly retry - understand the error first
- If it's a matching error, re-read the file
- If it's a logic error, may need to adjust approach
- Report errors clearly with context

## Execution Rules
1. Execute steps in order - do NOT skip ahead
2. Complete each step before starting the next
3. If a step fails after 2-3 attempts, stop and report
4. Verify changes work before marking step complete

## Response Format
After each step, report:
- What was done
- Whether it succeeded or failed
- Any issues or observations

Begin executing. Focus on getting each step right before moving on.]],
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
