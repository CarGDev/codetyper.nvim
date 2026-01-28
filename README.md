# codetyper.nvim

**AI-powered coding assistant for Neovim** - Write code faster with LLM assistance while staying in complete control.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Neovim](https://img.shields.io/badge/Neovim-0.8%2B-green.svg)](https://neovim.io/)

---

## Overview

codetyper.nvim brings the power of large language models directly into your Neovim workflow. Unlike other AI coding tools, codetyper is designed around **you staying in control** - every change is presented as a reviewable diff, and you decide what gets applied.

### Key Principles

- **Non-intrusive**: AI suggestions appear as reviewable conflicts, never auto-applied
- **Context-aware**: Uses tree-sitter to understand code scope and structure
- **Provider-agnostic**: Works with Claude, OpenAI, Gemini, GitHub Copilot, or local Ollama
- **Transparent**: Real-time logs show exactly what's happening with token usage and costs

---

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Usage Modes](#usage-modes)
  - [Tag-Based Prompts](#tag-based-prompts)
  - [Ask Panel](#ask-panel)
  - [Agent Mode](#agent-mode)
  - [Agentic Mode (Multi-Phase)](#agentic-mode-multi-phase)
- [Conflict Resolution](#conflict-resolution)
- [Commands Reference](#commands-reference)
- [Keymaps Reference](#keymaps-reference)
- [LLM Providers](#llm-providers)
- [Advanced Features](#advanced-features)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)

---

## Features

### Core Features

| Feature | Description |
|---------|-------------|
| **Split View** | Work with code and prompts side by side in companion files |
| **Ask Panel** | Chat interface for questions and explanations |
| **Agent Mode** | Autonomous coding agent with tool use (read, edit, write, bash) |
| **Agentic Mode** | Multi-phase workflow: Discovery → Planning → Execution |
| **Tag Prompts** | Write natural language prompts using `/@` and `@/` tags |
| **Transform** | Transform prompts inline without leaving your file |
| **Conflict Resolution** | Git-style diff visualization with interactive review |

### Intelligence Features

| Feature | Description |
|---------|-------------|
| **Intent Detection** | Understands: complete, refactor, fix, add, document, explain, test |
| **Scope Resolution** | Tree-sitter powered context extraction for functions/methods |
| **Confidence Scoring** | Automatic escalation from local to remote LLMs based on task complexity |
| **SEARCH/REPLACE** | Reliable code editing with fuzzy matching for robustness |
| **Linter Validation** | Auto-check and offer to fix lint errors after code injection |

### Operational Features

| Feature | Description |
|---------|-------------|
| **Multi-Provider** | Claude, OpenAI, Gemini, GitHub Copilot, Ollama (local) |
| **Logs Panel** | Real-time visibility into LLM requests, responses, and token usage |
| **Cost Tracking** | Persistent cost estimation with session and all-time statistics |
| **Brain System** | Knowledge graph that learns from your codebase and coding patterns |
| **Event Scheduler** | Queue-based processing with optimistic execution |

---

## Requirements

### Required

- **Neovim** >= 0.8.0
- **curl** - for API calls
- **One LLM provider**: Claude API key, OpenAI API key, Gemini API key, GitHub Copilot, or Ollama

### Required Plugins

```lua
"nvim-lua/plenary.nvim"          -- Async utilities
"nvim-treesitter/nvim-treesitter" -- Scope detection
```

### Optional Plugins

```lua
"nvim-treesitter/nvim-treesitter-textobjects" -- Better text objects
"MunifTanjim/nui.nvim"                        -- UI components
```

---

## Installation

### Using lazy.nvim

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
    { "<leader>cq", "<cmd>CoderAsk<cr>", desc = "Coder: Ask" },
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

### Using packer.nvim

```lua
use {
  "cargdev/codetyper.nvim",
  requires = {
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter",
  },
  config = function()
    require("codetyper").setup()
  end,
}
```

---

## Quick Start

### 1. Set up your API key

```bash
# Option A: Environment variable
export ANTHROPIC_API_KEY="your-key-here"

# Option B: Use the built-in credential manager
:CoderAddApiKey
```

### 2. Open a file and start the coder companion

```vim
:e src/utils.ts
:Coder open
```

This opens a split view with your code on the right and a `.coder.ts` companion file on the left.

### 3. Write a prompt using tags

In the companion file, write:

```typescript
/@ Create a function to validate email addresses
using regex, return true if valid @/
```

### 4. Review the generated code

The LLM generates code and presents it as a conflict:

```
<<<<<<< CURRENT
=======
function validateEmail(email: string): boolean {
  const regex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  return regex.test(email);
}
>>>>>>> INCOMING
```

### 5. Resolve the conflict

- Press `ct` to accept the AI suggestion (theirs)
- Press `co` to keep your original code (ours)
- Press `cb` to keep both versions
- Press `cn` to delete both (none)

---

## Configuration

### Full Configuration

```lua
require("codetyper").setup({
  -- LLM Provider Configuration
  llm = {
    provider = "claude", -- "claude" | "openai" | "gemini" | "copilot" | "ollama"

    claude = {
      api_key = nil, -- Uses ANTHROPIC_API_KEY env var if nil
      model = "claude-sonnet-4-20250514",
    },

    openai = {
      api_key = nil, -- Uses OPENAI_API_KEY env var if nil
      model = "gpt-4o",
      endpoint = nil, -- Custom endpoint for Azure, OpenRouter, etc.
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
    position = "left", -- "left" | "right"
    border = "rounded",
  },

  -- Prompt Tag Patterns
  patterns = {
    open_tag = "/@",
    close_tag = "@/",
    file_pattern = "*.coder.*",
  },

  -- Auto Features
  auto_gitignore = true,  -- Add .coder.* to .gitignore
  auto_open_ask = true,   -- Auto-open ask panel on first use
  auto_index = false,     -- Auto-create companion files on file open

  -- Event-Driven Scheduler
  scheduler = {
    enabled = true,
    ollama_scout = true,          -- Use Ollama for initial classification
    escalation_threshold = 0.7,   -- Confidence threshold for escalation
    max_concurrent = 2,           -- Max concurrent LLM requests
    completion_delay_ms = 100,    -- Delay before processing
    apply_delay_ms = 5000,        -- Delay before applying changes
  },
})
```

### Environment Variables

| Variable | Provider | Description |
|----------|----------|-------------|
| `ANTHROPIC_API_KEY` | Claude | Anthropic API key |
| `OPENAI_API_KEY` | OpenAI | OpenAI API key |
| `GEMINI_API_KEY` | Gemini | Google Gemini API key |

### Secure Credential Storage

Store API keys securely with the built-in credential manager:

```vim
:CoderAddApiKey
```

Credentials are stored in `~/.local/share/nvim/codetyper/configuration.json`.

**Priority order:**
1. Stored credentials (via `:CoderAddApiKey`)
2. Config file settings
3. Environment variables

---

## Usage Modes

### Tag-Based Prompts

Write prompts directly in your coder companion file using tags:

```typescript
/@ Create a React component for a user profile card
with props: name, email, avatar
Use Tailwind CSS for styling @/
```

#### Intent Keywords

The plugin detects your intent from keywords in the prompt:

| Intent | Keywords | Behavior |
|--------|----------|----------|
| **Complete** | complete, finish, implement | Fills in function body |
| **Refactor** | refactor, rewrite, simplify, clean | Restructures code |
| **Fix** | fix, debug, bug, error, broken | Fixes issues |
| **Add** | add, create, generate, new | Inserts new code |
| **Document** | document, comment, jsdoc, docstring | Adds documentation |
| **Explain** | explain, what, how, why | Shows explanation |
| **Test** | test, spec, unit test | Writes tests |

#### Scope-Aware Completion

Write prompts inside functions for automatic scope detection:

```typescript
function calculateTax(amount: number, rate: number): number {
  /@ calculate the tax and return the result @/
}
```

The plugin detects the function scope and generates appropriate code.

### Ask Panel

Open an interactive chat for questions and explanations:

```vim
:CoderAsk
```

**Features:**
- Multi-turn conversation with context
- File attachment with `@` key
- Add current file as context with `Ctrl+f`
- Copy responses with `Y`

**Keymaps in Ask Panel:**

| Key | Action |
|-----|--------|
| `@` | Attach/reference a file |
| `Ctrl+Enter` | Submit question |
| `Ctrl+n` | Start new chat |
| `Ctrl+f` | Add current file as context |
| `Y` | Copy last response |
| `q` | Close panel |

### Agent Mode

Autonomous coding agent with tool access:

```vim
:CoderAgent
```

**Available Tools:**

| Tool | Description |
|------|-------------|
| `view` / `read_file` | Read file contents |
| `edit` / `edit_file` | Edit files with SEARCH/REPLACE |
| `write` / `write_file` | Create or overwrite files |
| `bash` | Execute shell commands |
| `grep` | Search for patterns in files |
| `glob` | Find files by pattern |

**Example workflow:**
1. Open Agent panel: `:CoderAgent`
2. Describe task: "Add input validation to the login form"
3. Agent explores codebase, identifies files, makes changes
4. Review changes in conflict mode

**Keymaps in Agent Panel:**

| Key | Action |
|-----|--------|
| `<CR>` | Submit message |
| `Ctrl+c` | Stop agent execution |
| `q` | Close panel |

### Agentic Mode (Multi-Phase)

For complex tasks, use the multi-phase agentic workflow:

```vim
:CoderAgenticRun Add user authentication with JWT tokens
```

**Three Phases:**

#### 1. Discovery Phase (Read-only)
- Explores project structure
- Finds relevant files and patterns
- Understands dependencies and conventions
- Updates long-term project knowledge

#### 2. Planning Phase (Read-only)
- Creates step-by-step implementation plan
- Identifies all files to modify
- Specifies order of operations
- Includes testing steps

#### 3. Execution Phase (Full access)
- Executes approved plan step by step
- Verifies each change
- Handles errors and retries
- Reports progress

**Built-in Agent Personas:**

| Persona | Description | Tools |
|---------|-------------|-------|
| `coder` | Full-featured coding agent | view, edit, write, grep, glob, bash |
| `planner` | Read-only planning and analysis | view, grep, glob |
| `explorer` | Quick codebase exploration | view, grep, glob |

**Custom Agents:**

Create custom agents in `.coder/agents/`:

```markdown
---
description: Python specialist with testing focus
tools: view,grep,glob,edit,write,bash
---

# Python Agent

You are a Python specialist. Follow PEP 8 conventions.
Always write pytest tests for new functionality.
```

**Commands:**

| Command | Description |
|---------|-------------|
| `:CoderAgenticRun <task>` | Run agentic task |
| `:CoderAgenticList` | List available agents |
| `:CoderAgenticInit` | Initialize `.coder/agents/` directory |

---

## Conflict Resolution

When the LLM generates code, it's presented as a git-style conflict:

```
<<<<<<< CURRENT
// Your original code (if any)
=======
// AI-generated code
>>>>>>> INCOMING
```

### Visual Indicators

- **Green background**: Original (CURRENT) code
- **Blue background**: AI-generated (INCOMING) code
- **Virtual text**: Shows available keymaps on each section

### Resolution Keymaps

| Key | Action | Description |
|-----|--------|-------------|
| `co` | Accept Current | Keep your original code |
| `ct` | Accept Incoming | Use the AI suggestion |
| `cb` | Accept Both | Keep both versions |
| `cn` | Accept None | Delete the entire conflict |
| `cm` | Show Menu | Open resolution menu |
| `]x` | Next Conflict | Jump to next conflict |
| `[x` | Previous Conflict | Jump to previous conflict |

### Auto-Menu

When code is injected, a floating menu automatically appears. After resolving one conflict, it shows again for the next.

Toggle auto-menu: `:CoderConflictAutoMenu`

### Bulk Resolution

Resolve all conflicts at once:

```vim
:CoderConflictResolveAll ours    " Keep all original
:CoderConflictResolveAll theirs  " Accept all AI suggestions
:CoderConflictResolveAll both    " Keep all versions
:CoderConflictResolveAll none    " Delete all conflicts
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

### Ask & Agent

| Command | Alias | Description |
|---------|-------|-------------|
| `:Coder ask` | `:CoderAsk` | Open the Ask panel |
| `:Coder ask-toggle` | `:CoderAskToggle` | Toggle the Ask panel |
| `:Coder ask-clear` | `:CoderAskClear` | Clear chat history |
| `:Coder agent` | `:CoderAgent` | Open the Agent panel |
| `:Coder agent-toggle` | `:CoderAgentToggle` | Toggle the Agent panel |
| `:Coder agent-stop` | `:CoderAgentStop` | Stop running agent |

### Agentic Mode

| Command | Alias | Description |
|---------|-------|-------------|
| `:Coder agentic-run <task>` | `:CoderAgenticRun` | Run agentic task |
| `:Coder agentic-list` | `:CoderAgenticList` | List available agents |
| `:Coder agentic-init` | `:CoderAgenticInit` | Initialize agents directory |

### Transform

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
| `:CoderConflictResolveAll [keep]` | Resolve all conflicts |
| `:CoderConflictAcceptCurrent` | Accept original code |
| `:CoderConflictAcceptIncoming` | Accept AI suggestion |
| `:CoderConflictAcceptBoth` | Accept both versions |
| `:CoderConflictAcceptNone` | Delete both |

### Linter

| Command | Description |
|---------|-------------|
| `:CoderLintCheck` | Check buffer for lint errors |
| `:CoderLintFix` | Request AI to fix lint errors |
| `:CoderLintQuickfix` | Show errors in quickfix |
| `:CoderLintToggleAuto` | Toggle auto lint checking |

### Scheduler & Queue

| Command | Alias | Description |
|---------|-------|-------------|
| `:Coder queue-status` | `:CoderQueueStatus` | Show scheduler status |
| `:Coder queue-process` | `:CoderQueueProcess` | Trigger queue processing |
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

### UI

| Command | Description |
|---------|-------------|
| `:CoderLogs` | Toggle logs panel |
| `:CoderType` | Show Ask/Agent switcher |

---

## Keymaps Reference

### Default Keymaps

| Key | Mode | Description |
|-----|------|-------------|
| `<leader>ctt` | Normal | Transform tag at cursor |
| `<leader>ctt` | Visual | Transform selected tags |
| `<leader>ctT` | Normal | Transform all tags in file |
| `<leader>ca` | Normal | Toggle Agent panel |
| `<leader>ci` | Normal | Open coder companion |

### Conflict Resolution (Buffer-local)

| Key | Description |
|-----|-------------|
| `co` | Accept CURRENT (original) |
| `ct` | Accept INCOMING (AI suggestion) |
| `cb` | Accept BOTH versions |
| `cn` | Accept NONE (delete) |
| `cm` | Show conflict menu |
| `]x` | Next conflict |
| `[x` | Previous conflict |
| `<CR>` | Show menu on conflict |

### Suggested Additional Keymaps

```lua
local map = vim.keymap.set

-- Core
map("n", "<leader>co", "<cmd>Coder open<cr>", { desc = "Coder: Open" })
map("n", "<leader>cc", "<cmd>Coder close<cr>", { desc = "Coder: Close" })
map("n", "<leader>ct", "<cmd>Coder toggle<cr>", { desc = "Coder: Toggle" })
map("n", "<leader>cp", "<cmd>Coder process<cr>", { desc = "Coder: Process" })

-- Ask & Agent
map("n", "<leader>cq", "<cmd>CoderAsk<cr>", { desc = "Coder: Ask" })
map("n", "<leader>ca", "<cmd>CoderAgentToggle<cr>", { desc = "Coder: Agent" })

-- Utilities
map("n", "<leader>cs", "<cmd>Coder status<cr>", { desc = "Coder: Status" })
map("n", "<leader>cl", "<cmd>CoderLogs<cr>", { desc = "Coder: Logs" })
map("n", "<leader>c$", "<cmd>CoderCost<cr>", { desc = "Coder: Cost" })
```

---

## LLM Providers

### Claude (Anthropic)

```lua
llm = {
  provider = "claude",
  claude = {
    model = "claude-sonnet-4-20250514",
    -- api_key = "sk-..." -- or use ANTHROPIC_API_KEY env var
  },
}
```

### OpenAI

```lua
llm = {
  provider = "openai",
  openai = {
    model = "gpt-4o",
    -- api_key = "sk-..." -- or use OPENAI_API_KEY env var
    -- endpoint = "https://api.openai.com/v1/chat/completions",
  },
}
```

**Custom Endpoints (Azure, OpenRouter, etc.):**

```lua
openai = {
  model = "gpt-4o",
  endpoint = "https://your-resource.openai.azure.com/openai/deployments/gpt-4/chat/completions?api-version=2024-02-15-preview",
},
```

### Google Gemini

```lua
llm = {
  provider = "gemini",
  gemini = {
    model = "gemini-2.0-flash",
    -- api_key = "..." -- or use GEMINI_API_KEY env var
  },
}
```

### GitHub Copilot

```lua
llm = {
  provider = "copilot",
  copilot = {
    model = "gpt-4o",
  },
}
```

Requires GitHub Copilot to be configured in your editor.

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

**Popular Ollama models for coding:**
- `deepseek-coder:6.7b` - Fast, good for completions
- `codellama:13b` - Meta's code-focused model
- `mistral:7b` - General purpose, good quality
- `qwen2.5-coder:7b` - Strong coding performance

---

## Advanced Features

### Linter Validation

After accepting AI suggestions, the plugin automatically:

1. Saves the file
2. Checks LSP diagnostics for errors
3. Offers to fix lint errors with AI

**Configuration:**

```lua
-- In conflict settings
lint_after_accept = true,      -- Check linter after accepting
auto_fix_lint_errors = true,   -- Auto-queue fix without prompting
```

### Logs Panel

Real-time visibility into LLM operations:

```vim
:CoderLogs
```

Shows:
- Generation requests and responses
- Token usage (input/output)
- Queue status and timing
- Errors and warnings

### Cost Tracking

Track API costs across sessions:

```vim
:CoderCost
```

Features:
- Session and all-time statistics
- Per-model breakdown
- Pricing for 50+ models
- Persistent history in `.coder/cost_history.json`

**Keymaps in Cost Window:**

| Key | Action |
|-----|--------|
| `q` / `<Esc>` | Close window |
| `r` | Refresh display |
| `c` | Clear session costs |
| `C` | Clear all history |

### Brain System

The brain system learns from your codebase:

```vim
:CoderBrain stats    " Show brain statistics
:CoderBrain commit   " Commit learned knowledge
:CoderBrain flush    " Clear working memory
:CoderBrain prune    " Remove stale knowledge
```

**Knowledge Types:**
- Project structure and organization
- Code patterns and conventions
- File purposes and relationships
- Testing approaches
- Dependencies

### Project Rules

Create project-specific rules in `.coder/rules/`:

```markdown
<!-- .coder/rules/style.md -->
# Code Style Rules

- Use TypeScript strict mode
- Prefer functional components in React
- Use Tailwind CSS for styling
- Write tests for all new features
```

These rules are automatically injected into agent prompts.

---

## File Structure

```
your-project/
├── .coder/
│   ├── agents/           # Custom agent definitions
│   │   └── my-agent.md
│   ├── rules/            # Project-specific rules
│   │   └── style.md
│   ├── brain/            # Learned knowledge
│   ├── tree.log          # Project structure tracking
│   └── cost_history.json # Cost tracking data
├── src/
│   ├── index.ts          # Your source file
│   └── index.coder.ts    # Companion file (auto-created)
└── .gitignore            # .coder.* auto-added
```

---

## Troubleshooting

### Health Check

```vim
:checkhealth codetyper
```

### Debug Information

```vim
:Coder status      " Plugin status
:CoderLogs         " View logs
:messages          " Vim messages
```

### Common Issues

**1. No response from LLM**
- Check API key: `:CoderCredentials`
- Check logs: `:CoderLogs`
- Verify network connectivity

**2. Conflict markers not appearing**
- Ensure file type is supported
- Check for existing conflicts: `:CoderConflictStatus`

**3. Agent not finding files**
- Verify working directory: `:pwd`
- Check project structure: `:!ls -la`

**4. High latency**
- Consider using Ollama for local inference
- Use smaller models for simple tasks
- Check `scheduler.escalation_threshold`

---

## Contributing

Contributions are welcome! Please see [docs/contributing.md](docs/contributing.md) for guidelines.

### Development Setup

```bash
git clone https://github.com/cargdev/codetyper.nvim
cd codetyper.nvim
nvim --cmd "set rtp+=."
```

### Running Tests

```bash
nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"
```

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
