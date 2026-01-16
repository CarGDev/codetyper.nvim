# Codetyper.nvim

**AI-powered coding partner for Neovim** - Write code faster with LLM assistance while staying in control of your logic.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Neovim](https://img.shields.io/badge/Neovim-0.8%2B-green.svg)](https://neovim.io/)

## Features

- **Split View**: Work with your code and prompts side by side
- **Ask Panel**: Chat interface for questions and explanations
- **Agent Mode**: Autonomous coding agent with tool use (read, edit, write, bash)
- **Tag-based Prompts**: Use `/@` and `@/` tags to write natural language prompts
- **Transform Commands**: Transform prompts inline without leaving your file
- **Multiple LLM Providers**: Claude, OpenAI, Gemini, Copilot, and Ollama (local)
- **SEARCH/REPLACE Blocks**: Reliable code editing with fuzzy matching
- **Conflict Resolution**: Git-style diff visualization with interactive resolution
- **Linter Validation**: Auto-check and fix lint errors after code injection
- **Event-Driven Scheduler**: Queue-based processing with optimistic execution
- **Tree-sitter Scope Resolution**: Smart context extraction for functions/methods
- **Intent Detection**: Understands complete, refactor, fix, add, document intents
- **Confidence Scoring**: Automatic escalation from local to remote LLMs
- **Completion-Aware**: Safe injection that doesn't fight with autocomplete
- **Auto-Index**: Automatically create coder companion files on file open
- **Logs Panel**: Real-time visibility into LLM requests and token usage
- **Cost Tracking**: Persistent LLM cost estimation with session and all-time stats
- **Git Integration**: Automatically adds `.coder.*` files to `.gitignore`
- **Project Tree Logging**: Maintains a `tree.log` tracking your project structure
- **Brain System**: Knowledge graph that learns from your coding patterns

---

## Table of Contents

- [Requirements](#requirements)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [LLM Providers](#llm-providers)
- [Commands Reference](#commands-reference)
- [Keymaps Reference](#keymaps-reference)
- [Usage Guide](#usage-guide)
- [Conflict Resolution](#conflict-resolution)
- [Linter Validation](#linter-validation)
- [Logs Panel](#logs-panel)
- [Cost Tracking](#cost-tracking)
- [Agent Mode](#agent-mode)
- [Health Check](#health-check)
- [Reporting Issues](#reporting-issues)

---

## Requirements

- Neovim >= 0.8.0
- curl (for API calls)
- One of: Claude API key, OpenAI API key, Gemini API key, GitHub Copilot, or Ollama running locally

### Required Plugins

- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) - Async utilities
- [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) - Scope detection for functions/methods

### Optional Plugins

- [nvim-treesitter-textobjects](https://github.com/nvim-treesitter/nvim-treesitter-textobjects) - Better text object support
- [nui.nvim](https://github.com/MunifTanjim/nui.nvim) - UI components

---

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "cargdev/codetyper.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter",
    "nvim-treesitter/nvim-treesitter-textobjects",
    "MunifTanjim/nui.nvim",
  },
  cmd = { "Coder", "CoderOpen", "CoderToggle", "CoderAgent" },
  keys = {
    { "<leader>co", "<cmd>Coder open<cr>", desc = "Coder: Open" },
    { "<leader>ct", "<cmd>Coder toggle<cr>", desc = "Coder: Toggle" },
    { "<leader>ca", "<cmd>CoderAgentToggle<cr>", desc = "Coder: Agent" },
  },
  config = function()
    require("codetyper").setup({
      llm = {
        provider = "claude", -- or "openai", "gemini", "copilot", "ollama"
      },
    })
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "cargdev/codetyper.nvim",
  config = function()
    require("codetyper").setup()
  end,
}
```

---

## Quick Start

**1. Open a file and start Coder:**
```vim
:e src/utils.ts
:Coder open
```

**2. Write a prompt in the coder file (left panel):**
```typescript
/@ Create a function to validate email addresses
using regex, return boolean @/
```

**3. The LLM generates code and shows a diff for you to review**

**4. Use conflict resolution keymaps to accept/reject changes:**
- `ct` - Accept AI suggestion (theirs)
- `co` - Keep original code (ours)
- `cb` - Accept both versions
- `cn` - Delete both (none)

---

## Configuration

```lua
require("codetyper").setup({
  -- LLM Provider Configuration
  llm = {
    provider = "claude", -- "claude", "openai", "gemini", "copilot", or "ollama"

    claude = {
      api_key = nil, -- Uses ANTHROPIC_API_KEY env var if nil
      model = "claude-sonnet-4-20250514",
    },

    openai = {
      api_key = nil, -- Uses OPENAI_API_KEY env var if nil
      model = "gpt-4o",
      endpoint = nil, -- Custom endpoint (Azure, OpenRouter, etc.)
    },

    gemini = {
      api_key = nil, -- Uses GEMINI_API_KEY env var if nil
      model = "gemini-2.0-flash",
    },

    copilot = {
      model = "gpt-4o",
    },

    ollama = {
      host = "http://localhost:11434",
      model = "deepseek-coder:6.7b",
    },
  },

  -- Window Configuration
  window = {
    width = 25, -- Percentage of screen width
    position = "left",
    border = "rounded",
  },

  -- Prompt Tag Patterns
  patterns = {
    open_tag = "/@",
    close_tag = "@/",
    file_pattern = "*.coder.*",
  },

  -- Auto Features
  auto_gitignore = true,
  auto_open_ask = true,
  auto_index = false,

  -- Event-Driven Scheduler
  scheduler = {
    enabled = true,
    ollama_scout = true,
    escalation_threshold = 0.7,
    max_concurrent = 2,
    completion_delay_ms = 100,
    apply_delay_ms = 5000,
  },
})
```

### Environment Variables

| Variable | Description |
|----------|-------------|
| `ANTHROPIC_API_KEY` | Claude API key |
| `OPENAI_API_KEY` | OpenAI API key |
| `GEMINI_API_KEY` | Google Gemini API key |

### Credentials Management

Store API keys securely outside of config files:

```vim
:CoderAddApiKey
```

Credentials are stored in `~/.local/share/nvim/codetyper/configuration.json`.

**Priority order:**
1. Stored credentials (via `:CoderAddApiKey`)
2. Config file settings
3. Environment variables

---

## LLM Providers

### Claude
```lua
llm = {
  provider = "claude",
  claude = { model = "claude-sonnet-4-20250514" },
}
```

### OpenAI
```lua
llm = {
  provider = "openai",
  openai = {
    model = "gpt-4o",
    endpoint = "https://api.openai.com/v1/chat/completions",
  },
}
```

### Google Gemini
```lua
llm = {
  provider = "gemini",
  gemini = { model = "gemini-2.0-flash" },
}
```

### GitHub Copilot
```lua
llm = {
  provider = "copilot",
  copilot = { model = "gpt-4o" },
}
```

### Ollama (Local)
```lua
llm = {
  provider = "ollama",
  ollama = {
    host = "http://localhost:11434",
    model = "deepseek-coder:6.7b",
  },
}
```

---

## Commands Reference

### Core Commands

| Command | Alias | Description |
|---------|-------|-------------|
| `:Coder open` | `:CoderOpen` | Open the coder split view |
| `:Coder close` | `:CoderClose` | Close the coder split view |
| `:Coder toggle` | `:CoderToggle` | Toggle the coder split view |
| `:Coder process` | `:CoderProcess` | Process the last prompt |
| `:Coder status` | - | Show plugin status |
| `:Coder focus` | - | Switch focus between windows |
| `:Coder reset` | - | Reset processed prompts |

### Ask Panel

| Command | Alias | Description |
|---------|-------|-------------|
| `:Coder ask` | `:CoderAsk` | Open the Ask panel |
| `:Coder ask-toggle` | `:CoderAskToggle` | Toggle the Ask panel |
| `:Coder ask-clear` | `:CoderAskClear` | Clear chat history |

### Agent Mode

| Command | Alias | Description |
|---------|-------|-------------|
| `:Coder agent` | `:CoderAgent` | Open the Agent panel |
| `:Coder agent-toggle` | `:CoderAgentToggle` | Toggle the Agent panel |
| `:Coder agent-stop` | `:CoderAgentStop` | Stop running agent |

### Agentic Mode

| Command | Alias | Description |
|---------|-------|-------------|
| `:Coder agentic-run <task>` | `:CoderAgenticRun` | Run agentic task |
| `:Coder agentic-list` | `:CoderAgenticList` | List available agents |
| `:Coder agentic-init` | `:CoderAgenticInit` | Initialize .coder/agents/ |

### Transform Commands

| Command | Alias | Description |
|---------|-------|-------------|
| `:Coder transform` | `:CoderTransform` | Transform all tags in file |
| `:Coder transform-cursor` | `:CoderTransformCursor` | Transform tag at cursor |
| - | `:CoderTransformVisual` | Transform selected tags |

### Conflict Resolution

| Command | Description |
|---------|-------------|
| `:CoderConflictToggle` | Toggle conflict mode |
| `:CoderConflictMenu` | Show resolution menu |
| `:CoderConflictNext` | Go to next conflict |
| `:CoderConflictPrev` | Go to previous conflict |
| `:CoderConflictStatus` | Show conflict status |
| `:CoderConflictResolveAll [keep]` | Resolve all (ours/theirs/both/none) |
| `:CoderConflictAcceptCurrent` | Accept original code |
| `:CoderConflictAcceptIncoming` | Accept AI suggestion |
| `:CoderConflictAcceptBoth` | Accept both versions |
| `:CoderConflictAcceptNone` | Delete both |
| `:CoderConflictAutoMenu` | Toggle auto-show menu |

### Linter Validation

| Command | Description |
|---------|-------------|
| `:CoderLintCheck` | Check buffer for lint errors |
| `:CoderLintFix` | Request AI to fix lint errors |
| `:CoderLintQuickfix` | Show errors in quickfix |
| `:CoderLintToggleAuto` | Toggle auto lint checking |

### Queue & Scheduler

| Command | Alias | Description |
|---------|-------|-------------|
| `:Coder queue-status` | `:CoderQueueStatus` | Show scheduler status |
| `:Coder queue-process` | `:CoderQueueProcess` | Trigger queue processing |

### Processing Mode

| Command | Alias | Description |
|---------|-------|-------------|
| `:Coder auto-toggle` | `:CoderAutoToggle` | Toggle auto/manual mode |
| `:Coder auto-set <mode>` | `:CoderAutoSet` | Set mode (auto/manual) |

### Brain & Memory

| Command | Description |
|---------|-------------|
| `:CoderMemories` | Show learned memories |
| `:CoderForget [pattern]` | Clear memories |
| `:CoderBrain [action]` | Brain management (stats/commit/flush/prune) |
| `:CoderFeedback <type>` | Give feedback (good/bad/stats) |

### Cost & Credentials

| Command | Description |
|---------|-------------|
| `:CoderCost` | Show cost estimation window |
| `:CoderAddApiKey` | Add/update API key |
| `:CoderRemoveApiKey` | Remove credentials |
| `:CoderCredentials` | Show credentials status |
| `:CoderSwitchProvider` | Switch LLM provider |

### UI Commands

| Command | Description |
|---------|-------------|
| `:CoderLogs` | Toggle logs panel |
| `:CoderType` | Show Ask/Agent switcher |

---

## Keymaps Reference

### Default Keymaps (auto-configured)

| Key | Mode | Description |
|-----|------|-------------|
| `<leader>ctt` | Normal | Transform tag at cursor |
| `<leader>ctt` | Visual | Transform selected tags |
| `<leader>ctT` | Normal | Transform all tags in file |
| `<leader>ca` | Normal | Toggle Agent panel |
| `<leader>ci` | Normal | Open coder companion |

### Conflict Resolution Keymaps (buffer-local when conflicts exist)

| Key | Description |
|-----|-------------|
| `co` | Accept CURRENT (original) code |
| `ct` | Accept INCOMING (AI suggestion) |
| `cb` | Accept BOTH versions |
| `cn` | Delete conflict (accept NONE) |
| `cm` | Show conflict resolution menu |
| `]x` | Go to next conflict |
| `[x` | Go to previous conflict |
| `<CR>` | Show menu when on conflict |

### Conflict Menu Keymaps (in floating menu)

| Key | Description |
|-----|-------------|
| `1` | Accept current (original) |
| `2` | Accept incoming (AI) |
| `3` | Accept both |
| `4` | Accept none |
| `co` | Accept current |
| `ct` | Accept incoming |
| `cb` | Accept both |
| `cn` | Accept none |
| `]x` | Go to next conflict |
| `[x` | Go to previous conflict |
| `q` / `<Esc>` | Close menu |

### Ask Panel Keymaps

| Key | Description |
|-----|-------------|
| `@` | Attach/reference a file |
| `Ctrl+Enter` | Submit question |
| `Ctrl+n` | Start new chat |
| `Ctrl+f` | Add current file as context |
| `q` | Close panel |
| `Y` | Copy last response |

### Agent Panel Keymaps

| Key | Description |
|-----|-------------|
| `<CR>` | Submit message |
| `Ctrl+c` | Stop agent execution |
| `q` | Close agent panel |

### Logs Panel Keymaps

| Key | Description |
|-----|-------------|
| `q` / `<Esc>` | Close logs panel |

### Cost Window Keymaps

| Key | Description |
|-----|-------------|
| `q` / `<Esc>` | Close window |
| `r` | Refresh display |
| `c` | Clear session costs |
| `C` | Clear all history |

### Suggested Additional Keymaps

```lua
local map = vim.keymap.set

map("n", "<leader>co", "<cmd>Coder open<cr>", { desc = "Coder: Open" })
map("n", "<leader>cc", "<cmd>Coder close<cr>", { desc = "Coder: Close" })
map("n", "<leader>ct", "<cmd>Coder toggle<cr>", { desc = "Coder: Toggle" })
map("n", "<leader>cp", "<cmd>Coder process<cr>", { desc = "Coder: Process" })
map("n", "<leader>cs", "<cmd>Coder status<cr>", { desc = "Coder: Status" })
map("n", "<leader>cl", "<cmd>CoderLogs<cr>", { desc = "Coder: Logs" })
map("n", "<leader>cm", "<cmd>CoderConflictMenu<cr>", { desc = "Coder: Conflict Menu" })
```

---

## Usage Guide

### Tag-Based Prompts

Write prompts using `/@` and `@/` tags:

```typescript
/@ Create a Button component with:
- variant: 'primary' | 'secondary' | 'danger'
- size: 'sm' | 'md' | 'lg'
Use Tailwind CSS for styling @/
```

### Prompt Types

| Keywords | Type | Behavior |
|----------|------|----------|
| `complete`, `finish`, `implement` | Complete | Replaces scope |
| `refactor`, `rewrite`, `simplify` | Refactor | Replaces code |
| `fix`, `debug`, `bug`, `error` | Fix | Fixes bugs |
| `add`, `create`, `generate` | Add | Inserts new code |
| `document`, `comment`, `jsdoc` | Document | Adds docs |
| `explain`, `what`, `how` | Explain | Shows explanation |

### Function Completion

When you write a prompt inside a function, the plugin detects the enclosing scope:

```typescript
function getUserById(id: number): User | null {
  /@ return the user from the database by id @/
}
```

---

## Conflict Resolution

When code is generated, it's shown as a git-style conflict for you to review:

```
<<<<<<< CURRENT
// Original code here
=======
// AI-generated code here
>>>>>>> INCOMING
```

### Visual Indicators

- **Green background**: Original (CURRENT) code
- **Blue background**: AI-generated (INCOMING) code
- **Virtual text hints**: Shows available keymaps

### Resolution Options

1. **Accept Current (`co`)**: Keep your original code
2. **Accept Incoming (`ct`)**: Use the AI suggestion
3. **Accept Both (`cb`)**: Keep both versions
4. **Accept None (`cn`)**: Delete the entire conflict

### Auto-Show Menu

When code is injected, a floating menu automatically appears. After resolving a conflict, the menu shows again for the next conflict.

Toggle auto-show: `:CoderConflictAutoMenu`

---

## Linter Validation

After accepting AI suggestions (`ct` or `cb`), the plugin:

1. **Saves the file** automatically
2. **Checks LSP diagnostics** for errors/warnings
3. **Offers to fix** lint errors with AI

### Configuration

```lua
-- In conflict.lua config
lint_after_accept = true,      -- Check linter after accepting
auto_fix_lint_errors = true,   -- Auto-queue fix without prompting
```

### Manual Commands

- `:CoderLintCheck` - Check current buffer
- `:CoderLintFix` - Queue AI fix for errors
- `:CoderLintQuickfix` - Show in quickfix list

---

## Logs Panel

Real-time visibility into LLM operations:

```vim
:CoderLogs
```

Shows:
- Generation requests and responses
- Token usage
- Queue status
- Errors and warnings

---

## Cost Tracking

Track LLM API costs across sessions:

```vim
:CoderCost
```

Features:
- Session and all-time statistics
- Per-model breakdown
- Pricing for 50+ models
- Persistent history in `.coder/cost_history.json`

---

## Agent Mode

Autonomous coding assistant with tool access:

### Available Tools

- **read_file**: Read file contents
- **edit_file**: Edit files with find/replace
- **write_file**: Create or overwrite files
- **bash**: Execute shell commands

### Using Agent Mode

1. Open: `:CoderAgent` or `<leader>ca`
2. Describe your task
3. Agent uses tools autonomously
4. Review changes in conflict mode

---

## Health Check

```vim
:checkhealth codetyper
```

---

## File Structure

```
your-project/
├── .coder/
│   ├── tree.log
│   ├── cost_history.json
│   ├── brain/
│   ├── agents/
│   └── rules/
├── src/
│   ├── index.ts
│   └── index.coder.ts
└── .gitignore
```

---

## Reporting Issues

Found a bug or have a feature request? Please create an issue on GitHub.

### Before Creating an Issue

1. **Search existing issues** to avoid duplicates
2. **Update to the latest version** and check if the issue persists
3. **Run health check**: `:checkhealth codetyper`

### Bug Reports

When reporting a bug, please include:

```markdown
**Description**
A clear description of what the bug is.

**Steps to Reproduce**
1. Open file '...'
2. Run command '...'
3. See error

**Expected Behavior**
What you expected to happen.

**Actual Behavior**
What actually happened.

**Environment**
- Neovim version: (output of `nvim --version`)
- Plugin version: (commit hash or tag)
- OS: (e.g., macOS 14.0, Ubuntu 22.04)
- LLM Provider: (e.g., Claude, OpenAI, Ollama)

**Error Messages**
Paste any error messages from `:messages`

**Minimal Config**
If possible, provide a minimal config to reproduce:
```lua
-- minimal.lua
require("codetyper").setup({
  llm = { provider = "..." },
})
```
```

### Feature Requests

For feature requests, please describe:

- **Use case**: What problem does this solve?
- **Proposed solution**: How should it work?
- **Alternatives**: Other solutions you've considered

### Debug Information

To gather debug information:

```vim
" Check plugin status
:Coder status

" View logs
:CoderLogs

" Check health
:checkhealth codetyper

" View recent messages
:messages
```

### Issue Labels

- `bug` - Something isn't working
- `enhancement` - New feature request
- `documentation` - Documentation improvements
- `question` - General questions
- `help wanted` - Issues that need community help

---

## Contributing

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md).

---

## License

MIT License - see [LICENSE](LICENSE).

---

## Author

**cargdev**

- Website: [cargdev.io](https://cargdev.io)
- Email: carlos.gutierrez@carg.dev

---

<p align="center">
  Made with care for the Neovim community
</p>
