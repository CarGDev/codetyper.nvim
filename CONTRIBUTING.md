# Contributing to Codetyper.nvim

First off, thank you for considering contributing to Codetyper.nvim! 🎉

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

### Local Development

1. Clone the repository:
   ```bash
   git clone https://github.com/YOUR_USERNAME/codetyper.nvim.git
   cd codetyper.nvim
   ```

2. Create a minimal test configuration:
   ```lua
   -- test/minimal_init.lua
   vim.opt.runtimepath:append(".")
   require("codetyper").setup({
     llm = {
       provider = "ollama", -- Use local for testing
     },
   })
   ```

3. Test your changes:
   ```bash
   nvim --clean -u test/minimal_init.lua
   ```

## Project Structure

```
codetyper.nvim/
├── lua/
│   └── codetyper/
│       ├── init.lua          # Main entry point
│       ├── config.lua        # Configuration management
│       ├── types.lua         # Type definitions
│       ├── utils.lua         # Utility functions
│       ├── commands.lua      # Command definitions
│       ├── window.lua        # Window/split management
│       ├── parser.lua        # Prompt tag parser
│       ├── gitignore.lua     # .gitignore management
│       ├── autocmds.lua      # Autocommands
│       ├── inject.lua        # Code injection
│       ├── health.lua        # Health check
│       └── llm/
│           ├── init.lua      # LLM interface
│           ├── claude.lua    # Claude API client
│           └── ollama.lua    # Ollama API client
├── plugin/
│   └── codetyper.lua         # Plugin loader
├── doc/
│   └── codetyper.txt         # Vim help documentation
├── README.md
├── LICENSE
├── CHANGELOG.md
├── CONTRIBUTING.md
└── llms.txt
```

## Making Changes

### Branch Naming

Use descriptive branch names:
- `feature/description` - New features
- `fix/description` - Bug fixes
- `docs/description` - Documentation updates
- `refactor/description` - Code refactoring

### Commit Messages

Follow conventional commits:
```
type(scope): description

[optional body]

[optional footer]
```

Types:
- `feat` - New feature
- `fix` - Bug fix
- `docs` - Documentation
- `style` - Formatting, no code change
- `refactor` - Code restructuring
- `test` - Adding tests
- `chore` - Maintenance

Examples:
```
feat(llm): add support for GPT-4 API
fix(parser): handle nested prompt tags
docs(readme): update installation instructions
```

## Submitting Changes

1. **Ensure your code follows the style guide**
2. **Update documentation** if needed
3. **Update CHANGELOG.md** for notable changes
4. **Test your changes** thoroughly
5. **Create a pull request** with:
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

- Use 2 spaces for indentation
- Use `snake_case` for variables and functions
- Use `PascalCase` for module names
- Add type annotations with `---@param`, `---@return`, etc.
- Document public functions with LuaDoc comments

```lua
---@mod module_name Module description

local M = {}

--- Description of the function
---@param name string The parameter description
---@return boolean Success status
function M.example_function(name)
  -- Implementation
  return true
end

return M
```

### Documentation

- Keep README.md up to date
- Update doc/codetyper.txt for new features
- Use clear, concise language
- Include examples where helpful

## Testing

### Manual Testing

1. Test all commands work correctly
2. Test with different file types
3. Test window management
4. Test LLM integration (both Claude and Ollama)
5. Test edge cases (empty files, large files, etc.)

### Health Check

Run `:checkhealth codetyper` to verify the plugin setup.

## Questions?

Feel free to:
- Open an issue for bugs or feature requests
- Start a discussion for questions
- Reach out to the maintainer

## Contact

- **Maintainer**: cargdev
- **Email**: carlos.gutierrez@carg.dev
- **Website**: [cargdev.io](https://cargdev.io)
- **Blog**: [blog.cargdev.io](https://blog.cargdev.io)

---

Thank you for contributing! 🙏
