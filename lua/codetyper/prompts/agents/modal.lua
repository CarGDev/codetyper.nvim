---@mod codetyper.prompts.agents.modal Prompts and UI strings for context modal
local M = {}

--- Modal UI strings
M.ui = {
	files_header = { "", "-- No files detected in LLM response --" },
	llm_response_header = "-- LLM Response: --",
	suggested_commands_header = "-- Suggested commands: --",
	commands_hint = "-- Press <leader><n> to run a command, or <leader>r to run all --",
	input_header = "-- Enter additional context below (Ctrl-Enter to submit, Esc to cancel) --",
	project_inspect_header = { "", "-- Project inspection results --" },
}

return M
