# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0] - 2026-01-13

### Added

- **Event-Driven Architecture** - Complete rewrite of prompt processing system
  - Prompts are now treated as events with metadata (buffer state, priority, timestamps)
  - New modules: `queue.lua`, `patch.lua`, `confidence.lua`, `worker.lua`, `scheduler.lua`
  - Priority-based event queue with observer pattern
  - Buffer snapshots for staleness detection

- **Optimistic Execution** - Ollama as fast local scout
  - Use Ollama for first attempt (fast local inference)
  - Automatically escalate to remote LLM if confidence is low
  - Configurable escalation threshold (default: 0.7)

- **Confidence Scoring** - Response quality heuristics
  - 5 weighted heuristics: length, uncertainty phrases, syntax completeness, repetition, truncation
  - Scores range from 0.0-1.0
  - Determines whether to escalate to more capable LLM

- **Staleness Detection** - Safe patch application
  - Track `vim.b.changedtick` and content hash at prompt time
  - Discard patches if buffer changed during generation
  - Prevents stale code injection

- **Completion-Aware Injection** - No fighting with autocomplete
  - Defer code injection while completion popup visible
  - Works with native popup, nvim-cmp, and coq_nvim
  - Configurable delay after popup closes (default: 100ms)

- **Tree-sitter Scope Resolution** - Smart context extraction
  - Automatically resolves prompts to enclosing function/method/class
  - Falls back to heuristics when Tree-sitter unavailable
  - Scope types: function, method, class, block, file

- **Intent Detection** - Understands what you want
  - Parses prompts to detect: complete, refactor, fix, add, document, test, optimize, explain
  - Intent determines injection strategy (replace vs insert vs append)
  - Priority adjustment based on intent type

- **Tag Precedence Rules** - Multiple tags handled cleanly
  - First tag in scope wins (FIFO ordering)
  - Later tags in same scope skipped with warning
  - Different scopes process independently

### Configuration

New `scheduler` configuration block:
```lua
scheduler = {
  enabled = true,           -- Enable event-driven mode
  ollama_scout = true,      -- Use Ollama first
  escalation_threshold = 0.7,
  max_concurrent = 2,
  completion_delay_ms = 100,
}
```

---

## [0.3.0] - 2026-01-13

### Added

- **Multiple LLM Providers** - Support for additional providers beyond Claude and Ollama
  - OpenAI API with custom endpoint support (Azure, OpenRouter, etc.)
  - Google Gemini API
  - GitHub Copilot (uses existing copilot.lua/copilot.vim authentication)

- **Agent Mode** - Autonomous coding assistant with tool use
  - `read_file` - Read file contents
  - `edit_file` - Edit files with find/replace
  - `write_file` - Create or overwrite files
  - `bash` - Execute shell commands
  - Real-time logging of agent actions
  - `:CoderAgent`, `:CoderAgentToggle`, `:CoderAgentStop` commands

- **Transform Commands** - Transform /@ @/ tags inline without split view
  - `:CoderTransform` - Transform all tags in file
  - `:CoderTransformCursor` - Transform tag at cursor
  - `:CoderTransformVisual` - Transform selected tags
  - Default keymaps: `<leader>ctt` (cursor/visual), `<leader>ctT` (all)

- **Auto-Index Feature** - Automatically create coder companion files
  - Creates `.coder.` companion files when opening source files
  - Language-aware templates with correct comment syntax
  - `:CoderIndex` command to manually open companion
  - `<leader>ci` keymap
  - Configurable via `auto_index` option (disabled by default)

- **Logs Panel** - Real-time visibility into LLM operations
  - Token usage tracking (prompt and completion tokens)
  - "Thinking" process visibility
  - Request/response logging
  - `:CoderLogs` command to toggle panel

- **Mode Switcher** - Switch between Ask and Agent modes
  - `:CoderType` command shows mode selection UI

### Changed

- Window width configuration now uses percentage as whole number (e.g., `25` for 25%)
- Improved code extraction from LLM responses
- Better prompt templates for code generation

### Fixed

- Window width calculation consistency across modules

---

## [0.2.0] - 2026-01-11

### Added

- **Ask Panel** - Chat interface for asking questions about code
  - Fixed at 1/4 (25%) screen width for consistent layout
  - File attachment with `@` key (uses Telescope if available)
  - `Ctrl+n` to start a new chat (clears input and history)
  - `Ctrl+Enter` to submit questions
  - `Ctrl+f` to add current file as context
  - `Ctrl+h/j/k/l` for window navigation
  - `K/J` to jump between output and input windows
  - `Y` to copy last response to clipboard
  - `q` to close panel (closes both windows together)
- Auto-open Ask panel on startup (configurable via `auto_open_ask`)
- File content is now sent to LLM when attaching files with `@`

### Changed

- Ask panel width is now fixed at 25% (1/4 of screen)
- Improved close behavior - closing either Ask window closes both
- Proper focus management after closing Ask panel
- Compact UI elements to fit 1/4 width layout
- Changed "Assistant" label to "AI" in chat messages

### Fixed

- Ask panel window state sync issues
- Window focus returning to code after closing Ask panel
- NerdTree/nvim-tree causing Ask panel to resize incorrectly

---

## [0.1.0] - 2026-01-11

### Added

- Initial release of Codetyper.nvim
- Core plugin architecture with modular Lua structure
- Split window view for coder and target files
- Tag-based prompt system (`/@` to open, `@/` to close)
- Claude API integration for code generation
- Ollama API integration for local LLM support
- Automatic `.gitignore` management for coder files and `.coder/` folder
- Smart prompt type detection (refactor, add, document, explain)
- Code injection system with multiple strategies
- User commands: `Coder`, `CoderOpen`, `CoderClose`, `CoderToggle`, `CoderProcess`, `CoderTree`, `CoderTreeView`
- Health check module (`:checkhealth codetyper`)
- Comprehensive documentation and help files
- Telescope integration for file selection (optional)
- **Project tree logging**: Automatic `.coder/tree.log` maintenance
  - Updates on file create, save, delete
  - Debounced updates (1 second) for performance
  - File type icons for visual clarity
  - Ignores common build/dependency folders

### Configuration Options

- LLM provider selection (Claude/Ollama)
- Window position and width customization
- Custom prompt tag patterns
- Auto gitignore toggle

---

## Version History

### Legend

- **Added** - New features
- **Changed** - Changes in existing functionality
- **Deprecated** - Soon-to-be removed features
- **Removed** - Removed features
- **Fixed** - Bug fixes
- **Security** - Vulnerability fixes

[Unreleased]: https://github.com/cargdev/codetyper.nvim/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/cargdev/codetyper.nvim/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/cargdev/codetyper.nvim/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/cargdev/codetyper.nvim/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/cargdev/codetyper.nvim/releases/tag/v0.1.0
