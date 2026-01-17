---@mod codetyper.prompts.agents.bash Bash tool description
local M = {}

M.description = [[Executes a shell command in bash.

Usage notes:
- Provide the command to execute
- Optionally specify working directory (cwd)
- Optionally specify timeout in milliseconds (default: 120000)
- Returns the command output (stdout and stderr combined)
- Exit code 0 indicates success, non-zero indicates failure

SAFETY:
- Dangerous commands (rm -rf /, sudo, etc.) are blocked
- All commands require user approval before execution
- Commands run in a sandboxed environment when possible

Examples:
- List files: {"command": "ls -la"}
- Run tests: {"command": "npm test", "cwd": "/path/to/project"}
- Check git status: {"command": "git status"}]]

return M
