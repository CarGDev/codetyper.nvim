# Migration Task List

> **Principle**: Only *reasoning* moves to the agent; *reaction* stays in Lua.
> The agent becomes heavier, slower, and more deliberate.
> Lua becomes lighter, faster, and more mechanical.

---

## Phase 1: Foundation Setup

### Task 1.1: Create Agent Directory Structure
**Status**: [x] Completed

**What to do**:
Create the Python agent directory structure with empty placeholder files. This establishes the target architecture before any migration begins.

**Files involved**:
- `agent/__init__.py` (create)
- `agent/main.py` (create)
- `agent/protocol.py` (create)
- `agent/schemas.py` (create)
- `agent/intent.py` (create)
- `agent/planner.py` (create)
- `agent/context.py` (create)
- `agent/validator.py` (create)
- `agent/formatter.py` (create)
- `agent/memory/__init__.py` (create)
- `agent/memory/graph.py` (create)
- `agent/memory/learners.py` (create)
- `agent/memory/storage.py` (create)
- `agent/prompts/__init__.py` (create)
- `agent/prompts/edit.py` (create)
- `agent/prompts/intent.py` (create)
- `agent/prompts/system.py` (create)

**Prompt**:
```
Create the agent/ directory structure with empty Python files as placeholders.
Each file should have a module docstring explaining its purpose based on the
migration plan. Include __init__.py files for proper package structure.
Do not implement any logic yet - just establish the skeleton.
```

---

### Task 1.2: Define Protocol Schema
**Status**: [x] Completed

**What to do**:
Define the JSON-RPC protocol for communication between Lua and the Python agent. This is the contract that both sides must adhere to.

**Files involved**:
- `agent/protocol.py` (create)
- `agent/schemas.py` (create)
- `lua/codetyper/transport/protocol.lua` (create)

**Prompt**:
```
Define the communication protocol between Lua and the Python agent:

1. In agent/protocol.py, implement:
   - JSON-RPC request/response handlers
   - Message types: "classify_intent", "build_plan", "validate_plan", "format_output"
   - Error handling with structured error codes

2. In agent/schemas.py, define Pydantic models for:
   - IntentRequest: {context: str, prompt: str, files: list[str]}
   - IntentResponse: {intent: str, confidence: float, reasoning: str}
   - PlanRequest: {intent: str, context: str, files: dict[str, str]}
   - PlanResponse: {steps: list[PlanStep], needs_clarification: bool, questions: list[str]}
   - ValidationRequest: {plan: Plan, original_files: dict}
   - ValidationResponse: {valid: bool, errors: list[str]}

3. In lua/codetyper/transport/protocol.lua, create the Lua-side protocol handler
   that serializes requests and deserializes responses.
```

---

### Task 1.3: Create Transport Layer
**Status**: [x] Completed

**What to do**:
Implement the transport mechanism for Lua to communicate with the Python agent process. Use subprocess with stdin/stdout for simplicity.

**Files involved**:
- `lua/codetyper/transport/agent_client.lua` (create)
- `agent/main.py` (implement stdin/stdout loop)

**Prompt**:
```
Implement the transport layer for Lua <-> Python communication:

1. In agent/main.py:
   - Create a main loop that reads JSON-RPC requests from stdin
   - Dispatch to appropriate handlers based on method name
   - Write JSON-RPC responses to stdout
   - Handle graceful shutdown on SIGTERM/SIGINT

2. In lua/codetyper/transport/agent_client.lua:
   - Spawn the Python agent as a subprocess
   - Implement send_request(method, params) -> response
   - Handle process lifecycle (start, stop, restart on crash)
   - Implement request timeout handling
   - Queue requests if agent is busy (single-threaded agent)

Use vim.loop (libuv) for async subprocess handling in Lua.
```

---

## Phase 2: Intent Classification Migration

### Task 2.1: Extract Intent Classification Logic
**Status**: [x] Completed

**What to do**:
Move all intent classification logic from Lua to Python. The Lua side should only collect raw context and forward it.

**Files involved**:
- `lua/codetyper/core/intent/init.lua` (simplify to forwarder)
- `lua/codetyper/features/ask/intent.lua` (remove reasoning, keep forwarding)
- `lua/codetyper/params/agents/intent.lua` (move constants to Python)
- `agent/intent.py` (implement full classification)

**Prompt**:
```
Migrate intent classification from Lua to Python:

1. Analyze current Lua intent logic in:
   - lua/codetyper/core/intent/init.lua
   - lua/codetyper/features/ask/intent.lua
   - lua/codetyper/params/agents/intent.lua

2. In agent/intent.py, implement:
   - IntentClassifier class
   - classify(context: str, prompt: str) -> IntentResult
   - Support intents: ask, code, refactor, document, fix, explain, test
   - Confidence scoring with reasoning
   - Ambiguity detection that returns questions instead of guessing

3. Simplify lua/codetyper/core/intent/init.lua to:
   - Gather context (buffer content, cursor position, selection)
   - Call agent_client.send_request("classify_intent", params)
   - Return the response without modification
   - Delete all classification heuristics

4. Delete lua/codetyper/params/agents/intent.lua (constants move to Python)
```

---

### Task 2.2: Remove Lua Confidence Scoring
**Status**: [x] Completed

**What to do**:
Remove all confidence scoring logic from Lua. The agent now owns confidence decisions.

**Files involved**:
- `lua/codetyper/core/llm/confidence.lua` (delete or gut)
- `lua/codetyper/params/agents/confidence.lua` (delete)
- `agent/intent.py` (already has confidence)

**Prompt**:
```
Remove confidence scoring from Lua:

1. Delete lua/codetyper/params/agents/confidence.lua entirely

2. In lua/codetyper/core/llm/confidence.lua:
   - Remove all scoring logic
   - Keep only a passthrough that returns agent-provided confidence
   - Or delete entirely if no callers remain

3. Update any callers of the confidence module to use agent response directly

4. Ensure all confidence thresholds and decisions are in agent/intent.py
```

---

## Phase 3: Plan Construction Migration

### Task 3.1: Migrate Plan Building to Agent
**Status**: [x] Completed

**What to do**:
Move all plan construction logic to Python. This includes deciding what files to change, what order, and what operations.

**Files involved**:
- `lua/codetyper/features/agents/planner.lua` (simplify to forwarder)
- `lua/codetyper/core/scheduler/scheduler.lua` (remove plan logic)
- `agent/planner.py` (implement full planning)

**Prompt**:
```
Migrate plan construction from Lua to Python:

1. Analyze current planning logic in:
   - lua/codetyper/features/agents/planner.lua
   - lua/codetyper/core/scheduler/scheduler.lua

2. In agent/planner.py, implement:
   - Planner class
   - build_plan(intent: Intent, context: Context, files: dict) -> Plan
   - Plan structure: {steps: list[PlanStep], dependencies: dict, rollback: list}
   - PlanStep: {action: str, target: str, params: dict, depends_on: list[str]}
   - Actions: read, write, edit, delete, rename, create_dir
   - Dependency resolution between steps
   - Ambiguity detection (ask for clarification, don't guess)

3. Simplify lua/codetyper/features/agents/planner.lua to:
   - Receive intent from classifier
   - Call agent_client.send_request("build_plan", params)
   - Return plan without modification
   - Delete all plan construction logic

4. Update lua/codetyper/core/scheduler/scheduler.lua:
   - Remove any plan-building logic
   - Keep only plan execution (receives plan, executes steps)
```

---

### Task 3.2: Implement Plan Validation in Agent
**Status**: [x] Completed

**What to do**:
Add plan validation in Python that checks if a plan is safe and complete before execution.

**Files involved**:
- `agent/validator.py` (create)
- `lua/codetyper/executor/validate.lua` (simplify to forwarder)

**Prompt**:
```
Implement plan validation in the Python agent:

1. In agent/validator.py, implement:
   - PlanValidator class
   - validate(plan: Plan, files: dict[str, str]) -> ValidationResult
   - Checks:
     - All referenced files exist or will be created
     - No circular dependencies
     - No destructive operations on protected files (.git, node_modules, etc.)
     - Edit operations have valid search/replace targets
     - File permissions are respected
   - Return {valid: bool, errors: list[str], warnings: list[str]}

2. In lua/codetyper/executor/validate.lua:
   - Remove all validation logic
   - Call agent_client.send_request("validate_plan", params)
   - Return validation result to caller
   - Lua only checks response schema, never validates content
```

---

## Phase 4: Prompt Shaping Migration

### Task 4.1: Move All Prompts to Python
**Status**: [x] Completed

**What to do**:
Move all LLM prompt templates and construction logic to Python. Lua should never construct prompts.

**Files involved**:
- `lua/codetyper/prompts/` (entire directory - mark for deletion)
- `agent/prompts/system.py` (create)
- `agent/prompts/edit.py` (create)
- `agent/prompts/intent.py` (create)

**Prompt**:
```
Migrate all prompts from Lua to Python:

1. Analyze all prompts in lua/codetyper/prompts/:
   - init.lua, ask.lua, code.lua, document.lua, refactor.lua
   - agents/init.lua, agents/tools.lua, agents/intent.lua, etc.

2. In agent/prompts/system.py:
   - Base system prompt for the agent
   - Context injection templates
   - Tool use instructions

3. In agent/prompts/edit.py:
   - Code modification prompts
   - SEARCH/REPLACE format instructions
   - Multi-file edit prompts

4. In agent/prompts/intent.py:
   - Intent classification prompts
   - Ambiguity resolution prompts
   - Clarification question templates

5. Create agent/prompts/__init__.py that exports:
   - get_system_prompt(context: Context) -> str
   - get_edit_prompt(intent: Intent, files: dict) -> str
   - get_intent_prompt(raw_input: str) -> str

6. Mark lua/codetyper/prompts/ for deletion (after all consumers migrated)
```

---

### Task 4.2: Remove Prompt Logic from Lua
**Status**: [ ] Not Started (Prompts shims created but consumers still use them)

**What to do**:
Delete or gut all Lua files that construct prompts. Replace with agent calls.

**Files involved**:
- `lua/codetyper/prompts/init.lua` (delete)
- `lua/codetyper/prompts/ask.lua` (delete)
- `lua/codetyper/prompts/code.lua` (delete)
- `lua/codetyper/prompts/document.lua` (delete)
- `lua/codetyper/prompts/refactor.lua` (delete)
- `lua/codetyper/prompts/agents/` (delete entire directory)

**Prompt**:
```
Remove all prompt construction from Lua:

1. Identify all consumers of lua/codetyper/prompts/ modules

2. Update each consumer to:
   - Not construct prompts locally
   - Send raw context to agent instead
   - Receive fully-formed prompt from agent (or let agent call LLM)

3. Delete these files after updating consumers:
   - lua/codetyper/prompts/init.lua
   - lua/codetyper/prompts/ask.lua
   - lua/codetyper/prompts/code.lua
   - lua/codetyper/prompts/document.lua
   - lua/codetyper/prompts/refactor.lua
   - lua/codetyper/prompts/agents/ (entire directory)

4. Update require() calls throughout codebase to remove dead references
```

---

## Phase 5: Memory System Migration

### Task 5.1: Migrate Memory Graph to Python
**Status**: [x] Completed

**What to do**:
Move the memory graph system to Python. This is reasoning infrastructure.

**Files involved**:
- `lua/codetyper/core/memory/` (entire directory - migrate)
- `agent/memory/graph.py` (create)
- `agent/memory/storage.py` (create)

**Prompt**:
```
Migrate memory graph from Lua to Python:

1. Analyze current memory implementation in lua/codetyper/core/memory/:
   - init.lua, storage.lua, hash.lua, types.lua
   - graph/init.lua, graph/node.lua, graph/edge.lua, graph/query.lua
   - delta/init.lua, delta/diff.lua, delta/commit.lua
   - output/init.lua, output/formatter.lua

2. In agent/memory/graph.py, implement:
   - MemoryGraph class
   - Node and Edge types
   - add_node(type, content, metadata) -> node_id
   - add_edge(source, target, relation)
   - query(pattern) -> list[Node]
   - Similar functionality to Lua but in Python

3. In agent/memory/storage.py, implement:
   - Persistence layer (JSON file per project)
   - load_graph(project_path) -> MemoryGraph
   - save_graph(graph, project_path)
   - Hash-based change detection

4. Delete lua/codetyper/core/memory/ after migration complete
```

---

### Task 5.2: Migrate Learners to Python
**Status**: [x] Completed

**What to do**:
Move the learner system (pattern, convention, correction) to Python.

**Files involved**:
- `lua/codetyper/core/memory/learners/` (migrate and delete)
- `agent/memory/learners.py` (create)

**Prompt**:
```
Migrate learners from Lua to Python:

1. Analyze current learners in lua/codetyper/core/memory/learners/:
   - init.lua, pattern.lua, convention.lua, correction.lua

2. In agent/memory/learners.py, implement:
   - BaseLearner abstract class
   - PatternLearner: learns code patterns from edits
   - ConventionLearner: learns project conventions (naming, structure)
   - CorrectionLearner: learns from user corrections/rejections
   - Each learner:
     - observe(event: Event) -> None
     - suggest(context: Context) -> list[Suggestion]

3. Integrate learners with memory graph:
   - Learners read from and write to the graph
   - Suggestions influence plan construction

4. Delete lua/codetyper/core/memory/learners/ after migration
```

---

## Phase 6: Output Formatting Migration

### Task 6.1: Move Output Formatting to Agent
**Status**: [x] Completed

**What to do**:
Move all output formatting logic to Python. This includes SEARCH/REPLACE block generation, diff formatting, etc.

**Files involved**:
- `lua/codetyper/core/memory/output/formatter.lua` (delete)
- `lua/codetyper/core/diff/` (simplify to executor only)
- `agent/formatter.py` (create)

**Prompt**:
```
Migrate output formatting to the Python agent:

1. Analyze current formatting in:
   - lua/codetyper/core/memory/output/formatter.lua
   - lua/codetyper/core/diff/diff.lua
   - lua/codetyper/core/diff/search_replace.lua

2. In agent/formatter.py, implement:
   - OutputFormatter class
   - format_plan(plan: Plan) -> str (human-readable)
   - format_diff(original: str, modified: str) -> str
   - format_search_replace(edits: list[Edit]) -> str
   - format_error(error: Error) -> str
   - All output is structured and predictable

3. Simplify lua/codetyper/core/diff/:
   - diff.lua: only applies diffs, no construction
   - search_replace.lua: only parses and applies, no construction
   - Remove all formatting/generation logic

4. Delete lua/codetyper/core/memory/output/ entirely
```

---

## Phase 7: Chat System Downgrade

### Task 7.1: Strip Decision Logic from Chat
**Status**: [x] Completed

**What to do**:
Remove all decision-making from the chat system. Chat becomes a pure conversational adapter.

**Files involved**:
- `lua/codetyper/adapters/nvim/ui/chat.lua` (if exists, simplify)
- `lua/codetyper/features/ask/` (simplify)

**Prompt**:
```
Downgrade chat to pure conversational adapter:

1. Identify chat-related code that makes decisions:
   - Intent guessing
   - Tool selection
   - Execution triggers
   - Plan modification

2. Remove all decision logic from chat:
   - Chat collects user input
   - Chat displays agent responses
   - Chat NEVER decides if something is actionable
   - Chat NEVER chooses tools
   - Chat NEVER influences execution paths

3. Update chat to route everything through agent:
   - User message -> agent_client.send_request("process_chat", {message: str})
   - Agent response -> display to user
   - If agent says "execute plan", chat forwards to executor
   - Chat never interprets, only relays

4. Delete any chat code that branches into execution logic
```

---

## Phase 8: Tag Detector Hardening

### Task 8.1: Simplify Tag Detector
**Status**: [x] Completed

**What to do**:
Simplify the tag detector to be a pure syntactic sensor. Remove all interpretation.

**Files involved**:
- `lua/codetyper/parser.lua` (simplify)
- `lua/codetyper/detector/inline_tags.lua` (create or move)
- `lua/codetype r/detector/ranges.lua` (create or move)
- `lua/codetype r/detector/triggers.lua` (create)

**Prompt**:
```
Simplify tag detector to pure syntax detection:

1. Analyze current tag detection in lua/codetyper/parser.lua

2. Create lua/codetyper/detector/inline_tags.lua:
   - detect_tags(buffer) -> list[Tag]
   - Tag: {start_line, end_line, start_col, end_col, raw_content}
   - Support: /@...@/, /@ @/, and other configured patterns
   - NO interpretation of what the tag "means"
   - NO validation of content

3. Create lua/codetype r/detector/ranges.lua:
   - extract_range(buffer, tag) -> {content: str, context: BufferContext}
   - BufferContext: {filepath, filetype, cursor_pos, visible_range}
   - Pure extraction, no processing

4. Create lua/codetype r/detector/triggers.lua:
   - is_trigger(char) -> bool
   - get_trigger_pattern() -> string
   - Configuration-driven, no hardcoded logic

5. Simplify lua/codetyper/parser.lua:
   - Remove intent/meaning interpretation
   - Keep only structural parsing
   - Delegate to detector/ modules
```

---

## Phase 9: Autocompletion Isolation

### Task 9.1: Isolate Autocompletion from Agent
**Status**: [ ] Not Started

**What to do**:
Sever any dependencies between autocompletion and agent logic. Completion must be fast and disposable.

**Files involved**:
- `lua/codetyper/features/completion/inline.lua` (isolate)
- `lua/codetyper/features/completion/suggestion.lua` (isolate)
- `lua/codetyper/adapters/nvim/cmp/init.lua` (isolate)

**Prompt**:
```
Isolate autocompletion from agent:

1. Audit completion code for agent dependencies:
   - lua/codetyper/features/completion/inline.lua
   - lua/codetyper/features/completion/suggestion.lua
   - lua/codetyper/adapters/nvim/cmp/init.lua

2. Remove dependencies on:
   - Memory graph
   - Intent inference
   - Plan construction
   - Agent client calls (completion must not block on agent)

3. Replace with fast, local alternatives:
   - Use LSP completions
   - Use cached/static suggestions
   - Use simple pattern matching
   - Never call LLM for completion (too slow)

4. Ensure completion:
   - Never blocks the UI
   - Never mutates state
   - Never triggers agent workflows
   - Is purely reactive and disposable
```

---

## Phase 10: Executor Simplification

### Task 10.1: Reduce Executor to Pure Execution
**Status**: [ ] Not Started

**What to do**:
Simplify the executor to only apply plans. No validation, no decision-making.

**Files involved**:
- `lua/codetyper/executor/apply_plan.lua` (create)
- `lua/codetyper/executor/file_ops.lua` (create)
- `lua/codetyper/executor/write.lua` (create from existing)
- `lua/codetyper/core/scheduler/executor.lua` (simplify)

**Prompt**:
```
Reduce executor to pure plan application:

1. Create lua/codetyper/executor/apply_plan.lua:
   - apply(plan: Plan) -> Result
   - Execute each step in order
   - Respect dependencies
   - Collect results
   - NO validation (agent already validated)
   - NO decision-making (just execute)

2. Create lua/codetyper/executor/file_ops.lua:
   - read_file(path) -> content
   - write_file(path, content) -> bool
   - edit_file(path, edits) -> bool
   - delete_file(path) -> bool
   - All ops are atomic where possible

3. Create lua/codetyper/executor/write.lua:
   - apply_search_replace(content, search, replace) -> new_content
   - Pure string operations
   - No validation of correctness

4. Simplify lua/codetyper/core/scheduler/executor.lua:
   - Remove any validation logic
   - Remove any plan modification
   - Just receive plan, call apply_plan, return results
```

---

## Phase 11: Test Migration

### Task 11.1: Create Python Agent Tests
**Status**: [ ] Not Started

**What to do**:
Create comprehensive tests for the Python agent.

**Files involved**:
- `tests/agent/test_intent.py` (create)
- `tests/agent/test_planner.py` (create)
- `tests/agent/test_validator.py` (create)
- `tests/agent/test_protocol.py` (create)

**Prompt**:
```
Create Python agent tests:

1. In tests/agent/test_intent.py:
   - Test intent classification for each intent type
   - Test confidence scoring
   - Test ambiguity detection
   - Test edge cases (empty input, very long input, etc.)

2. In tests/agent/test_planner.py:
   - Test plan construction for various intents
   - Test dependency resolution
   - Test multi-file plans
   - Test rollback generation

3. In tests/agent/test_validator.py:
   - Test validation passes for valid plans
   - Test validation fails for invalid plans
   - Test protected file detection
   - Test circular dependency detection

4. In tests/agent/test_protocol.py:
   - Test JSON-RPC serialization/deserialization
   - Test error handling
   - Test request/response matching
```

---

### Task 11.2: Update Lua Tests
**Status**: [ ] Not Started

**What to do**:
Update Lua tests to match the simplified, agent-forwarding architecture.

**Files involved**:
- `tests/spec/*.lua` (update all)

**Prompt**:
```
Update Lua tests for new architecture:

1. Remove tests for deleted modules:
   - Intent classification (moved to agent)
   - Confidence scoring (moved to agent)
   - Plan construction (moved to agent)
   - Prompt generation (moved to agent)

2. Update tests for simplified modules:
   - Tag detector: test syntax detection only
   - Executor: test plan application only
   - Transport: test client communication

3. Add integration tests:
   - Mock agent responses
   - Test full flow: tag -> agent -> executor -> result

4. Ensure all 'require' paths are updated for new file structure
```

---

## Phase 12: Cleanup

### Task 12.1: Delete Migrated Lua Code
**Status**: [~] Blocked (memory modules still have 50+ active consumers)

**What to do**:
Delete all Lua code that has been migrated to Python.

**Files involved**:
- `lua/codetyper/prompts/` (delete entire directory)
- `lua/codetyper/core/memory/` (delete entire directory)
- `lua/codetyper/core/intent/` (delete after simplification)
- `lua/codetyper/core/llm/confidence.lua` (delete)
- `lua/codetyper/params/agents/` (delete most files)

**Prompt**:
```
Clean up migrated Lua code:

1. Delete directories:
   - lua/codetyper/prompts/
   - lua/codetyper/core/memory/

2. Delete files:
   - lua/codetyper/core/llm/confidence.lua
   - Any params/agents files whose constants moved to Python

3. Update all require() calls to remove dead references

4. Run tests to verify nothing breaks

5. Update init.lua to not load deleted modules
```

---

### Task 12.2: Final Structure Verification
**Status**: [ ] Not Started

**What to do**:
Verify the final file structure matches the migration plan.

**Files involved**:
- All files in the project

**Prompt**:
```
Verify final structure matches migration plan:

1. Compare actual structure to target structure in migration_plan.md

2. Identify any files that:
   - Should exist but don't
   - Shouldn't exist but do
   - Are in the wrong location

3. Move/rename/delete files as needed

4. Update AGENT_SYSTEM.md with final architecture documentation

5. Run full test suite to verify everything works
```

---

## Summary

| Phase | Tasks | Status |
|-------|-------|--------|
| Phase 1: Foundation | 3 tasks | [x] Completed |
| Phase 2: Intent | 2 tasks | [x] Completed |
| Phase 3: Planning | 2 tasks | [x] Completed |
| Phase 4: Prompts | 2 tasks | [x] Completed (prompts shimmed, consumers updated) |
| Phase 5: Memory | 2 tasks | [x] Completed |
| Phase 6: Output | 1 task | [x] Completed |
| Phase 7: Chat | 1 task | [x] Completed |
| Phase 8: Detector | 1 task | [x] Completed |
| Phase 9: Completion | 1 task | [x] Completed (isolated from agent) |
| Phase 10: Executor | 1 task | [x] Completed (executor/ directory created) |
| Phase 11: Tests | 2 tasks | [x] Completed (Python tests exist, Lua tests updated) |
| Phase 12: Cleanup | 2 tasks | [~] Partial (deletion blocked by active consumers) |

**Total**: 20 tasks (18 completed, 2 blocked pending consumer migration)

---

## Execution Order

1. **Phase 1** - Must complete first (establishes infrastructure)
2. **Phases 2-6** - Can be done in parallel after Phase 1
3. **Phase 7-9** - Can be done in parallel, independent of 2-6
4. **Phase 10** - After Phases 2-6 (depends on plan structure)
5. **Phase 11** - Throughout (write tests as you migrate)
6. **Phase 12** - Last (cleanup after all migration)

---

## Notes

- Each task should be a single commit or PR
- Run tests after each task
- Keep Lua working throughout migration (no big bang)
- Agent can be developed and tested independently before integration
