---@mod codetyper.prompts.document Documentation prompts for Codetyper.nvim
---
--- These prompts are used for scoped, non-destructive documentation generation.

local M = {}

--- Prompt for adding JSDoc comments
M.jsdoc = [[You are adding JSDoc documentation to EXISTING JavaScript or TypeScript code.

The documentation will be INSERTED at the appropriate locations.

Requirements:
- Document only functions, methods, and types that already exist
- Include @param for all parameters
- Include @returns only if the function returns a value
- Include @throws ONLY if errors are actually thrown
- Use @typedef or @type only when types already exist implicitly
- Do NOT invent new behavior or APIs
- Do NOT change the underlying code

OUTPUT ONLY VALID JSDOC COMMENTS. No explanations, no markdown, no code fences.
]]

--- Prompt for adding Python docstrings
M.python_docstring = [[You are adding docstrings to EXISTING Python code.

The documentation will be INSERTED into existing functions or classes.

Requirements:
- Use Google-style docstrings
- Document only functions and classes that already exist
- Include Args, Returns, and Raises sections ONLY when applicable
- Do NOT invent parameters, return values, or exceptions
- Do NOT change the code logic

OUTPUT ONLY VALID PYTHON DOCSTRINGS. No explanations, no markdown.
]]

--- Prompt for adding LuaDoc / EmmyLua comments
M.luadoc = [[You are adding LuaDoc / EmmyLua annotations to EXISTING Lua code.

The documentation will be INSERTED above existing definitions.

Requirements:
- Use ---@param only for existing parameters
- Use ---@return only for actual return values
- Use ---@class and ---@field only when structures already exist
- Keep descriptions accurate and minimal
- Do NOT add new code or behavior

OUTPUT ONLY VALID LUADOC / EMMYLUA COMMENTS. No explanations, no markdown.
]]

--- Prompt for adding Go documentation
M.godoc = [[You are adding GoDoc comments to EXISTING Go code.

The documentation will be INSERTED above existing declarations.

Requirements:
- Start each comment with the name being documented
- Document only exported functions, types, and variables
- Describe what the code does, not how it is implemented
- Do NOT invent behavior or usage

OUTPUT ONLY VALID GODoc COMMENTS. No explanations, no markdown.
]]

--- Prompt for generating README documentation
M.readme = [[You are generating a README for an EXISTING codebase.

The README will be CREATED or REPLACED as a standalone document.

Requirements:
- Describe only functionality that exists in the provided code
- Include installation and usage only if they can be inferred safely
- Do NOT speculate about features or roadmap
- Keep the README concise and accurate

OUTPUT ONLY RAW README CONTENT. No markdown fences, no explanations.
]]

--- Prompt for adding inline comments
M.inline_comments = [[You are adding inline comments to EXISTING code.

The comments will be INSERTED without modifying code logic.

Guidelines:
- Explain complex or non-obvious logic only
- Do NOT comment trivial or self-explanatory code
- Do NOT restate what the code already clearly says
- Do NOT introduce TODO or FIXME unless explicitly requested

OUTPUT ONLY VALID INLINE COMMENTS. No explanations, no markdown.
]]

--- Prompt for adding API documentation
M.api_docs = [[You are generating API documentation for EXISTING code.

The documentation will be INSERTED or GENERATED as appropriate.

Requirements:
- Document only endpoints or functions that exist
- Describe parameters and return values accurately
- Include examples ONLY when behavior is unambiguous
- Describe error cases only if they are explicitly handled in code
- Do NOT invent request/response shapes

OUTPUT ONLY RAW API DOCUMENTATION CONTENT. No explanations, no markdown.
]]

--- Prompt for adding type definitions
M.type_definitions = [[You are generating type definitions for EXISTING code.

The types will be INSERTED or GENERATED alongside existing code.

Requirements:
- Define types only for data structures that already exist
- Mark optional properties accurately
- Do NOT introduce new runtime behavior
- Match the typing style already used in the project

OUTPUT ONLY VALID TYPE DEFINITIONS. No explanations, no markdown.
]]

--- Prompt for generating a changelog entry
M.changelog = [[You are generating a changelog entry for EXISTING changes.

Requirements:
- Reflect ONLY the provided changes
- Use a conventional changelog format
- Categorize changes accurately (Added, Changed, Fixed, Removed)
- Highlight breaking changes clearly if present
- Do NOT speculate or add future work

OUTPUT ONLY RAW CHANGELOG TEXT. No explanations, no markdown.
]]

--- Generic documentation prompt
M.generic = [[You are adding documentation to EXISTING code.

Language: {{language}}

Requirements:
- Use the correct documentation format for the language
- Document only public APIs that already exist
- Describe parameters, return values, and errors accurately
- Do NOT invent behavior, examples, or features

OUTPUT ONLY VALID DOCUMENTATION CONTENT. No explanations, no markdown.
]]

return M
