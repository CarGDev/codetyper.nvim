---@mod codetyper.prompts.code Code generation prompts for Codetyper.nvim
---
--- These prompts are used for generating new code.

local M = {}

--- Prompt template for creating a new function
M.create_function = [[Create a function with the following requirements:

{{description}}

Requirements:
- Follow the coding style of the existing file
- Include proper error handling
- Use appropriate types (if applicable)
- Make it efficient and readable

OUTPUT ONLY THE RAW CODE. No explanations, no markdown, no code fences.
]]

--- Prompt template for creating a new class/module
M.create_class = [[Create a class/module with the following requirements:

{{description}}

Requirements:
- Follow OOP best practices
- Include constructor/initialization
- Implement proper encapsulation
- Add necessary methods as described

OUTPUT ONLY THE RAW CODE. No explanations, no markdown, no code fences.
]]

--- Prompt template for implementing an interface/trait
M.implement_interface = [[Implement the following interface/trait:

{{description}}

Requirements:
- Implement all required methods
- Follow the interface contract exactly
- Handle edge cases appropriately

OUTPUT ONLY THE RAW CODE. No explanations, no markdown, no code fences.
]]

--- Prompt template for creating a React component
M.create_react_component = [[Create a React component with the following requirements:

{{description}}

Requirements:
- Use functional components with hooks
- Include proper TypeScript types (if .tsx)
- Follow React best practices
- Make it reusable and composable

OUTPUT ONLY THE RAW CODE. No explanations, no markdown, no code fences.
]]

--- Prompt template for creating an API endpoint
M.create_api_endpoint = [[Create an API endpoint with the following requirements:

{{description}}

Requirements:
- Include input validation
- Proper error handling and status codes
- Follow RESTful conventions
- Include appropriate middleware

OUTPUT ONLY THE RAW CODE. No explanations, no markdown, no code fences.
]]

--- Prompt template for creating a utility function
M.create_utility = [[Create a utility function:

{{description}}

Requirements:
- Pure function (no side effects) if possible
- Handle edge cases
- Efficient implementation
- Well-typed (if applicable)

OUTPUT ONLY THE RAW CODE. No explanations, no markdown, no code fences.
]]

--- Prompt template for generic code generation
M.generic = [[Generate code based on the following description:

{{description}}

Context:
- Language: {{language}}
- File: {{filepath}}

Requirements:
- Match existing code style
- Follow best practices
- Handle errors appropriately

OUTPUT ONLY THE RAW CODE. No explanations, no markdown, no code fences.
]]

return M
