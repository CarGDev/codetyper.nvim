---@mod codetyper.prompts.agent.tools Tool system prompts
local M = {}

M.instructions = {
	intro = "You have access to the following tools. To use a tool, respond with a JSON block.",
	header = "To call a tool, output a JSON block like this:",
	example = [[
```json
{"tool": "tool_name", "parameters": {"param1": "value1"}}
```
]],
	footer = [[
After receiving tool results, continue your response or call another tool.
When you're done, just respond normally without any tool calls.
]],
}

return M
