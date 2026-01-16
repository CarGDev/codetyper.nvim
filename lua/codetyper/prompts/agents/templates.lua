---@mod codetyper.prompts.agents.templates Agent and Rule templates
local M = {}

M.agent = [[---
description: Example custom agent
tools: view,grep,glob,edit,write
model:
---

# Custom Agent

You are a custom coding agent. Describe your specialized behavior here.

## Your Role
- Define what this agent specializes in
- List specific capabilities

## Guidelines
- Add agent-specific rules
- Define coding standards to follow

## Examples
Provide examples of how to handle common tasks.
]]

M.rule = [[# Code Style

Follow these coding standards:

## General
- Use consistent indentation (tabs or spaces based on project)
- Keep lines under 100 characters
- Add comments for complex logic

## Naming Conventions
- Use descriptive variable names
- Functions should be verbs (e.g., getUserData, calculateTotal)
- Constants in UPPER_SNAKE_CASE

## Testing
- Write tests for new functionality
- Aim for >80% code coverage
- Test edge cases

## Documentation
- Document public APIs
- Include usage examples
- Keep docs up to date with code
]]

return M
