---@mod codetyper.prompts.document Documentation prompts for Codetyper.nvim
---
--- These prompts are used for generating documentation.

local M = {}

--- Prompt for adding JSDoc comments
M.jsdoc = [[Add JSDoc documentation to this code:

{{code}}

Requirements:
- Document all functions and methods
- Include @param for all parameters
- Include @returns for return values
- Add @throws if exceptions are thrown
- Include @example where helpful
- Use @typedef for complex types
]]

--- Prompt for adding Python docstrings
M.python_docstring = [[Add docstrings to this Python code:

{{code}}

Requirements:
- Use Google-style docstrings
- Document all functions and classes
- Include Args, Returns, Raises sections
- Add Examples where helpful
- Include type hints in docstrings
]]

--- Prompt for adding LuaDoc comments
M.luadoc = [[Add LuaDoc/EmmyLua annotations to this Lua code:

{{code}}

Requirements:
- Use ---@param for parameters
- Use ---@return for return values
- Use ---@class for table structures
- Use ---@field for class fields
- Add descriptions for all items
]]

--- Prompt for adding Go documentation
M.godoc = [[Add GoDoc comments to this Go code:

{{code}}

Requirements:
- Start comments with the name being documented
- Document all exported functions, types, and variables
- Keep comments concise but complete
- Follow Go documentation conventions
]]

--- Prompt for adding README documentation
M.readme = [[Generate README documentation for this code:

{{code}}

Include:
- Project description
- Installation instructions
- Usage examples
- API documentation
- Contributing guidelines
]]

--- Prompt for adding inline comments
M.inline_comments = [[Add helpful inline comments to this code:

{{code}}

Guidelines:
- Explain complex logic
- Document non-obvious decisions
- Don't state the obvious
- Keep comments concise
- Use TODO/FIXME where appropriate
]]

--- Prompt for adding API documentation
M.api_docs = [[Generate API documentation for this code:

{{code}}

Include for each endpoint/function:
- Description
- Parameters with types
- Return value with type
- Example request/response
- Error cases
]]

--- Prompt for adding type definitions
M.type_definitions = [[Generate type definitions for this code:

{{code}}

Requirements:
- Define interfaces/types for all data structures
- Include optional properties where appropriate
- Add JSDoc/docstring descriptions
- Export all types that should be public
]]

--- Prompt for changelog entry
M.changelog = [[Generate a changelog entry for these changes:

{{changes}}

Format:
- Use conventional changelog format
- Categorize as Added/Changed/Fixed/Removed
- Be concise but descriptive
- Include breaking changes prominently
]]

--- Generic documentation prompt
M.generic = [[Add documentation to this code:

{{code}}

Language: {{language}}

Requirements:
- Use appropriate documentation format for the language
- Document all public APIs
- Include parameter and return descriptions
- Add examples where helpful
]]

return M
