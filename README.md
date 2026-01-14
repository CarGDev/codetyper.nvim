# 🚀 Codetyper.nvim

**AI-powered coding partner for Neovim** - Write code faster with LLM assistance while staying in control of your logic.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Neovim](https://img.shields.io/badge/Neovim-0.8%2B-green.svg)](https://neovim.io/)

## ✨ Features

- 📐 **Split View**: Work with your code and prompts side by side
- 💬 **Ask Panel**: Chat interface for questions and explanations
- 🤖 **Agent Mode**: Autonomous coding agent with tool use (read, edit, write, bash)
- 🏷️ **Tag-based Prompts**: Use `/@` and `@/` tags to write natural language prompts
- ⚡ **Transform Commands**: Transform prompts inline without leaving your file
- 🔌 **Multiple LLM Providers**: Claude, OpenAI, Gemini, Copilot, and Ollama (local)
- 📋 **Event-Driven Scheduler**: Queue-based processing with optimistic execution
- 🎯 **Tree-sitter Scope Resolution**: Smart context extraction for functions/methods
- 🧠 **Intent Detection**: Understands complete, refactor, fix, add, document intents
- 📊 **Confidence Scoring**: Automatic escalation from local to remote LLMs
- 🛡️ **Completion-Aware**: Safe injection that doesn't fight with autocomplete
- 📁 **Auto-Index**: Automatically create coder companion files on file open
- 📜 **Logs Panel**: Real-time visibility into LLM requests and token usage
- 🔒 **Git Integration**: Automatically adds `.coder.*` files to `.gitignore`
- 🌳 **Project Tree Logging**: Maintains a `tree.log` tracking your project structure

---

## 📚 Table of Contents

- [Requirements](#-requirements)
- [Installation](#-installation)
- [Quick Start](#-quick-start)
- [Configuration](#-configuration)
- [LLM Providers](#-llm-providers)
- [Commands Reference](#-commands-reference)
- [Usage Guide](#-usage-guide)
- [Agent Mode](#-agent-mode)
- [Keymaps](#-keymaps)
- [Health Check](#-health-check)

---

## 📋 Requirements

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

## 📦 Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "cargdev/codetyper.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim", -- Required: async utilities
    "nvim-treesitter/nvim-treesitter", -- Required: scope detection
    "nvim-treesitter/nvim-treesitter-textobjects", -- Optional: text objects
    "MunifTanjim/nui.nvim", -- Optional: UI components
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

## 🚀 Quick Start

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

**3. The LLM generates code and injects it into `utils.ts` (right panel)**

---

## ⚙️ Configuration

```lua
require("codetyper").setup({
  -- LLM Provider Configuration
  llm = {
    provider = "claude", -- "claude", "openai", "gemini", "copilot", or "ollama"

    -- Claude (Anthropic) settings
    claude = {
      api_key = nil, -- Uses ANTHROPIC_API_KEY env var if nil
      model = "claude-sonnet-4-20250514",
    },

    -- OpenAI settings
    openai = {
      api_key = nil, -- Uses OPENAI_API_KEY env var if nil
      model = "gpt-4o",
      endpoint = nil, -- Custom endpoint (Azure, OpenRouter, etc.)
    },

    -- Google Gemini settings
    gemini = {
      api_key = nil, -- Uses GEMINI_API_KEY env var if nil
      model = "gemini-2.0-flash",
    },

    -- GitHub Copilot settings (uses copilot.lua/copilot.vim auth)
    copilot = {
      model = "gpt-4o",
    },

    -- Ollama (local) settings
    ollama = {
      host = "http://localhost:11434",
      model = "deepseek-coder:6.7b",
    },
  },

  -- Window Configuration
  window = {
    width = 25, -- Percentage of screen width (25 = 25%)
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
  auto_gitignore = true, -- Automatically add coder files to .gitignore
  auto_open_ask = true, -- Auto-open Ask panel on startup
  auto_index = false, -- Auto-create coder companion files on file open

  -- Event-Driven Scheduler
  scheduler = {
    enabled = true, -- Enable event-driven prompt processing
    ollama_scout = true, -- Use Ollama for first attempt (fast local)
    escalation_threshold = 0.7, -- Below this confidence, escalate to remote
    max_concurrent = 2, -- Max parallel workers
    completion_delay_ms = 100, -- Delay injection after completion popup
    apply_delay_ms = 5000, -- Wait before applying code (ms), allows review
  },
})
```

### Environment Variables

| Variable | Description |
|----------|-------------|
| `ANTHROPIC_API_KEY` | Claude API key |
| `OPENAI_API_KEY` | OpenAI API key |
| `GEMINI_API_KEY` | Google Gemini API key |

---

## 🔌 LLM Providers

### Claude (Anthropic)
Best for complex reasoning and code generation.
```lua
llm = {
  provider = "claude",
  claude = { model = "claude-sonnet-4-20250514" },
}
```

### OpenAI
Supports custom endpoints for Azure, OpenRouter, etc.
```lua
llm = {
  provider = "openai",
  openai = {
    model = "gpt-4o",
    endpoint = "https://api.openai.com/v1/chat/completions", -- optional
  },
}
```

### Google Gemini
Fast and capable.
```lua
llm = {
  provider = "gemini",
  gemini = { model = "gemini-2.0-flash" },
}
```

### GitHub Copilot
Uses your existing Copilot subscription (requires copilot.lua or copilot.vim).
```lua
llm = {
  provider = "copilot",
  copilot = { model = "gpt-4o" },
}
```

### Ollama (Local)
Run models locally with no API costs.
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

## 📝 Commands Reference

### Main Commands

| Command | Description |
|---------|-------------|
| `:Coder {subcommand}` | Main command with subcommands |
| `:CoderOpen` | Open the coder split view |
| `:CoderClose` | Close the coder split view |
| `:CoderToggle` | Toggle the coder split view |
| `:CoderProcess` | Process the last prompt |

### Ask Panel

| Command | Description |
|---------|-------------|
| `:CoderAsk` | Open the Ask panel |
| `:CoderAskToggle` | Toggle the Ask panel |
| `:CoderAskClear` | Clear chat history |

### Agent Mode

| Command | Description |
|---------|-------------|
| `:CoderAgent` | Open the Agent panel |
| `:CoderAgentToggle` | Toggle the Agent panel |
| `:CoderAgentStop` | Stop the running agent |

### Transform Commands

| Command | Description |
|---------|-------------|
| `:CoderTransform` | Transform all /@ @/ tags in file |
| `:CoderTransformCursor` | Transform tag at cursor position |
| `:CoderTransformVisual` | Transform selected tags (visual mode) |

### Utility Commands

| Command | Description |
|---------|-------------|
| `:CoderIndex` | Open coder companion for current file |
| `:CoderLogs` | Toggle logs panel |
| `:CoderType` | Switch between Ask/Agent modes |
| `:CoderTree` | Refresh tree.log |
| `:CoderTreeView` | View tree.log |

---

## 📖 Usage Guide

### Tag-Based Prompts

Write prompts in your coder file using `/@` and `@/` tags:

```typescript
/@ Create a Button component with the following props:
- variant: 'primary' | 'secondary' | 'danger'
- size: 'sm' | 'md' | 'lg'
- disabled: boolean
Use Tailwind CSS for styling @/
```

When you close the tag with `@/`, the prompt is automatically processed.

### Transform Commands

Transform prompts inline without the split view:

```typescript
// In your source file:
/@ Add input validation for email and password @/

// Run :CoderTransformCursor to transform the prompt at cursor
```

### Prompt Types

The plugin auto-detects prompt type:

| Keywords | Type | Behavior |
|----------|------|----------|
| `complete`, `finish`, `implement`, `todo` | Complete | Completes function body (replaces scope) |
| `refactor`, `rewrite`, `simplify` | Refactor | Replaces code |
| `fix`, `debug`, `bug`, `error` | Fix | Fixes bugs (replaces scope) |
| `add`, `create`, `generate` | Add | Inserts new code |
| `document`, `comment`, `jsdoc` | Document | Adds documentation |
| `optimize`, `performance`, `faster` | Optimize | Optimizes code (replaces scope) |
| `explain`, `what`, `how` | Explain | Shows explanation only |

### Function Completion

When you write a prompt **inside** a function body, the plugin uses Tree-sitter to detect the enclosing scope and automatically switches to "complete" mode:

```typescript
function getUserById(id: number): User | null {
  /@ return the user from the database by id, handle not found case @/
}
```

The LLM will complete the function body while keeping the exact same signature. The entire function scope is replaced with the completed version.

---

## 📊 Logs Panel

The logs panel provides real-time visibility into LLM operations:

### Features

- **Generation Logs**: Shows all LLM requests, responses, and token usage
- **Queue Display**: Shows pending and processing prompts
- **Full Response View**: Complete LLM responses are logged for debugging
- **Auto-cleanup**: Logs panel and queue windows automatically close when exiting Neovim

### Opening the Logs Panel

```vim
:CoderLogs
```

The logs panel opens automatically when processing prompts with the scheduler enabled.

### Keymaps

| Key | Description |
|-----|-------------|
| `q` | Close logs panel |
| `<Esc>` | Close logs panel |

---

## 🤖 Agent Mode

The Agent mode provides an autonomous coding assistant with tool access:

### Available Tools

- **read_file**: Read file contents
- **edit_file**: Edit files with find/replace
- **write_file**: Create or overwrite files
- **bash**: Execute shell commands

### Using Agent Mode

1. Open the agent panel: `:CoderAgent` or `<leader>ca`
2. Describe what you want to accomplish
3. The agent will use tools to complete the task
4. Review changes before they're applied

### Agent Keymaps

| Key | Description |
|-----|-------------|
| `<CR>` | Submit message |
| `Ctrl+c` | Stop agent execution |
| `q` | Close agent panel |

---

## ⌨️ Keymaps

### Default Keymaps (auto-configured)

| Key | Mode | Description |
|-----|------|-------------|
| `<leader>ctt` | Normal | Transform tag at cursor |
| `<leader>ctt` | Visual | Transform selected tags |
| `<leader>ctT` | Normal | Transform all tags in file |
| `<leader>ca` | Normal | Toggle Agent panel |
| `<leader>ci` | Normal | Open coder companion (index) |

### Ask Panel Keymaps

| Key | Description |
|-----|-------------|
| `@` | Attach/reference a file |
| `Ctrl+Enter` | Submit question |
| `Ctrl+n` | Start new chat |
| `Ctrl+f` | Add current file as context |
| `q` | Close panel |
| `Y` | Copy last response |

### Suggested Additional Keymaps

```lua
local map = vim.keymap.set

map("n", "<leader>co", "<cmd>Coder open<cr>", { desc = "Coder: Open" })
map("n", "<leader>cc", "<cmd>Coder close<cr>", { desc = "Coder: Close" })
map("n", "<leader>ct", "<cmd>Coder toggle<cr>", { desc = "Coder: Toggle" })
map("n", "<leader>cp", "<cmd>Coder process<cr>", { desc = "Coder: Process" })
map("n", "<leader>cs", "<cmd>Coder status<cr>", { desc = "Coder: Status" })
```

---

## 🏥 Health Check

Verify your setup:

```vim
:checkhealth codetyper
```

This checks:
- Neovim version
- curl availability
- LLM configuration
- API key status
- Telescope availability (optional)

---

## 📁 File Structure

```
your-project/
├── .coder/                    # Auto-created, gitignored
│   └── tree.log              # Project structure log
├── src/
│   ├── index.ts              # Your source file
│   ├── index.coder.ts        # Coder file (gitignored)
└── .gitignore                # Auto-updated with coder patterns
```

---

## 🤝 Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

---

## 📄 License

MIT License - see [LICENSE](LICENSE) for details.

---

## 👨‍💻 Author

**cargdev**

- Website: [cargdev.io](https://cargdev.io)
- Blog: [blog.cargdev.io](https://blog.cargdev.io)
- Email: carlos.gutierrez@carg.dev

---

<p align="center">
  Made with ❤️ for the Neovim community
</p>
