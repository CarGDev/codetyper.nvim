---@mod codetyper.prompts.code Code generation prompts for Codetyper.nvim
---
--- These prompts are used for scoped, non-destructive code generation and transformation.

local M = {}

--- Prompt template for creating a new function (greenfield)
M.create_function = [[You are creating a NEW function inside an existing codebase.

Requirements:
{{description}}

Constraints:
- Follow the coding style and conventions of the surrounding file
- Choose names consistent with nearby code
- Include appropriate error handling if relevant
- Use correct and idiomatic types for the language
- Do NOT include code outside the function itself
- Do NOT add comments unless explicitly requested

OUTPUT ONLY THE RAW CODE OF THE FUNCTION. No explanations, no markdown, no code fences.
]]

--- Prompt template for completing an existing function
M.complete_function = [[You are completing an EXISTING function.

The function definition already exists and will be replaced by your output.

Instructions:
- Preserve the function signature unless completion is impossible without changing it
- Complete missing logic, TODOs, or placeholders
- Preserve naming, structure, and intent
- Do NOT refactor or reformat unrelated parts
- Do NOT add new public APIs unless explicitly required

OUTPUT ONLY THE FULL FUNCTION CODE. No explanations, no markdown, no code fences.
]]

--- Prompt template for creating a new class or module (greenfield)
M.create_class = [[You are creating a NEW class or module inside an existing project.

Requirements:
{{description}}

Constraints:
- Match the architectural and stylistic patterns of the project
- Include required initialization or constructors
- Expose only the necessary public surface
- Do NOT include unrelated helper code
- Do NOT include comments unless explicitly requested

OUTPUT ONLY THE RAW CLASS OR MODULE CODE. No explanations, no markdown, no code fences.
]]

--- Prompt template for modifying an existing class or module
M.modify_class = [[You are modifying an EXISTING class or module.

The provided code will be replaced by your output.

Instructions:
- Preserve the public API unless explicitly instructed otherwise
- Modify only what is required to satisfy the request
- Maintain method order and structure where possible
- Do NOT introduce unrelated refactors or stylistic changes

OUTPUT ONLY THE FULL UPDATED CLASS OR MODULE CODE. No explanations, no markdown, no code fences.
]]

--- Prompt template for implementing an interface or trait
M.implement_interface = [[You are implementing an interface or trait in an existing codebase.

Requirements:
{{description}}

Constraints:
- Implement ALL required methods exactly
- Match method signatures and order defined by the interface
- Do NOT add extra public methods
- Use idiomatic patterns for the target language
- Handle required edge cases only

OUTPUT ONLY THE RAW IMPLEMENTATION CODE. No explanations, no markdown, no code fences.
]]

--- Prompt template for creating a React component (greenfield)
M.create_react_component = [[You are creating a NEW React component within an existing project.

Requirements:
{{description}}

Constraints:
- Use the patterns already present in the codebase
- Prefer functional components if consistent with surrounding files
- Use hooks and TypeScript types only if already in use
- Do NOT introduce new architectural patterns
- Do NOT include comments unless explicitly requested

OUTPUT ONLY THE RAW COMPONENT CODE. No explanations, no markdown, no code fences.
]]

--- Prompt template for creating an API endpoint
M.create_api_endpoint = [[You are creating a NEW API endpoint in an existing backend codebase.

Requirements:
{{description}}

Constraints:
- Follow the conventions and framework already used in the project
- Validate inputs as required by existing patterns
- Use appropriate error handling and status codes
- Do NOT add middleware or routing changes unless explicitly requested
- Do NOT modify unrelated endpoints

OUTPUT ONLY THE RAW ENDPOINT CODE. No explanations, no markdown, no code fences.
]]

--- Prompt template for creating a utility function
M.create_utility = [[You are creating a NEW utility function.

Requirements:
{{description}}

Constraints:
- Prefer pure functions when possible
- Avoid side effects unless explicitly required
- Handle relevant edge cases only
- Match naming and style conventions of existing utilities

OUTPUT ONLY THE RAW FUNCTION CODE. No explanations, no markdown, no code fences.
]]

--- Prompt template for generic scoped code transformation
M.generic = [[You are modifying or generating code within an EXISTING file.

Context:
- Language: {{language}}
- File: {{filepath}}

Instructions:
{{description}}

Constraints:
- Operate ONLY on the provided scope
- Preserve existing structure and intent
- Do NOT modify code outside the target region
- Do NOT add explanations, comments, or formatting changes unless requested

OUTPUT ONLY THE RAW CODE THAT REPLACES THE TARGET SCOPE. No explanations, no markdown, no code fences.
]]

return M
