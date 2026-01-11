---@mod codetyper.prompts.ask Ask/explanation prompts for Codetyper.nvim
---
--- These prompts are used for the Ask panel and code explanations.

local M = {}

--- Prompt for explaining code
M.explain_code = [[Please explain the following code:

{{code}}

Provide:
1. A high-level overview of what it does
2. Explanation of key parts
3. Any potential issues or improvements
]]

--- Prompt for explaining a specific function
M.explain_function = [[Explain this function in detail:

{{code}}

Include:
1. What the function does
2. Parameters and their purposes
3. Return value
4. Any side effects
5. Usage examples
]]

--- Prompt for explaining an error
M.explain_error = [[I'm getting this error:

{{error}}

In this code:

{{code}}

Please explain:
1. What the error means
2. Why it's happening
3. How to fix it
]]

--- Prompt for code review
M.code_review = [[Please review this code:

{{code}}

Provide feedback on:
1. Code quality and readability
2. Potential bugs or issues
3. Performance considerations
4. Security concerns (if applicable)
5. Suggested improvements
]]

--- Prompt for explaining a concept
M.explain_concept = [[Explain the following programming concept:

{{concept}}

Include:
1. Definition and purpose
2. When and why to use it
3. Simple code examples
4. Common pitfalls to avoid
]]

--- Prompt for comparing approaches
M.compare_approaches = [[Compare these different approaches:

{{approaches}}

Analyze:
1. Pros and cons of each
2. Performance implications
3. Maintainability
4. When to use each approach
]]

--- Prompt for debugging help
M.debug_help = [[Help me debug this issue:

Problem: {{problem}}

Code:
{{code}}

What I've tried:
{{attempts}}

Please help identify the issue and suggest a solution.
]]

--- Prompt for architecture advice
M.architecture_advice = [[I need advice on this architecture decision:

{{question}}

Context:
{{context}}

Please provide:
1. Recommended approach
2. Reasoning
3. Potential alternatives
4. Things to consider
]]

--- Generic ask prompt
M.generic = [[USER QUESTION: {{question}}

{{#if files}}
ATTACHED FILE CONTENTS:
{{files}}
{{/if}}

{{#if context}}
ADDITIONAL CONTEXT:
{{context}}
{{/if}}

Please provide a helpful, accurate response.
]]

return M
