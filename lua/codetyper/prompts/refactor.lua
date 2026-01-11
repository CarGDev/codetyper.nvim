---@mod codetyper.prompts.refactor Refactoring prompts for Codetyper.nvim
---
--- These prompts are used for code refactoring operations.

local M = {}

--- Prompt for general refactoring
M.general = [[Refactor this code to improve its quality:

{{code}}

Focus on:
- Readability
- Maintainability
- Following best practices
- Keeping the same functionality
]]

--- Prompt for extracting a function
M.extract_function = [[Extract a function from this code:

{{code}}

The function should:
{{description}}

Requirements:
- Give it a meaningful name
- Include proper parameters
- Return appropriate values
]]

--- Prompt for simplifying code
M.simplify = [[Simplify this code while maintaining functionality:

{{code}}

Goals:
- Reduce complexity
- Remove redundancy
- Improve readability
- Keep all existing behavior
]]

--- Prompt for converting to async/await
M.async_await = [[Convert this code to use async/await:

{{code}}

Requirements:
- Convert all promises to async/await
- Maintain error handling
- Keep the same functionality
]]

--- Prompt for adding error handling
M.add_error_handling = [[Add proper error handling to this code:

{{code}}

Requirements:
- Handle all potential errors
- Use appropriate error types
- Add meaningful error messages
- Don't change core functionality
]]

--- Prompt for improving performance
M.optimize_performance = [[Optimize this code for better performance:

{{code}}

Focus on:
- Algorithm efficiency
- Memory usage
- Reducing unnecessary operations
- Maintaining readability
]]

--- Prompt for converting to TypeScript
M.convert_to_typescript = [[Convert this JavaScript code to TypeScript:

{{code}}

Requirements:
- Add proper type annotations
- Use interfaces where appropriate
- Handle null/undefined properly
- Maintain all functionality
]]

--- Prompt for applying design pattern
M.apply_pattern = [[Refactor this code to use the {{pattern}} pattern:

{{code}}

Requirements:
- Properly implement the pattern
- Maintain existing functionality
- Improve code organization
]]

--- Prompt for splitting a large function
M.split_function = [[Split this large function into smaller, focused functions:

{{code}}

Goals:
- Single responsibility per function
- Clear function names
- Proper parameter passing
- Maintain all functionality
]]

--- Prompt for removing code smells
M.remove_code_smells = [[Refactor this code to remove code smells:

{{code}}

Look for and fix:
- Long methods
- Duplicated code
- Magic numbers
- Deep nesting
- Other anti-patterns
]]

return M
