# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.6.0] - 2026-01-16

### Added

- **Conflict Resolution System** - Git-style diff visualization for code review
  - New `conflict.lua` module with full conflict management
  - Git-style markers: `<<<<<<< CURRENT`, `=======`, `>>>>>>> INCOMING`
  - Visual highlighting: green for original, blue for AI suggestions
  - Buffer-local keymaps: `co` (ours), `ct` (theirs), `cb` (both), `cn` (none)
  - Navigation keymaps: `]x` (next), `[x` (previous)
  - Floating menu with `cm` or `<CR>` on conflict
  - Number keys `1-4` for quick selection in menu
  - Auto-show menu after code injection
  - Auto-show menu for next conflict after resolution
  - Commands: `:CoderConflictToggle`, `:CoderConflictMenu`, `:CoderConflictNext`, `:CoderConflictPrev`, `:CoderConflictStatus`, `:CoderConflictResolveAll`, `:CoderConflictAcceptCurrent`, `:CoderConflictAcceptIncoming`, `:CoderConflictAcceptBoth`, `:CoderConflictAcceptNone`, `:CoderConflictAutoMenu`

- **Linter Validation System** - Auto-check and fix lint errors after code injection
  - New `linter.lua` module for LSP diagnostics integration
  - Auto-saves file after code injection
  - Waits for LSP diagnostics to update
  - Detects errors and warnings in injected code region
  - Auto-queues AI fix prompts for lint errors
  - Shows errors in quickfix list
  - Commands: `:CoderLintCheck`, `:CoderLintFix`, `:CoderLintQuickfix`, `:CoderLintToggleAuto`

- **SEARCH/REPLACE Block System** - Reliable code editing with fuzzy matching
  - New `search_replace.lua` module for reliable code editing
  - Parses SEARCH/REPLACE blocks from LLM responses
  - Fuzzy matching with configurable thresholds
  - Whitespace normalization for better matching
  - Multiple matching strategies: exact, normalized, line-by-line
  - Automatic fallback to line-based injection

- **Process and Show Menu Function** - Streamlined conflict handling
  - New `process_and_show_menu()` function combines processing and menu display
  - Ensures highlights and keymaps are set up before showing menu

### Changed

- Unified automatic and manual tag processing to use same code path
- `insert_conflict()` now only inserts markers, callers handle processing
- Added `nowait = true` to conflict keymaps to prevent delay from built-in `c` command
- Improved patch application flow with conflict mode integration

### Fixed

- Fixed `string.gsub` returning two values causing `table.insert` errors
- Fixed keymaps not triggering due to Neovim's `c` command intercepting first character
- Fixed menu not showing after code injection
- Fixed diff highlighting not appearing

---

## [0.5.0] - 2026-01-15

### Added

- **Cost Tracking System** - Track LLM API costs across sessions
  - New `:CoderCost` command opens cost estimation floating window
  - Session costs tracked in real-time
  - All-time costs persisted in `.coder/cost_history.json`
  - Per-model breakdown with token counts
  - Pricing database for 50+ models (GPT-4/5, Claude, O-series, Gemini)
  - Window keymaps: `q` close, `r` refresh, `c` clear session, `C` clear all

- **Automatic Ollama Fallback** - Graceful degradation when API limits hit
  - Automatically switches to Ollama when Copilot rate limits exceeded
  - Detects local Ollama availability before fallback
  - Notifies user of provider switch

- **Enhanced Error Handling** - Better error messages for API failures
  - Shows actual API response on parse errors
  - Improved rate limit detection and messaging
  - Sanitized newlines in error notifications

- **Agent Tools System Improvements**
  - New `to_openai_format()` and `to_claude_format()` functions
  - `get_definitions()` for generic tool access
  - Fixed tool call argument serialization

- **Credentials Management System** - Store API keys outside of config files
  - New `:CoderAddApiKey` command for interactive credential setup
  - `:CoderRemoveApiKey` to remove stored credentials
  - `:CoderCredentials` to view credential status
  - `:CoderSwitchProvider` to switch active LLM provider
  - Credentials stored in `~/.local/share/nvim/codetyper/configuration.json`

### Changed

- Cost window now shows both session and all-time statistics
- Improved agent prompt templates with correct tool names
- Better error context in LLM provider responses

### Fixed

- Fixed "Failed to parse Copilot response" error showing instead of actual error
- Fixed `nvim_buf_set_lines` crash from newlines in error messages
- Fixed `tools.definitions` nil error in agent initialization
- Fixed tool name mismatch in agent prompts

---

## [0.4.0] - 2026-01-13

### Added

- **Event-Driven Architecture** - Complete rewrite of prompt processing system
  - Prompts are now treated as events with metadata
  - New modules: `queue.lua`, `patch.lua`, `confidence.lua`, `worker.lua`, `scheduler.lua`
  - Priority-based event queue with observer pattern
  - Buffer snapshots for staleness detection

- **Optimistic Execution** - Ollama as fast local scout
  - Use Ollama for first attempt (fast local inference)
  - Automatically escalate to remote LLM if confidence is low
  - Configurable escalation threshold (default: 0.7)

- **Confidence Scoring** - Response quality heuristics
  - 5 weighted heuristics: length, uncertainty, syntax, repetition, truncation
  - Scores range from 0.0-1.0
  - Determines whether to escalate to more capable LLM

- **Staleness Detection** - Safe patch application
  - Track `vim.b.changedtick` and content hash at prompt time
  - Discard patches if buffer changed during generation

- **Completion-Aware Injection** - No fighting with autocomplete
  - Defer code injection while completion popup visible
  - Works with native popup, nvim-cmp, and coq_nvim

- **Tree-sitter Scope Resolution** - Smart context extraction
  - Automatically resolves prompts to enclosing function/method/class
  - Falls back to heuristics when Tree-sitter unavailable

- **Intent Detection** - Understands what you want
  - Parses prompts to detect: complete, refactor, fix, add, document, test, optimize, explain
  - Intent determines injection strategy

### Configuration

New `scheduler` configuration block:
```lua
scheduler = {
  enabled = true,
  ollama_scout = true,
  escalation_threshold = 0.7,
  max_concurrent = 2,
  completion_delay_ms = 100,
}
```

---

## [0.3.0] - 2026-01-13

### Added

- **Multiple LLM Providers** - Support for additional providers
  - OpenAI API with custom endpoint support
  - Google Gemini API
  - GitHub Copilot

- **Agent Mode** - Autonomous coding assistant with tool use
  - `read_file`, `edit_file`, `write_file`, `bash` tools
  - Real-time logging of agent actions
  - `:CoderAgent`, `:CoderAgentToggle`, `:CoderAgentStop` commands

- **Transform Commands** - Transform /@ @/ tags inline
  - `:CoderTransform`, `:CoderTransformCursor`, `:CoderTransformVisual`
  - Default keymaps: `<leader>ctt`, `<leader>ctT`

- **Auto-Index Feature** - Automatically create coder companion files
  - Creates `.coder.` companion files when opening source files
  - Language-aware templates

- **Logs Panel** - Real-time visibility into LLM operations

- **Mode Switcher** - Switch between Ask and Agent modes

### Changed

- Window width configuration now uses percentage as whole number
- Improved code extraction from LLM responses

---

## [0.2.0] - 2026-01-11

### Added

- **Ask Panel** - Chat interface for asking questions about code
  - Fixed at 1/4 (25%) screen width
  - File attachment with `@` key
  - `Ctrl+n` to start a new chat
  - `Ctrl+Enter` to submit questions
  - `Ctrl+f` to add current file as context
  - `Y` to copy last response

### Changed

- Ask panel width is now fixed at 25%
- Improved close behavior
- Changed "Assistant" label to "AI"

### Fixed

- Ask panel window state sync issues
- Window focus returning to code after closing

---

## [0.1.0] - 2026-01-11

### Added

- Initial release of Codetyper.nvim
- Core plugin architecture with modular Lua structure
- Split window view for coder and target files
- Tag-based prompt system (`/@` to open, `@/` to close)
- Claude API integration
- Ollama API integration
- Automatic `.gitignore` management
- Smart prompt type detection
- Code injection system
- Health check module
- Project tree logging

---

## Version History

### Legend

- **Added** - New features
- **Changed** - Changes in existing functionality
- **Deprecated** - Soon-to-be removed features
- **Removed** - Removed features
- **Fixed** - Bug fixes
- **Security** - Vulnerability fixes

[Unreleased]: https://github.com/cargdev/codetyper.nvim/compare/v0.6.0...HEAD
[0.6.0]: https://github.com/cargdev/codetyper.nvim/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/cargdev/codetyper.nvim/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/cargdev/codetyper.nvim/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/cargdev/codetyper.nvim/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/cargdev/codetyper.nvim/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/cargdev/codetyper.nvim/releases/tag/v0.1.0
