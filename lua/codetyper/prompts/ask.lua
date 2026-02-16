---@mod codetyper.prompts.ask Ask / explanation prompts for Codetyper.nvim
---
--- These prompts are used for the Ask panel and non-destructive explanations.

local M = {}

--- Prompt for explaining code
M.explain_code = [[You are explaining EXISTING code to a developer.

Code:
{{code}}

Instructions:
- Start with a concise high-level overview
- Explain important logic and structure
- Point out noteworthy implementation details
- Mention potential issues or limitations ONLY if clearly visible
- Do NOT speculate about missing context

Format the response in markdown.
]]

--- Prompt for explaining a specific function
M.explain_function = [[You are explaining an EXISTING function.

Function code:
{{code}}

Explain:
- What the function does and when it is used
- The purpose of each parameter
- The return value, if any
- Side effects or assumptions
- A brief usage example if appropriate

Format the response in markdown.
Do NOT suggest refactors unless explicitly asked.
]]

--- Prompt for explaining an error
M.explain_error = [[You are helping diagnose a real error.

Error message:
{{error}}

Relevant code:
{{code}}

Instructions:
- Explain what the error message means
- Identify the most likely cause based on the code
- Suggest concrete fixes or next debugging steps
- If multiple causes are possible, say so clearly

Format the response in markdown.
Do NOT invent missing stack traces or context.
]]

--- Prompt for code review
M.code_review = [[You are performing a code review on EXISTING code.

Code:
{{code}}

Review criteria:
- Readability and clarity
- Correctness and potential bugs
- Performance considerations where relevant
- Security concerns only if applicable
- Practical improvement suggestions

Guidelines:
- Be constructive and specific
- Do NOT nitpick style unless it impacts clarity
- Do NOT suggest large refactors unless justified

Format the response in markdown.
]]

--- Prompt for explaining a programming concept
M.explain_concept = [[Explain the following programming concept to a developer:

Concept:
{{concept}}

Include:
- A clear definition and purpose
- When and why it is used
- A simple illustrative example
- Common pitfalls or misconceptions

Format the response in markdown.
Avoid unnecessary jargon.
]]

--- Prompt for comparing approaches
M.compare_approaches = [[Compare the following approaches:

{{approaches}}

Analysis guidelines:
- Describe strengths and weaknesses of each
- Discuss performance or complexity tradeoffs if relevant
- Compare maintainability and clarity
- Explain when one approach is preferable over another

Format the response in markdown.
Base comparisons on general principles unless specific code is provided.
]]

--- Prompt for debugging help
M.debug_help = [[You are helping debug a concrete issue.

Problem description:
{{problem}}

Code:
{{code}}

What has already been tried:
{{attempts}}

Instructions:
- Identify likely root causes
- Explain why the issue may be occurring
- Suggest specific debugging steps or fixes
- Call out missing information if needed

Format the response in markdown.
Do NOT guess beyond the provided information.
]]

--- Prompt for architecture advice
M.architecture_advice = [[You are providing architecture guidance.

Question:
{{question}}

Context:
{{context}}

Instructions:
- Recommend a primary approach
- Explain the reasoning and tradeoffs
- Mention viable alternatives when relevant
- Highlight risks or constraints to consider

Format the response in markdown.
Avoid dogmatic or one-size-fits-all answers.
]]

--- Generic ask prompt
M.generic = [[You are answering a developer's question.

Question:
{{question}}

{{#if files}}
Relevant file contents:
{{files}}
{{/if}}

{{#if context}}
Additional context:
{{context}}
{{/if}}

Instructions:
- Be accurate and grounded in the provided information
- Clearly state assumptions or uncertainty
- Prefer clarity over verbosity
- Do NOT output raw code intended for insertion unless explicitly asked

Format the response in markdown.
]]

return M
