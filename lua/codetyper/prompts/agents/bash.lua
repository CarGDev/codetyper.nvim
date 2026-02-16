M.description = [[Executes a bash command in a shell.

IMPORTANT RULES:
- Do NOT use bash to read files (use 'view' tool instead)
- Do NOT use bash to modify files (use 'write' or 'edit' tools instead)
- Do NOT use interactive commands (vim, nano, less, etc.)
- Commands timeout after 2 minutes by default

Allowed uses:
- Running builds (make, npm run build, cargo build)
- Running tests (npm test, pytest, cargo test)
- Git operations (git status, git diff, git commit)
- Package management (npm install, pip install)
- System info commands (ls, pwd, which)]]

return M
