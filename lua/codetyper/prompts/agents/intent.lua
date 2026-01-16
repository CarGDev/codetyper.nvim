---@mod codetyper.prompts.agents.intent Intent-specific system prompts
local M = {}

M.modifiers = {
	complete = [[
You are completing an incomplete function.
Return the complete function with all missing parts filled in.
Keep the existing signature unless changes are required.
Output only the code, no explanations.]],

	refactor = [[
You are refactoring existing code.
Improve the code structure while maintaining the same behavior.
Keep the function signature unchanged.
Output only the refactored code, no explanations.]],

	fix = [[
You are fixing a bug in the code.
Identify and correct the issue while minimizing changes.
Preserve the original intent of the code.
Output only the fixed code, no explanations.]],

	add = [[
You are adding new code.
Follow the existing code style and conventions.
Output only the new code to be inserted, no explanations.]],

	document = [[
You are adding documentation to the code.
Add appropriate comments/docstrings for the function.
Include parameter types, return types, and description.
Output the complete function with documentation.]],

	test = [[
You are generating tests for the code.
Create comprehensive unit tests covering edge cases.
Follow the testing conventions of the project.
Output only the test code, no explanations.]],

	optimize = [[
You are optimizing code for performance.
Improve efficiency while maintaining correctness.
Document any significant algorithmic changes.
Output only the optimized code, no explanations.]],

	explain = [[
You are explaining code to a developer.
Provide a clear, concise explanation of what the code does.
Include information about the algorithm and any edge cases.
Do not output code, only explanation.]],
}

return M
