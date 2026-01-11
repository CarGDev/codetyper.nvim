# 🚀 Codetyper.nvim

**AI-powered coding partner for Neovim** - Write code faster with LLM assistance while staying in control of your logic.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Neovim](https://img.shields.io/badge/Neovim-0.8%2B-green.svg)](https://neovim.io/)

## ✨ Features

- **🪟 Split View**: Work with your code and prompts side by side
- **💬 Ask Panel**: Chat interface for questions and explanations (like avante.nvim)
- **🏷️ Tag-based Prompts**: Use `/@` and `@/` tags to write natural language prompts
- **🤖 Multiple LLM Providers**: Support for Claude API and Ollama (local)
- **📝 Smart Injection**: Automatically detects prompt type (refactor, add, document)
- **🔒 Git Integration**: Automatically adds `.coder.*` files and `.coder/` folder to `.gitignore`
- **🌳 Project Tree Logging**: Automatically maintains a `tree.log` tracking your project structure
- **⚡ Lazy Loading**: Only loads when you need it

---

## 📋 Table of Contents

- [Requirements](#-requirements)
- [Installation](#-installation)
- [Quick Start](#-quick-start)
- [Configuration](#%EF%B8%8F-configuration)
- [Commands Reference](#-commands-reference)
- [Usage Guide](#-usage-guide)
- [How It Works](#%EF%B8%8F-how-it-works)
- [Keymaps](#-keymaps-suggested)
- [Health Check](#-health-check)
- [Contributing](#-contributing)

---

## 📋 Requirements

- Neovim >= 0.8.0
- curl (for API calls)
- Claude API key **OR** Ollama running locally

---

## 📦 Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "cargdev/codetyper.nvim",
  cmd = { "Coder", "CoderOpen", "CoderToggle" },
  keys = {
    { "<leader>co", "<cmd>Coder open<cr>", desc = "Coder: Open" },
    { "<leader>ct", "<cmd>Coder toggle<cr>", desc = "Coder: Toggle" },
    { "<leader>cp", "<cmd>Coder process<cr>", desc = "Coder: Process" },
  },
  config = function()
    require("codetyper").setup({
      llm = {
        provider = "claude", -- or "ollama"
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

That's it! You're now coding with AI assistance. 🎉

---

## ⚙️ Configuration

```lua
require("codetyper").setup({
  -- LLM Provider Configuration
  llm = {
    provider = "claude", -- "claude" or "ollama"
    
    -- Claude (Anthropic) settings
    claude = {
      api_key = nil, -- Uses ANTHROPIC_API_KEY env var if nil
      model = "claude-sonnet-4-20250514",
    },
    
    -- Ollama (local) settings
    ollama = {
      host = "http://localhost:11434",
      model = "codellama",
    },
  },
  
  -- Window Configuration
  window = {
    width = 0.25,         -- 25% of screen width (1/4) for Ask panel
    position = "left",    -- "left" or "right"
    border = "rounded",   -- Border style for floating windows
  },
  
  -- Prompt Tag Patterns
  patterns = {
    open_tag = "/@",      -- Tag to start a prompt
    close_tag = "@/",     -- Tag to end a prompt
    file_pattern = "*.coder.*",
  },
  
  -- Auto Features
  auto_gitignore = true,  -- Automatically add coder files to .gitignore
})
```

### Environment Variables

| Variable | Description |
|----------|-------------|
| `ANTHROPIC_API_KEY` | Your Claude API key (if not set in config) |

---

## 📜 Commands Reference

### Main Command

| Command | Description |
|---------|-------------|
| `:Coder {subcommand}` | Main command with subcommands below |

### Subcommands

| Subcommand | Alias | Description |
|------------|-------|-------------|
| `open` | `:CoderOpen` | Open the coder split view for current file |
| `close` | `:CoderClose` | Close the coder split view |
| `toggle` | `:CoderToggle` | Toggle the coder split view on/off |
| `process` | `:CoderProcess` | Process the last prompt and generate code |
| `status` | - | Show plugin status and project statistics |
| `focus` | - | Switch focus between coder and target windows |
| `tree` | `:CoderTree` | Manually refresh the tree.log file |
| `tree-view` | `:CoderTreeView` | Open tree.log in a readonly split |
| `ask` | `:CoderAsk` | Open the Ask panel for questions |
| `ask-toggle` | `:CoderAskToggle` | Toggle the Ask panel |
| `ask-clear` | `:CoderAskClear` | Clear Ask chat history |

---

### Command Details

#### `:Coder open` / `:CoderOpen`

Opens a split view with:
- **Left panel**: The coder file (`*.coder.*`) where you write prompts
- **Right panel**: The target file where generated code is injected

```vim
" If you have index.ts open:
:Coder open
" Creates/opens index.coder.ts on the left
```

**Behavior:**
- If no file is in buffer, opens a file picker (Telescope if available)
- Creates the coder file if it doesn't exist
- Automatically sets the correct filetype for syntax highlighting

---

#### `:Coder close` / `:CoderClose`

Closes the coder split view, keeping only your target file open.

```vim
:Coder close
```

---

#### `:Coder toggle` / `:CoderToggle`

Toggles the coder view on or off. Useful for quick switching.

```vim
:Coder toggle
```

---

#### `:Coder process` / `:CoderProcess`

Processes the last completed prompt in the coder file and sends it to the LLM.

```vim
" After writing a prompt and closing with @/
:Coder process
```

**What happens:**
1. Finds the last `/@...@/` prompt in the coder buffer
2. Detects the prompt type (refactor, add, document, etc.)
3. Sends it to the configured LLM with file context
4. Injects the generated code into the target file

---

#### `:Coder status`

Displays current plugin status including:
- LLM provider and configuration
- API key status (configured/not set)
- Window settings
- Project statistics (files, directories)
- Tree log path

```vim
:Coder status
```

---

#### `:Coder focus`

Switches focus between the coder window and target window.

```vim
:Coder focus
" Press again to switch back
```

---

#### `:Coder tree` / `:CoderTree`

Manually refreshes the `.coder/tree.log` file with current project structure.

```vim
:Coder tree
```

> Note: The tree is automatically updated on file save/create/delete.

---

#### `:Coder tree-view` / `:CoderTreeView`

Opens the tree.log file in a readonly split for viewing your project structure.

```vim
:Coder tree-view
```

---

#### `:Coder ask` / `:CoderAsk`

Opens the **Ask panel** - a chat interface similar to avante.nvim for asking questions about your code, getting explanations, or general programming help.

```vim
:Coder ask
```

**The Ask Panel Layout:**
```
┌───────────────────┬─────────────────────────────────────────┐
│  💬 Chat (output) │                                         │
│                   │         Your code file                  │
│  ┌─ 👤 You ────   │                                         │
│  │ What is this?  │                                         │
│                   │                                         │
│  ┌─ 🤖 AI ─────   │                                         │
│  │ This is...     │                                         │
├───────────────────┤                                         │
│  ✏️  Input        │                                         │
│  Type question... │                                         │
└───────────────────┴─────────────────────────────────────────┘
      (1/4 width)                  (3/4 width)
```

> **Note:** The Ask panel is fixed at 1/4 (25%) of the screen width.

**Ask Panel Keymaps:**

| Key | Mode | Description |
|-----|------|-------------|
| `@` | Insert | Attach/reference a file |
| `Ctrl+Enter` | Insert/Normal | Submit question |
| `Ctrl+n` | Insert/Normal | Start new chat (clear all) |
| `Ctrl+f` | Insert/Normal | Add current file as context |
| `Ctrl+h/j/k/l` | Normal/Insert | Navigate between windows |
| `q` | Normal | Close panel (closes both windows) |
| `K` / `J` | Normal | Jump between output/input |
| `Y` | Normal | Copy last response to clipboard |

---

#### `:Coder ask-toggle` / `:CoderAskToggle`

Toggles the Ask panel on or off.

```vim
:Coder ask-toggle
```

---

#### `:Coder ask-clear` / `:CoderAskClear`

Clears the Ask panel chat history.

```vim
:Coder ask-clear
```

---

## 📖 Usage Guide

### Step 1: Open Your Project File

Open any source file you want to work with:

```vim
:e src/components/Button.tsx
```

### Step 2: Start Coder View

```vim
:Coder open
```

This creates a split:
```
┌─────────────────────────┬─────────────────────────┐
│  Button.coder.tsx       │  Button.tsx             │
│  (write prompts here)   │  (your actual code)     │
└─────────────────────────┴─────────────────────────┘
```

### Step 3: Write Your Prompt

In the coder file (left), write your prompt using tags:

```tsx
/@ Create a Button component with the following props:
- variant: 'primary' | 'secondary' | 'danger'
- size: 'sm' | 'md' | 'lg'
- disabled: boolean
- onClick: function
Use Tailwind CSS for styling @/
```

### Step 4: Process the Prompt

When you close the tag with `@/`, you'll be prompted to process. Or manually:

```vim
:Coder process
```

### Step 5: Review Generated Code

The generated code appears in your target file (right panel). Review, edit if needed, and save!

---

### Prompt Types

The plugin automatically detects what you want based on keywords:

| Keywords | Type | Behavior |
|----------|------|----------|
| `refactor`, `rewrite`, `change` | Refactor | Replaces code in target file |
| `add`, `create`, `implement`, `new` | Add | Inserts code at cursor position |
| `document`, `comment`, `jsdoc` | Document | Adds documentation above code |
| `explain`, `what`, `how` | Explain | Shows explanation (no injection) |
| *(other)* | Generic | Prompts you for injection method |

---

### Prompt Examples

#### Creating New Functions

```typescript
/@ Create an async function fetchUsers that:
- Takes a page number and limit as parameters
- Fetches from /api/users endpoint
- Returns typed User[] array
- Handles errors gracefully @/
```

#### Refactoring Code

```typescript
/@ Refactor the handleSubmit function to:
- Use async/await instead of .then()
- Add proper TypeScript types
- Extract validation logic into separate function @/
```

#### Adding Documentation

```typescript
/@ Add JSDoc documentation to all exported functions
including @param, @returns, and @example tags @/
```

#### Implementing Patterns

```typescript
/@ Implement the singleton pattern for DatabaseConnection class
with lazy initialization and thread safety @/
```

#### Adding Tests

```typescript
/@ Create unit tests for the calculateTotal function
using Jest, cover edge cases:
- Empty array
- Negative numbers
- Large numbers @/
```

---

## 🏗️ How It Works

```
┌─────────────────────────────────────────────────────────────────┐
│                          Neovim                                  │
├────────────────────────────┬────────────────────────────────────┤
│   src/api.coder.ts         │        src/api.ts                  │
│                            │                                    │
│   /@ Create a REST client  │   // Generated code appears here   │
│   class with methods for   │   export class RestClient {        │
│   GET, POST, PUT, DELETE   │     async get<T>(url: string) {    │
│   with TypeScript          │       // ...                       │
│   generics @/              │     }                              │
│                            │   }                                │
└────────────────────────────┴────────────────────────────────────┘
```

### File Structure

```
your-project/
├── .coder/                    # Auto-created, gitignored
│   └── tree.log              # Project structure log
├── src/
│   ├── index.ts              # Your source file
│   ├── index.coder.ts        # Coder file (gitignored)
│   ├── utils.ts
│   └── utils.coder.ts
└── .gitignore                # Auto-updated with coder patterns
```

### The Flow

1. **You write prompts** in `*.coder.*` files using `/@...@/` tags
2. **Plugin detects** when you close a prompt tag
3. **Context is gathered** from the target file (content, language, etc.)
4. **LLM generates** code based on your prompt and context
5. **Code is injected** into the target file based on prompt type
6. **You review and save** - you're always in control!

### Project Tree Logging

The `.coder/tree.log` file is automatically maintained:

```
# Project Tree: my-project
# Generated: 2026-01-11 15:30:45
# By: Codetyper.nvim

📦 my-project
├── 📁 src
│   ├── 📘 index.ts
│   ├── 📘 utils.ts
│   └── 📁 components
│       └── ⚛️  Button.tsx
├── 📋 package.json
└── 📝 README.md
```

Updated automatically when you:
- Create new files
- Save files
- Delete files

---

## 🔑 Keymaps (Suggested)

Add these to your Neovim config:

```lua
-- Codetyper keymaps
local map = vim.keymap.set

-- Coder view
map("n", "<leader>co", "<cmd>Coder open<cr>", { desc = "Coder: Open view" })
map("n", "<leader>cc", "<cmd>Coder close<cr>", { desc = "Coder: Close view" })
map("n", "<leader>ct", "<cmd>Coder toggle<cr>", { desc = "Coder: Toggle view" })
map("n", "<leader>cp", "<cmd>Coder process<cr>", { desc = "Coder: Process prompt" })
map("n", "<leader>cs", "<cmd>Coder status<cr>", { desc = "Coder: Show status" })
map("n", "<leader>cf", "<cmd>Coder focus<cr>", { desc = "Coder: Switch focus" })
map("n", "<leader>cv", "<cmd>Coder tree-view<cr>", { desc = "Coder: View tree" })

-- Ask panel
map("n", "<leader>ca", "<cmd>Coder ask<cr>", { desc = "Coder: Open Ask" })
map("n", "<leader>cA", "<cmd>Coder ask-toggle<cr>", { desc = "Coder: Toggle Ask" })
map("n", "<leader>cx", "<cmd>Coder ask-clear<cr>", { desc = "Coder: Clear Ask" })
```

Or with [which-key.nvim](https://github.com/folke/which-key.nvim):

```lua
local wk = require("which-key")
wk.register({
  ["<leader>c"] = {
    name = "+coder",
    o = { "<cmd>Coder open<cr>", "Open view" },
    c = { "<cmd>Coder close<cr>", "Close view" },
    t = { "<cmd>Coder toggle<cr>", "Toggle view" },
    p = { "<cmd>Coder process<cr>", "Process prompt" },
    s = { "<cmd>Coder status<cr>", "Show status" },
    f = { "<cmd>Coder focus<cr>", "Switch focus" },
    v = { "<cmd>Coder tree-view<cr>", "View tree" },
  },
})
```

---

## 🔧 Health Check

Verify your setup is correct:

```vim
:checkhealth codetyper
```

This checks:
- ✅ Neovim version
- ✅ curl availability
- ✅ LLM configuration
- ✅ API key status
- ✅ Telescope availability (optional)
- ✅ Gitignore configuration

---

## 🤝 Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

---

## 📄 License

MIT License - see [LICENSE](LICENSE) for details.

---

## 👤 Author

**cargdev**

- 🌐 Website: [cargdev.io](https://cargdev.io)
- 📝 Blog: [blog.cargdev.io](https://blog.cargdev.io)
- 📧 Email: carlos.gutierrez@carg.dev

---

<p align="center">
  Made with ❤️ for the Neovim community
</p>
