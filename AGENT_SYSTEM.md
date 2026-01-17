# CodeTyper Agent System

A robust, multi-phase agent system for codetyper.nvim with human-like memory organization.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    Agent Workflow                        │
├─────────────────────────────────────────────────────────┤
│                                                           │
│  ┌──────────────┐    ┌──────────────┐    ┌────────────┐│
│  │  DISCOVERY   │ →  │   PLANNING   │ →  │ EXECUTION  ││
│  │   PHASE      │    │    PHASE     │    │   PHASE    ││
│  └──────────────┘    └──────────────┘    └────────────┘│
│         │                   │                   │        │
│         ↓                   ↓                   ↓        │
│  ┌──────────────────────────────────────────────────┐  │
│  │         Memory System (Dual Memory)               │  │
│  ├──────────────────────────────────────────────────┤  │
│  │  Long-term Memory (Brain)  │  Short-term Memory  │  │
│  │  • Project knowledge       │  • Current task     │  │
│  │  • Persistent to disk      │  • Ephemeral        │  │
│  │  • Accumulates over time   │  • Cleared on done  │  │
│  └──────────────────────────────────────────────────┘  │
│                                                           │
│  ┌──────────────────────────────────────────────────┐  │
│  │             Middleware Layer                       │  │
│  ├──────────────────────────────────────────────────┤  │
│  │  • Session Management                             │  │
│  │  • Permission System (auto-approve safe tools)    │  │
│  │  • Hook System (pre/post tool execution)          │  │
│  │  • Retry Logic (exponential backoff)              │  │
│  └──────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

## Three-Phase Workflow

### Phase 1: Discovery

**Goal:** Learn about the project before making changes.

**Tools Available:** Read-only (view, grep, glob, search_files, list_directory)

**Process:**
1. Agent explores the codebase
2. Reads relevant files and searches for patterns
3. Understands project structure, conventions, and constraints
4. **Updates long-term memory** using [LEARN:] markers
5. Completes with `DISCOVERY_COMPLETE:` followed by summary

**Learning Markers:**
```lua
-- Agent can use these in their discovery notes:
[LEARN:structure:directory/path] Purpose description
[LEARN:pattern:pattern_name] Pattern description
[LEARN:file:path/to/file] File purpose
[LEARN:architecture:aspect] How it works
[LEARN:testing:] Testing approach
[LEARN:dependency:package_name] Dependency note
```

### Phase 2: Planning

**Goal:** Create a detailed, step-by-step implementation plan.

**Tools Available:** Read-only (view, grep, glob)

**Process:**
1. Reviews discovery findings and long-term knowledge
2. Designs implementation approach
3. Breaks down into atomic steps
4. Outputs plan as JSON: `PLAN:` followed by array of steps
5. User approves plan (currently auto-approved, TODO: add UI)
6. **Clears discovery notes** from working memory

**Plan Format:**
```json
[
  {
    "id": "step-1",
    "description": "What this step does",
    "tool": "edit" | "write" | "bash",
    "params": { "path": "...", "content": "..." }
  }
]
```

### Phase 3: Execution

**Goal:** Execute the approved plan step by step.

**Tools Available:** Full access (view, edit, write, bash, delete, etc.)

**Process:**
1. Executes steps sequentially
2. Tracks progress (pending → in_progress → completed/failed)
3. Handles errors with retry logic
4. Reports after each step
5. Completes when all steps done
6. **Clears working memory** (brain knowledge persists)

## Memory System

### Long-term Memory (Brain)

**Purpose:** Persistent knowledge about the project that accumulates over time.

**Storage:** `.coder/brain/knowledge.json`

**Structure:**
```lua
{
  structure = {
    ["lua/codetyper/"] = "Main source directory",
    ["tests/"] = "Test directory"
  },
  patterns = {
    error_handling = "Uses pcall for error handling",
    modules = "Each module returns a table"
  },
  key_files = {
    ["init.lua"] = "Plugin entry point",
    ["engine.lua"] = "Agent orchestration"
  },
  architecture = {
    state_management = "Uses local modules",
    tool_system = "Registry pattern with tool definitions"
  },
  testing = "Uses plenary.nvim for tests",
  dependencies = ["plenary.nvim", "nvim-cmp"],
  last_updated = 1736954321
}
```

**Lifecycle:**
- Loaded at agent start
- Updated during discovery phase
- Persisted to disk
- Survives across agent runs
- Can be reset with `brain.reset()`

### Short-term Memory (Working Memory)

**Purpose:** Ephemeral context for the current task.

**Storage:** In-memory only

**Structure:**
```lua
{
  task = "Implement dark mode",
  phase = "execution",
  discoveries = {
    {category = "file", finding = "Found theme.lua", timestamp = ...}
  },
  plan = {
    steps = [...],
    approved = true
  },
  context = {
    custom_key = "custom_value"
  },
  thoughts = {
    {text = "Analyzing structure", timestamp = ...}
  },
  created_at = 1736954321
}
```

**Lifecycle:**
- Created when task starts
- Updated during all phases
- Discoveries cleared after planning
- Cleared completely when task completes
- Does NOT persist across agent runs

## Middleware System

### Session Management

**Purpose:** Track permission caching for current agent run.

**Features:**
- Unique session ID
- Permission cache (session-scoped)
- Context storage
- Cleared on completion/error

### Permission System

**Purpose:** Auto-approve safe operations, require confirmation for dangerous ones.

**Safe Tools (auto-approved):**
- view, read, grep, glob, list, show, get (read-only)

**Dangerous Patterns (blocked):**
- `rm -rf`, `sudo`, `dd`, `mkfs`, `curl|sh`, `chmod 777`

**Caching:**
- Once approved, permission cached for session
- Same command auto-approved next time
- Cache cleared when session ends

### Hook System

**Purpose:** Execute callbacks before/after tool execution.

**Hook Types:**
- `pre_tool` - Before tool execution (can reject)
- `post_tool` - After tool completes
- `tool_error` - When tool fails
- `tool_timeout` - When tool times out

**Built-in Hooks:**
- Logging (tool start/complete with timing)
- Error reporting

**Custom Hooks:**
```lua
hooks.register("pre_tool", function(ctx)
  -- ctx.tool_name, ctx.input
  -- return false to reject execution
  return true
end)
```

### Retry Logic

**Purpose:** Automatically retry failed operations with exponential backoff.

**Policies:**
- `network` - Retry connection/timeout errors
- `filesystem` - Retry EBUSY/locked errors
- `always` - Retry all errors
- `never` - No retries

**Defaults:**
- Max attempts: 3
- Initial delay: 100ms
- Max delay: 5000ms
- Backoff factor: 2x

**Usage:**
```lua
local result = retry.with_retry_sync(function()
  -- Your code here
end, retry.policies.network)

if result.success then
  print(result.result)
else
  print("Failed after " .. result.attempts .. " attempts")
end
```

## Usage

### Basic Usage

```lua
local engine = require("codetyper.features.agents.engine")

engine.run_with_planner({
  task = "Add dark mode toggle to settings",
  agent = "coder",
  on_status = function(status)
    print(status)
  end,
  on_plan_ready = function(plan)
    print("Plan created with " .. #plan.steps .. " steps")
  end,
  on_complete = function(result, error)
    if error then
      print("Failed: " .. error)
    else
      print("Success!")
    end
  end
})
```

### Viewing Brain Knowledge

```lua
local brain = require("codetyper.features.agents.brain")
local knowledge = brain.load()

print(brain.format_for_context(knowledge))
print(brain.get_summary(knowledge))
```

### Checking Working Memory

```lua
local memory = require("codetyper.features.agents.memory")

if memory.is_active() then
  print(memory.get_summary())
  print(memory.format_for_context())
  print("Duration: " .. memory.get_duration() .. "s")
end
```

## Files

### Core Modules

| File | Purpose |
|------|---------|
| `lua/codetyper/features/agents/engine.lua` | Agent orchestration (run, run_with_planner) |
| `lua/codetyper/features/agents/planner.lua` | Multi-phase workflow management |
| `lua/codetyper/features/agents/brain.lua` | Long-term project knowledge |
| `lua/codetyper/features/agents/memory.lua` | Short-term working memory |

### Middleware

| File | Purpose |
|------|---------|
| `lua/codetyper/features/agents/middleware/session.lua` | Session state |
| `lua/codetyper/features/agents/middleware/permissions.lua` | Permission checking |
| `lua/codetyper/features/agents/middleware/hooks.lua` | Hook system |
| `lua/codetyper/features/agents/middleware/retry.lua` | Retry logic |

### Tests

| File | Tests |
|------|-------|
| `tests/spec/middleware_spec.lua` | Middleware (40 tests) |
| `tests/spec/brain_memory_spec.lua` | Brain & Memory (38 tests) |

## Benefits

1. **Structured Workflow** - Clear phases (discover → plan → execute)
2. **Knowledge Accumulation** - Brain learns and remembers project patterns
3. **Safety** - Permission system prevents dangerous operations
4. **Reliability** - Retry logic handles transient failures
5. **Observability** - Hooks provide logging and monitoring
6. **Testability** - Comprehensive test coverage (78+ tests)

## Future Enhancements

- [ ] UI for plan approval (currently auto-approved)
- [ ] Persistent permissions across sessions
- [ ] More granular permission levels
- [ ] Tool-specific retry policies
- [ ] Webhook support for external integrations
- [ ] Plan templates for common tasks
- [ ] Brain knowledge export/import
- [ ] Multi-agent collaboration
- [ ] Learning from execution failures

## Test Coverage

**Middleware:** 40 passing tests
- Session management (6 tests)
- Permissions (12 tests)
- Hooks (12 tests)
- Retry logic (10 tests)

**Brain & Memory:** 38 passing tests
- Brain learning (15 tests)
- Working memory (23 tests)

**Total:** 78 passing tests, 0 failures

Run tests:
```bash
nvim --headless -c "PlenaryBustedDirectory tests/spec/" -c "qa!"
```
