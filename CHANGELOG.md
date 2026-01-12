# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Improved code generation prompts to explicitly request only raw code output (no explanations, markdown, or code fences)

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

[Unreleased]: https://github.com/cargdev/codetyper.nvim/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/cargdev/codetyper.nvim/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/cargdev/codetyper.nvim/releases/tag/v0.1.0
