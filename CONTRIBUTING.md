# Contributing to Codetyper.nvim

Thank you for considering contributing to Codetyper.nvim!

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Project Structure](#project-structure)
- [Making Changes](#making-changes)
- [Submitting Changes](#submitting-changes)
- [Style Guide](#style-guide)
- [Testing](#testing)
- [Questions](#questions)

## Code of Conduct

This project and everyone participating in it is governed by our commitment to creating a welcoming and inclusive environment. Please be respectful and constructive in all interactions.

## Getting Started

1. Fork the repository
2. Clone your fork locally
3. Set up the development environment
4. Create a branch for your changes
5. Make your changes
6. Submit a pull request

## Development Setup

### Prerequisites

- Neovim >= 0.8.0
- Lua 5.1+ or LuaJIT
- Git
- One of: GitHub Copilot (via copilot.lua/copilot.vim) or Ollama

### Local Development

1. Clone the repository:
   ```bash
   git clone https://github.com/CarGDev/codetyper.nvim.git
   cd codetyper.nvim
   ```

2. Create a minimal test configuration:
   ```lua
   -- tests/minimal_init.lua
   vim.opt.runtimepath:append(".")
   require("codetyper").setup({
     llm = {
       provider = "ollama",
     },
   })
   ```

3. Test your changes:
   ```bash
   nvim --clean -u tests/minimal_init.lua
   ```

4. Run the full test suite:
   ```bash
   make test
   ```

## Project Structure

```
codetyper.nvim/
├── lua/codetyper/
│   ├── init.lua                         # Entry point, setup()
│   ├── inject.lua                       # Code injection into buffers
│   ├── parser.lua                       # /@ @/ tag parser
│   ├── types.lua                        # Lua type annotations
│   │
│   ├── config/
│   │   ├── defaults.lua                 # Default configuration values
│   │   ├── credentials.lua              # Credential & model storage
│   │   └── preferences.lua              # User preference persistence
│   │
│   ├── adapters/nvim/
│   │   ├── autocmds.lua                 # Autocommands (prompt processing)
│   │   ├── commands.lua                 # All :Coder* user commands
│   │   ├── cmp/init.lua                 # nvim-cmp source integration
│   │   └── ui/
│   │       ├── thinking.lua             # Status window ("Thinking...")
│   │       ├── throbber.lua             # Animated spinner
│   │       ├── logs.lua                 # Internal log viewer
│   │       ├── logs_panel.lua           # Standalone logs panel
│   │       ├── context_modal.lua        # File-context picker
│   │       └── diff_review.lua          # Side-by-side diff review
│   │
│   ├── core/
│   │   ├── transform.lua                # Visual selection -> prompt -> apply
│   │   ├── marks.lua                    # Extmark tracking for injection
│   │   ├── thinking_placeholder.lua     # Inline virtual text status
│   │   ├── scope/init.lua              # Tree-sitter + indent scope
│   │   ├── intent/init.lua             # Prompt intent classifier
│   │   ├── llm/
│   │   │   ├── init.lua                 # Provider dispatcher
│   │   │   ├── copilot.lua              # GitHub Copilot client
│   │   │   ├── ollama.lua               # Ollama client (local)
│   │   │   ├── confidence.lua           # Response confidence scoring
│   │   │   └── selector.lua             # Provider selection logic
│   │   ├── diff/
│   │   │   ├── diff.lua                 # Diff utilities
│   │   │   ├── patch.lua                # Patch generation + staleness
│   │   │   ├── conflict.lua             # Git-style conflict resolution
│   │   │   └── search_replace.lua       # SEARCH/REPLACE block parser
│   │   ├── events/queue.lua             # Priority event queue
│   │   ├── scheduler/
│   │   │   ├── scheduler.lua            # Event dispatch orchestrator
│   │   │   ├── worker.lua               # Async LLM worker
│   │   │   ├── executor.lua             # Tool execution
│   │   │   ├── loop.lua                 # Processing loop
│   │   │   └── resume.lua               # Session resume
│   │   ├── cost/init.lua               # Token usage + cost estimation
│   │   └── memory/                      # Knowledge graph & pattern learning
│   │
│   ├── features/
│   │   ├── completion/                  # Inline completion & suggestions
│   │   └── indexer/                     # Project indexing & analysis
│   │
│   ├── support/
│   │   ├── utils.lua                    # General utilities
│   │   ├── logger.lua                   # Logging system
│   │   ├── tree.lua                     # Project tree generator
│   │   ├── health.lua                   # :checkhealth provider
│   │   ├── gitignore.lua                # .gitignore management
│   │   └── langmap.lua                  # Language detection
│   │
│   ├── params/agents/                   # Config tables for subsystems
│   └── prompts/                         # System & agent prompts
│
├── plugin/codetyper.lua                 # Plugin loader
├── doc/codetyper.txt                    # Vim help documentation
├── doc/tags                             # Help tags
├── tests/                               # Test suite
├── Makefile                             # Build/test/lint targets
├── README.md
├── CHANGELOG.md
├── CONTRIBUTING.md
├── LICENSE
└── llms.txt                             # LLM context documentation
```

## Making Changes

### Branch Naming

Use descriptive branch names:
- `feature/description` — New features
- `fix/description` — Bug fixes
- `docs/description` — Documentation updates
- `refactor/description` — Code refactoring

### Commit Messages

Follow conventional commits:
```
type(scope): description

[optional body]

[optional footer]
```

Types:
- `feat` — New feature
- `fix` — Bug fix
- `docs` — Documentation
- `style` — Formatting, no code change
- `refactor` — Code restructuring
- `test` — Adding tests
- `chore` — Maintenance

Examples:
```
feat(scope): add indentation-based fallback for scope resolution
fix(patch): handle missing if-wrapper in SEARCH/REPLACE block
docs(readme): update commands reference for current state
```

## Submitting Changes

1. Ensure your code follows the style guide
2. Update documentation if needed
3. Update `CHANGELOG.md` for notable changes
4. Test your changes thoroughly
5. Create a pull request with:
   - Clear title describing the change
   - Description of what and why
   - Reference to any related issues

### Pull Request Template

```markdown
## Description
[Describe your changes]

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Documentation update
- [ ] Refactoring

## Testing
[Describe how you tested your changes]

## Checklist
- [ ] Code follows style guide
- [ ] Documentation updated
- [ ] CHANGELOG.md updated
- [ ] All tests pass
```

## Style Guide

### Lua Style

- Use tabs for indentation
- Use `snake_case` for variables and functions
- Use `PascalCase` for module names
- Add type annotations with `---@param`, `---@return`, etc.
- Document public functions with LuaDoc comments
- Avoid obvious/redundant comments

```lua
---@mod module_name Module description

local M = {}

--- Description of the function
---@param name string The parameter description
---@return boolean
function M.example_function(name)
  return true
end

return M
```

### Documentation

- Keep `README.md` up to date
- Update `doc/codetyper.txt` for new features
- Regenerate `doc/tags` after help file changes
- Use clear, concise language
- Include examples where helpful

## Testing

### Running Tests

```bash
make test              # Run all tests
make test-file F=x     # Run a specific test file
make test-verbose      # Verbose output
make lint              # Run luacheck
make format            # Format with stylua
```

### Manual Testing

1. Test all commands work correctly
2. Test with different file types
3. Test LLM integration (Copilot and Ollama)
4. Test edge cases (empty files, large files, no Tree-sitter, etc.)
5. Run `:checkhealth codetyper`

## Questions?

Feel free to:
- Open an issue for bugs or feature requests
- Start a discussion for questions
- Reach out to the maintainer

## Contact

- **Maintainer**: cargdev
- **Email**: carlos.gutierrez@carg.dev
- **Website**: [cargdev.io](https://cargdev.io)

---

Thank you for contributing!
