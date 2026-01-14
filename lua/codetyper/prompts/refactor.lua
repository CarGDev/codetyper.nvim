---@mod codetyper.prompts.refactor Refactoring prompts for Codetyper.nvim
---
--- These prompts are used for scoped, non-destructive refactoring operations.

local M = {}

--- Prompt for general refactoring
M.general = [[You are refactoring a SPECIFIC REGION of existing code.

The provided code will be REPLACED by your output.

Goals:
- Improve readability and maintainability
- Preserve ALL existing behavior
- Follow the coding style already present
- Keep changes minimal and justified

Constraints:
- Do NOT change public APIs unless explicitly required
- Do NOT introduce new dependencies
- Do NOT refactor unrelated logic
- Do NOT add comments unless explicitly requested

OUTPUT ONLY THE FULL REFACTORED CODE FOR THIS REGION. No explanations, no markdown, no code fences.
]]

--- Prompt for extracting a function
M.extract_function = [[You are extracting a function from an EXISTING CODE REGION.

The provided code will be REPLACED by your output.

Instructions:
{{description}}

Constraints:
- Preserve behavior exactly
- Extract ONLY the logic required
- Choose a name consistent with existing naming conventions
- Do NOT introduce new abstractions beyond the extracted function
- Keep parameter order and data flow explicit

OUTPUT ONLY THE FULL UPDATED CODE FOR THIS REGION. No explanations, no markdown, no code fences.
]]

--- Prompt for simplifying code
M.simplify = [[You are simplifying an EXISTING CODE REGION.

The provided code will be REPLACED by your output.

Goals:
- Reduce unnecessary complexity
- Remove redundancy
- Improve clarity without changing behavior

Constraints:
- Do NOT change function signatures unless required
- Do NOT alter control flow semantics
- Do NOT refactor unrelated logic

OUTPUT ONLY THE FULL SIMPLIFIED CODE FOR THIS REGION. No explanations, no markdown, no code fences.
]]

--- Prompt for converting to async/await
M.async_await = [[You are converting an EXISTING CODE REGION to async/await syntax.

The provided code will be REPLACED by your output.

Requirements:
- Convert promise-based logic to async/await
- Preserve existing error handling semantics
- Maintain return values and control flow
- Match existing async patterns in the file

Constraints:
- Do NOT introduce new behavior
- Do NOT change public APIs unless required
- Do NOT refactor unrelated code

OUTPUT ONLY THE FULL UPDATED CODE FOR THIS REGION. No explanations, no markdown, no code fences.
]]

--- Prompt for adding error handling
M.add_error_handling = [[You are adding error handling to an EXISTING CODE REGION.

The provided code will be REPLACED by your output.

Requirements:
- Handle realistic failure cases for the existing logic
- Follow error-handling patterns already used in the file
- Preserve normal execution paths

Constraints:
- Do NOT change core logic
- Do NOT introduce new error types unless necessary
- Do NOT add logging unless explicitly requested

OUTPUT ONLY THE FULL UPDATED CODE FOR THIS REGION. No explanations, no markdown, no code fences.
]]

--- Prompt for improving performance
M.optimize_performance = [[You are optimizing an EXISTING CODE REGION for performance.

The provided code will be REPLACED by your output.

Goals:
- Improve algorithmic or operational efficiency
- Reduce unnecessary work or allocations
- Preserve readability where possible

Constraints:
- Preserve ALL existing behavior
- Do NOT introduce premature optimization
- Do NOT change public APIs
- Do NOT refactor unrelated logic

OUTPUT ONLY THE FULL OPTIMIZED CODE FOR THIS REGION. No explanations, no markdown, no code fences.
]]

--- Prompt for converting JavaScript to TypeScript
M.convert_to_typescript = [[You are converting an EXISTING JavaScript CODE REGION to TypeScript.

The provided code will be REPLACED by your output.

Requirements:
- Add accurate type annotations
- Use interfaces or types only when they clarify intent
- Handle null and undefined explicitly where required

Constraints:
- Do NOT change runtime behavior
- Do NOT introduce types that alter semantics
- Match TypeScript style already used in the project

OUTPUT ONLY THE FULL TYPESCRIPT CODE FOR THIS REGION. No explanations, no markdown, no code fences.
]]

--- Prompt for applying a design pattern
M.apply_pattern = [[You are refactoring an EXISTING CODE REGION to apply the {{pattern}} pattern.

The provided code will be REPLACED by your output.

Requirements:
- Apply the pattern correctly and idiomatically
- Preserve ALL existing behavior
- Improve structure only where justified by the pattern

Constraints:
- Do NOT over-abstract
- Do NOT introduce unnecessary indirection
- Do NOT modify unrelated code

OUTPUT ONLY THE FULL UPDATED CODE FOR THIS REGION. No explanations, no markdown, no code fences.
]]

--- Prompt for splitting a large function
M.split_function = [[You are splitting an EXISTING LARGE FUNCTION into smaller functions.

The provided code will be REPLACED by your output.

Goals:
- Each function has a single, clear responsibility
- Names reflect existing naming conventions
- Data flow remains explicit and understandable

Constraints:
- Preserve external behavior exactly
- Do NOT change the public API unless required
- Do NOT introduce unnecessary abstraction layers

OUTPUT ONLY THE FULL UPDATED CODE FOR THIS REGION. No explanations, no markdown, no code fences.
]]

--- Prompt for removing code smells
M.remove_code_smells = [[You are refactoring an EXISTING CODE REGION to remove code smells.

The provided code will be REPLACED by your output.

Focus on:
- Reducing duplication
- Simplifying long or deeply nested logic
- Removing magic numbers where appropriate

Constraints:
- Preserve ALL existing behavior
- Do NOT introduce speculative refactors
- Do NOT refactor beyond the provided region

OUTPUT ONLY THE FULL CLEANED CODE FOR THIS REGION. No explanations, no markdown, no code fences.
]]

return M
