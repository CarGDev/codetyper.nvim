---@mod codetyper.llm LLM interface for Codetyper.nvim

local M = {}
local lang_map = require("codetyper.utils.langmap")
local utils = require("codetyper.utils")

--- Get the appropriate LLM client based on configuration
---@return table LLM client module
function M.get_client()
	local codetyper = require("codetyper")
	local config = codetyper.get_config()

	if config.llm.provider == "ollama" then
		return require("codetyper.llm.ollama")
	elseif config.llm.provider == "openai" then
		return require("codetyper.llm.openai")
	elseif config.llm.provider == "gemini" then
		return require("codetyper.llm.gemini")
	elseif config.llm.provider == "copilot" then
		return require("codetyper.llm.copilot")
	else
		error("Unknown LLM provider: " .. config.llm.provider)
	end
end

--- Generate code from a prompt
---@param prompt string The user's prompt
---@param context table Context information (file content, language, etc.)
---@param callback fun(response: string|nil, error: string|nil) Callback function
function M.generate(prompt, context, callback)
	local client = M.get_client()
	client.generate(prompt, context, callback)
end

--- Smart generate with automatic provider selection based on brain memories
--- Prefers Ollama when context is rich, falls back to Copilot otherwise.
--- Implements verification pondering to reinforce Ollama accuracy over time.
---@param prompt string The user's prompt
---@param context table Context information
---@param callback fun(response: string|nil, error: string|nil, metadata: table|nil) Callback
function M.smart_generate(prompt, context, callback)
	local selector = require("codetyper.llm.selector")
	selector.smart_generate(prompt, context, callback)
end

--- Get accuracy statistics for providers
---@return table Statistics for each provider
function M.get_accuracy_stats()
	local selector = require("codetyper.llm.selector")
	return selector.get_accuracy_stats()
end

--- Report user feedback on response quality (for reinforcement learning)
---@param provider string Which provider generated the response
---@param was_correct boolean Whether the response was good
function M.report_feedback(provider, was_correct)
	local selector = require("codetyper.llm.selector")
	selector.report_feedback(provider, was_correct)
end

--- Build the system prompt for code generation
---@param context table Context information
---@return string System prompt
function M.build_system_prompt(context)
	local prompts = require("codetyper.prompts")

	-- Select appropriate system prompt based on context
	local prompt_type = context.prompt_type or "code_generation"
	local system_prompts = prompts.system

	local system = system_prompts[prompt_type] or system_prompts.code_generation

	-- Substitute variables
	system = system:gsub("{{language}}", context.language or "unknown")
	system = system:gsub("{{filepath}}", context.file_path or "unknown")

	-- For agent mode, include project context
	if prompt_type == "agent" then
		local project_info = "\n\n## PROJECT CONTEXT\n"

		if context.project_root then
			project_info = project_info .. "- Project root: " .. context.project_root .. "\n"
		end
		if context.cwd then
			project_info = project_info .. "- Working directory: " .. context.cwd .. "\n"
		end
		if context.project_type then
			project_info = project_info .. "- Project type: " .. context.project_type .. "\n"
		end
		if context.project_stats then
			project_info = project_info
				.. string.format(
					"- Stats: %d files, %d functions, %d classes\n",
					context.project_stats.files or 0,
					context.project_stats.functions or 0,
					context.project_stats.classes or 0
				)
		end
		if context.file_path then
			project_info = project_info .. "- Current file: " .. context.file_path .. "\n"
		end

		system = system .. project_info
		return system
	end

	-- For "ask" or "explain" mode, don't add code generation instructions
	if prompt_type == "ask" or prompt_type == "explain" then
		-- Just add context about the file if available
		if context.file_path then
			system = system .. "\n\nContext: The user is working with " .. context.file_path
			if context.language then
				system = system .. " (" .. context.language .. ")"
			end
		end
		return system
	end

	-- Add file content with analysis hints (for code generation modes)
	if context.file_content and context.file_content ~= "" then
		system = system .. "\n\n===== EXISTING FILE CONTENT (analyze and match this style) =====\n"
		system = system .. context.file_content
		system = system .. "\n===== END OF EXISTING FILE =====\n"
		system = system .. "\nYour generated code MUST follow the exact patterns shown above."
	else
		system = system
			.. "\n\nThis is a new/empty file. Generate clean, idiomatic "
			.. (context.language or "code")
			.. " following best practices."
	end

	return system
end

--- Build context for LLM request
---@param target_path string Path to target file
---@param prompt_type string Type of prompt
---@return table Context object
function M.build_context(target_path, prompt_type)
	local content = utils.read_file(target_path)
	local ext = vim.fn.fnamemodify(target_path, ":e")

	local context = {
		file_content = content,
		language = lang_map[ext] or ext,
		extension = ext,
		prompt_type = prompt_type,
		file_path = target_path,
	}

	-- For agent mode, include additional project context
	if prompt_type == "agent" then
		local project_root = utils.get_project_root()
		context.project_root = project_root

		-- Try to get project info from indexer
		local ok_indexer, indexer = pcall(require, "codetyper.indexer")
		if ok_indexer then
			local status = indexer.get_status()
			if status.indexed then
				context.project_type = status.project_type
				context.project_stats = status.stats
			end
		end

		-- Include working directory
		context.cwd = vim.fn.getcwd()
	end

	return context
end

--- Parse LLM response and extract code
---@param response string Raw LLM response
---@return string Extracted code
function M.extract_code(response)
	local code = response

	-- Remove markdown code blocks with language tags (```typescript, ```javascript, etc.)
	code = code:gsub("```%w+%s*\n", "")
	code = code:gsub("```%w+%s*$", "")
	code = code:gsub("^```%w*\n?", "")
	code = code:gsub("\n?```%s*$", "")
	code = code:gsub("\n```\n", "\n")
	code = code:gsub("```", "")

	-- Remove common explanation prefixes that LLMs sometimes add
	code = code:gsub("^Here.-:\n", "")
	code = code:gsub("^Here's.-:\n", "")
	code = code:gsub("^This.-:\n", "")
	code = code:gsub("^The following.-:\n", "")
	code = code:gsub("^Below.-:\n", "")

	-- Remove common explanation suffixes
	code = code:gsub("\n\nThis code.-$", "")
	code = code:gsub("\n\nThe above.-$", "")
	code = code:gsub("\n\nNote:.-$", "")
	code = code:gsub("\n\nExplanation:.-$", "")

	-- Trim leading/trailing whitespace but preserve internal formatting
	code = code:match("^%s*(.-)%s*$") or code

	return code
end

return M
