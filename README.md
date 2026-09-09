# Codetyper.nvim

**An AI coding partner for Neovim that keeps the developer in control.**

Codetyper turns a selection, cursor position, or inline ` /@ ... @/ ` prompt
into a bounded LLM request and a reviewable edit. It supports provider-aware
generation, deterministic import insertion, project context adapters, and a
small interactive agent tool boundary.

## Features

- Inline transforms for selections and cursor-oriented edits
- Explain and question prompts in a markdown window
- Agent file operations using `FILE:CREATE`, `FILE:MODIFY`, and `FILE:DELETE`
- Six bounded project-agent tools with shared native/marker validation
- CodeGraph and TokenSave adapters that never open databases or run indexing
- Context7 through MCPHub first, with a fixed read-only HTTP fallback
- Safe deterministic imports for supported source languages
- Selectable `ask_user` popup with cancellation and FIFO serialization
- Copilot, Ollama, Anthropic Claude, and ChatGPT Plus/Pro provider routing
- Provider-labelled asynchronous model discovery with stale/error states
- Scope-aware context, project indexing, diff review, queueing, and cost tracking

## Requirements

- Neovim 0.9 or newer
- `curl` for HTTP providers and the Context7 fallback
- At least one configured provider:
  - GitHub Copilot, using existing Copilot credentials or `:CoderAuth`
  - Ollama running locally
  - Anthropic access through inherited `ANTHROPIC_API_KEY`
  - ChatGPT Plus/Pro subscription OAuth through the OpenAI auth flow
- Optional: `nvim-treesitter` for richer scope resolution
- Optional: `nui.nvim` for other UI integrations
- Optional: `mcphub.nvim`, CodeGraph, and TokenSave for project context tools

The test suite does not require a provider, external CLI, MCP server, database,
or network credentials. It uses headless Neovim and injected fakes.

## Installation

### lazy.nvim

```lua
{
  "cargdev/codetyper.nvim",
  cmd = {
    "Coder",
    "CoderTransformSelection",
    "CoderModel",
  },
  keys = {
    { "<leader>ctt", desc = "Coder: Transform / Prompt" },
    { "<leader>ctm", desc = "Coder: Select model" },
  },
  config = function()
    require("codetyper").setup({
      llm = { provider = "copilot" },
    })
  end,
}
```

### packer.nvim

```lua
use({
  "cargdev/codetyper.nvim",
  config = function()
    require("codetyper").setup()
  end,
})
```

## Quick start

1. Select code and press `<leader>ctt`, or place the cursor where new code
   should be inserted.
2. Describe the change in the prompt window.
3. Submit with `<CR>` and review the generated diff/conflict.
4. Resolve the change with the conflict controls or continue with another
   prompt.

Inline prompts use the configured tags inside comments:

```lua
-- /@ add input validation to this function @/
```

Use `:CoderProcess` for manual processing. `:CoderAutotrigger` toggles
automatic processing.

## Configuration

```lua
require("codetyper").setup({
  llm = {
    provider = "copilot", -- ollama, copilot, claude, or openai
    smart_selection = false,
    copilot = {
      model = "claude-sonnet-5",
      ask_model = "gpt-5-mini",
    },
    ollama = {
      host = "http://localhost:11434",
      model = "gemma4:26b",
    },
    claude = {
      model = "claude-sonnet-4-5",
      ask_model = "claude-3-5-haiku-20241022",
    },
    openai = {
      model = "gpt-5.5",
      ask_model = "gpt-5.4-mini",
    },
  },
  patterns = {
    open_tag = "/@",
    close_tag = "@/",
    file_pattern = "*.codetyper.*",
  },
  keymaps = {
    transform = "<leader>ctt",
    model = "<leader>ctm",
    terminal = "<leader>ter",
  },
})
```

The supported provider names are exactly `ollama`, `copilot`, `claude`, and
`openai`. Configuration validation rejects unsupported providers, malformed
provider blocks, and non-canonical companion patterns.

`smart_selection` affects selection strategy; it does not silently replace an
explicit provider. An explicit provider or qualified model such as
`copilot/gpt-4o`, `ollama/llama3:8b`, `claude/claude-sonnet-4-5`, or
`openai/gpt-5.5` remains authoritative. Automatic provider resolution checks
Copilot authentication first and uses reachable Ollama only as a fallback.

## Providers and credentials

### GitHub Copilot

Codetyper can reuse Copilot credentials from `copilot.lua` or `copilot.vim`.
`:CoderAuth` validates the token exchange first and starts the device flow only
when authentication is unavailable. Copilot model discovery is provider
specific and cancellable.

### Ollama

Ollama is a local HTTP provider and the automatic fallback when Copilot is not
authenticated. It can also be selected explicitly:

```lua
llm = {
  provider = "ollama",
  ollama = { host = "http://localhost:11434", model = "gemma4:26b" },
}
```

### Anthropic Claude

Claude reads only the inherited `ANTHROPIC_API_KEY`. The key is sent in memory
as `x-api-key`; it is not saved in Codetyper metadata and is not requested by
the UI. Claude supports non-streaming text generation without native tools.

### ChatGPT Plus/Pro

The `openai` provider uses ChatGPT subscription OAuth, not an OpenAI API key:

```vim
:Coder auth openai browser
:Coder auth openai device
```

OAuth tokens, account identity, residency, request headers, and `OPENAI_API_KEY`
are not persisted or interpreted as subscription credentials. Re-authentication
is required after restart; only the selected model preference may be stored.

Provider metadata and model preferences are stored in
`~/.local/share/nvim/codetyper/configuration.json`. Legacy secret fields are
scrubbed when metadata is read.

## Context and agent tools

The registry contains exactly these six canonical tools:

| Tool | Purpose | Safety boundary |
| --- | --- | --- |
| `codegraph_context(query,max_nodes,no_code)` | Read initialized CodeGraph context | Fixed argv; status checked first; read-only `context`/`explore` only |
| `tokensave_search(query,limit)` | Search the current TokenSave index | Requires project markers and branch mapping; no database access |
| `context7_resolve_library(query)` | Resolve a documentation library | Context7 `resolve-library-id` only |
| `context7_query_docs(library_id,query)` | Query resolved documentation | Context7 `query-docs` only |
| `ask_user(question,options)` | Ask the developer to choose | Bounded popup; no shell, file, or provider side effects |
| `add_import(path,statement)` | Insert one safe declaration | Project-relative source file or open buffer; one-line validated declaration |

Every tool returns bounded `{status,data,error,stale}` metadata. Results are
limited to 4000 encoded characters. Missing integrations degrade to
`unavailable` or `stale`; they do not trigger setup, synchronization, daemon,
database, or indexing commands.

### CodeGraph and TokenSave

CodeGraph runs only fixed argv operations equivalent to:

```text
codegraph status --json <root>
codegraph context <query> --path <root> --format json --max-nodes <n> [--no-code]
```

TokenSave checks `.tokensave/config.json`, `.tokensave/branch-meta.json`, the
current Git branch, and readiness status before running its read-only search.
Both adapters use argv arrays rather than shell strings, bound stdout/stderr,
redact sensitive diagnostics, and suppress late callbacks after cancellation.

### Context7

Context7 first uses a ready `mcphub.nvim` Context7 server. The fallback uses
only the fixed endpoint `https://mcp.context7.com/mcp`, performs the bounded
initialize/session/list/call protocol, accepts JSON or SSE, and allowlists only
`resolve-library-id` and `query-docs`. Set `CONTEXT7_API_KEY` when the fallback
requires authentication. URLs, headers, sessions, payloads, and credentials
are not stored in result metadata.

### Interactive and import behavior

The `ask_user` popup displays at most eight options. Use `<Up>`/`<Down>` and
`<CR>` to select, or `<Esc>` to cancel. Interactive and mutating calls are
serialized FIFO and callbacks complete exactly once.

`add_import` supports JavaScript/TypeScript, Python, Lua, Go, Rust, C/C++,
Java/Kotlin, Ruby, and PHP. It preserves shebangs, headers, package/namespace
metadata, line endings, and unsaved open-buffer content. Traversal, absolute
paths, documentation files, remote references, multiline declarations, and
ambiguous or unsupported declarations are rejected without mutation.

### Native and marker dispatch

Native structured schemas are sent only to tool-capable Copilot project tasks.
Claude, OpenAI, and Ollama receive no native tool schemas. The validated text
markers are:

```text
TOOL:CODEGRAPH {"query":"request","max_nodes":20}
TOOL:TOKENSAVE {"query":"request","limit":10}
TOOL:CONTEXT7_RESOLVE {"query":"neovim"}
TOOL:CONTEXT7_QUERY {"library_id":"/neovim/neovim","query":"autocmd"}
TOOL:ASK_USER {"question":"Continue?","options":["Yes","No"]}
TOOL:ADD_IMPORT {"path":"lua/app.lua","statement":"local M = {}"}
```

Terminal calls remain visible and pass the terminal safety check. MCP calls are
limited to the installed, filtered MCP tool list; filesystem and shell MCP
tools are excluded from the native API boundary.

## Commands and keymaps

| Command | Purpose |
| --- | --- |
| `:Coder` | Main dispatcher; defaults to `version` |
| `:Coder transform-selection` | Open the transform prompt |
| `:Coder index-project` / `:Coder index-status` | Manage project index state |
| `:Coder model [provider/model]` | Select a provider-labelled model |
| `:Coder auth` | Authenticate Copilot |
| `:Coder auth openai browser/device` | Authenticate ChatGPT subscription |
| `:Coder credentials` / `:Coder switch-provider` | Inspect or change provider state |
| `:Coder terminal` / `:Coder queue` | Toggle the terminal or prompt queue |
| `:Coder process` / `:Coder autotrigger` | Process tags or toggle automatic processing |
| `:Coder cost` / `:Coder cost-clear` | View or clear usage costs |
| `:Coder llm-stats` / `:Coder llm-reset-stats` | View or clear accuracy statistics |
| `:CoderTransformSelection` | Standalone transform command |
| `:CoderModel` | Standalone model selector |
| `:CoderCredentials` | Standalone credentials status |
| `:CoderSwitchProvider` | Standalone provider switcher |
| `:CoderAuth` | Standalone Copilot authentication |

Default mappings are `<leader>ctt` for transform, `<leader>ctm` for model
selection, and `<leader>ter` for the terminal. Set a mapping to `false` to
disable it without affecting the others.

Conflict review uses `co` (current), `ct` (incoming), `cb` (both), `cn` (none),
`cm` (menu), `]x` (next), and `[x` (previous) while a conflict is active.

## Troubleshooting

- Run `:checkhealth codetyper` and inspect `:messages`.
- If a provider is unavailable, verify its explicit configuration and provider
  credentials; explicit selections are not silently replaced.
- If CodeGraph or TokenSave is stale, check the executable, project markers,
  current branch, and index status. Codetyper will not initialize or sync them.
- If Context7 is unavailable, install/configure MCPHub or set
  `CONTEXT7_API_KEY` for the fixed fallback endpoint.
- If a tool is missing from a prompt, check its availability state and whether
  the request is an eligible Copilot project task.
- Use `make test-file FILE=tests/spec/foo_spec.lua` when reporting a focused
  regression.

## Development and tests

The suite runs headless Plenary tests with injected network, CLI, popup, and
provider fakes. No test requires real credentials, external binaries, a
database, an MCP server, or network access.

```bash
make test
make test-file FILE=tests/spec/context7_spec.lua
make lint
make format-check
make docs
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for the workflow and
[SECURITY.md](SECURITY.md) for reporting guidance.

## License

MIT. See [LICENSE](LICENSE).
