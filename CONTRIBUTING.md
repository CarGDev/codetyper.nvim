# Contributing to Codetyper.nvim

Thank you for helping improve Codetyper.nvim. Keep changes small, observable,
and safe at the boundary between Neovim, providers, local tools, and files.

## Development setup

Prerequisites:

- Neovim 0.9 or newer
- LuaJIT or Lua 5.1-compatible tooling
- Git
- `make`
- Plenary.nvim available to the headless test bootstrap
- StyLua and Luacheck for formatting and linting

A real LLM provider, CodeGraph, TokenSave, MCPHub, database, or network access
is not required for tests. Specs inject fakes for HTTP, CLI, MCP, providers,
buffers, popups, and cancellation.

Clone the repository and inspect the available commands:

```bash
cd codetyper.nvim
make check-deps
```

## Project structure

```text
lua/codetyper/
├── core/agent/                 parser, executor, loop, MCP, tool registry
├── core/llm/                   providers, selection, shared HTTP/context
├── core/scheduler/             event scheduling and worker flow
├── core/transform.lua          prompt window and selection handling
├── features/indexer/           project index and memory context
├── inject/                     deterministic buffer insertion
├── prompts/tiers/              agent, chat, and basic prompt builders
├── window/                     conflict, cost, queue, terminal, ask-user UI
├── adapters/nvim/              commands, keymaps, and Neovim UI glue
├── config/                     defaults, provider state, and credentials
└── params/                     language and subsystem definitions
tests/spec/                     headless Plenary specs
doc/codetyper.txt               Vim help
```

The canonical agent registry is
`lua/codetyper/core/agent/tools/init.lua`. It owns only:

```text
codegraph_context
tokensave_search
context7_resolve_library
context7_query_docs
ask_user
add_import
```

Preserve the separation between registry tools, terminal commands, and external
MCP tools. Do not widen an allowlist merely to make a test or integration pass.

## Making changes

1. Create a focused branch.
2. Read the relevant source, tests, help text, and configuration contract.
3. For behavior changes, write a failing focused test first.
4. Implement the smallest change that makes the test pass.
5. Add an edge case or second path when the behavior branches.
6. Run focused tests, then the full available checks.
7. Update user-facing documentation and `CHANGELOG.md` for notable changes.
8. Regenerate `doc/tags` after editing `doc/codetyper.txt`.

Avoid unrelated formatting or generated-file changes. Never include credentials,
tokens, private URLs, or user project data in tests, logs, fixtures, or commits.

## Tests and quality checks

```bash
make test
make test-file FILE=tests/spec/http_boundary_spec.lua
make lint
make format-check
make docs
```

The test suite is deterministic and headless. Boundary specs must use fakes:

- HTTP tests replace `vim.fn.jobstart` and must never make a network request.
- Local context tests inject argv runners and must never run indexing, sync,
  daemon, shell, or database operations.
- Context7 tests inject MCPHub/HTTP transports and must not use live secrets.
- Popup tests drive headless floats or injectable UI callbacks.
- Provider tests inject transports and verify secret-free persistence/logging.

When changing an async boundary, test cancellation, timeout, late callbacks,
and exactly-once completion. When changing a parser or tool boundary, test
malformed input, bounds, allowlists, and no-mutation behavior.

## Documentation

Update the relevant section in `README.md`, `llm.txt`, and
`doc/codetyper.txt` when public behavior changes. Keep these claims aligned:

- supported providers are `copilot`, `ollama`, `claude`, and `openai`;
- native structured tools are limited to eligible Copilot project tasks;
- Claude uses environment-only `ANTHROPIC_API_KEY`;
- OpenAI means ChatGPT subscription OAuth, not `OPENAI_API_KEY`;
- Context7 is MCPHub-first with a fixed read-only fallback;
- CodeGraph and TokenSave adapters are read-only and fail closed;
- import paths and declarations are bounded and project-relative; and
- tests use network/CLI/DB-free fakes.

After help changes:

```bash
make docs
```

## Style guide

- Use two spaces for Lua indentation, matching the repository formatter.
- Use `snake_case` for Lua variables and functions.
- Keep modules focused and prefer pure helpers for validation and transformations.
- Add LuaCATS annotations to public functions when practical.
- Keep comments concise and describe safety boundaries or non-obvious behavior.
- Use English for code comments and project documentation.

Commit messages should use a conventional prefix, for example:

```text
feat(tools): add bounded project context adapter
```

## Pull requests

Describe the user-visible behavior, safety impact, and rollback boundary. Include
the exact focused test command and result, plus full-suite/lint/format/docs
results when available. Call out unavailable external integrations rather than
silently substituting live services.

Checklist:

- [ ] Focused tests pass
- [ ] Full test suite passes when available
- [ ] Lint and format checks pass
- [ ] Documentation and changelog are updated when needed
- [ ] `doc/tags` was regenerated after help changes
- [ ] No credentials or private project data are included

For security-sensitive changes, follow [SECURITY.md](SECURITY.md) instead of
publishing exploit details in a public issue.
