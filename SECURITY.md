# Security Policy

Codetyper.nvim can send source context to configured providers and can apply
model-requested edits. Report security issues privately and do not include
credentials, private source code, or an undisclosed exploit in a public issue.

## Supported versions

Security fixes target the latest released version and the current `main`
branch. Older releases may not receive backported fixes.

## Security boundaries

- Provider credentials are not part of prompts or persisted project metadata.
- Anthropic reads only inherited `ANTHROPIC_API_KEY` and keeps it in memory.
- ChatGPT subscription OAuth tokens and identity data are session-only;
  `OPENAI_API_KEY` is not interpreted for that provider.
- HTTP request bodies use temporary files that are removed after completion or
  cancellation; diagnostics redact sensitive values.
- CodeGraph and TokenSave use fixed argv commands, status checks, and bounded
  output. They do not initialize, synchronize, daemonize, or open databases.
- Context7 uses MCPHub first or the fixed HTTPS endpoint
  `https://mcp.context7.com/mcp`; only read-only resolve/query operations are
  allowed, and transport metadata is not persisted.
- Agent registry tools validate names, arguments, paths, bounds, and result
  sizes before execution. Import operations are project-relative and reject
  traversal, documentation paths, remote references, and multiline input.
- Terminal commands remain a visible separate boundary with dangerous command
  patterns blocked. MCP filesystem and shell tools are excluded from the
  native tool surface.
- Missing or stale integrations fail closed rather than triggering setup or
  indexing commands.

## Reporting a vulnerability

Preferred options:

1. Use a private GitHub Security Advisory for
   `cargdev/codetyper.nvim` when available.
2. If private advisories are unavailable, email
   `carlos.gutierrez@carg.dev` with the subject `Codetyper security report`.

Include:

- affected version or commit;
- a concise description of the impact;
- safe reproduction steps or a minimal proof of concept; and
- any suggested mitigation.

The maintainer will acknowledge a report as soon as practical, investigate it
privately, and coordinate disclosure after a fix or mitigation is available.
Please do not publicly disclose the issue before coordination.

## Secret handling for contributors

Use fake credentials and local fixtures in tests. Never commit API keys, OAuth
tokens, private endpoints, real user source, or generated logs containing
request data. If a secret is exposed, revoke or rotate it immediately and
report the exposure privately.
