---@mod codetyper.parser Parser for /@ @/ prompt tags

local M = {}

local utils = require("codetyper.support.utils")
local logger = require("codetyper.support.logger")

--- Get config with safe fallback
---@return table config
local function get_config_safe()
	logger.func_entry("parser", "get_config_safe", {})
	
	local ok, codetyper = pcall(require, "codetyper")
	if ok and codetyper.get_config then
		local config = codetyper.get_config()
		if config and config.patterns then
			logger.debug("parser", "get_config_safe: loaded config from codetyper")
			logger.func_exit("parser", "get_config_safe", "success")
			return config
		end
	end
	
	logger.debug("parser", "get_config_safe: using fallback defaults")
	logger.func_exit("parser", "get_config_safe", "fallback")
	
	-- Fallback defaults
	return {
		patterns = {
			open_tag = "/@",
			close_tag = "@/",
		},
	}
end

--- Find all prompts in buffer content
---@param content string Buffer content
---@param open_tag string Opening tag
---@param close_tag string Closing tag
---@return CoderPrompt[] List of found prompts
function M.find_prompts(content, open_tag, close_tag)
	logger.func_entry("parser", "find_prompts", {
		content_length = #content,
		open_tag = open_tag,
		close_tag = close_tag
	})
	
	local prompts = {}
	local escaped_open = utils.escape_pattern(open_tag)
	local escaped_close = utils.escape_pattern(close_tag)

	local lines = vim.split(content, "\n", { plain = true })
	local in_prompt = false
	local current_prompt = nil
	local prompt_content = {}

	logger.debug("parser", "find_prompts: parsing " .. #lines .. " lines")

	for line_num, line in ipairs(lines) do
		if not in_prompt then
			-- Look for opening tag
			local start_col = line:find(escaped_open)
			if start_col then
				logger.debug("parser", "find_prompts: found opening tag at line " .. line_num .. ", col " .. start_col)
				in_prompt = true
				current_prompt = {
					start_line = line_num,
					start_col = start_col,
					content = "",
				}
				-- Get content after opening tag on same line
				local after_tag = line:sub(start_col + #open_tag)
				local end_col = after_tag:find(escaped_close)
				if end_col then
					-- Single line prompt
					current_prompt.content = after_tag:sub(1, end_col - 1)
					current_prompt.end_line = line_num
					current_prompt.end_col = start_col + #open_tag + end_col + #close_tag - 2
					table.insert(prompts, current_prompt)
					logger.debug("parser", "find_prompts: single-line prompt completed at line " .. line_num)
					in_prompt = false
					current_prompt = nil
				else
					table.insert(prompt_content, after_tag)
				end
			end
		else
			-- Look for closing tag
			local end_col = line:find(escaped_close)
			if end_col then
				-- Found closing tag
				local before_tag = line:sub(1, end_col - 1)
				table.insert(prompt_content, before_tag)
				current_prompt.content = table.concat(prompt_content, "\n")
				current_prompt.end_line = line_num
				current_prompt.end_col = end_col + #close_tag - 1
				table.insert(prompts, current_prompt)
				logger.debug("parser", "find_prompts: multi-line prompt completed at line " .. line_num .. ", total lines: " .. #prompt_content)
				in_prompt = false
				current_prompt = nil
				prompt_content = {}
			else
				table.insert(prompt_content, line)
			end
		end
	end

	logger.debug("parser", "find_prompts: found " .. #prompts .. " prompts total")
	logger.func_exit("parser", "find_prompts", "found " .. #prompts .. " prompts")
	
	return prompts
end

--- Find prompts in a buffer
---@param bufnr number Buffer number
---@return CoderPrompt[] List of found prompts
function M.find_prompts_in_buffer(bufnr)
	logger.func_entry("parser", "find_prompts_in_buffer", { bufnr = bufnr })
	
	local config = get_config_safe()

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local content = table.concat(lines, "\n")

	logger.debug("parser", "find_prompts_in_buffer: bufnr=" .. bufnr .. ", lines=" .. #lines .. ", content_length=" .. #content)

	local result = M.find_prompts(content, config.patterns.open_tag, config.patterns.close_tag)
	
	logger.func_exit("parser", "find_prompts_in_buffer", "found " .. #result .. " prompts")
	return result
end

--- Get prompt at cursor position
---@param bufnr? number Buffer number (default: current)
---@return CoderPrompt|nil Prompt at cursor or nil
function M.get_prompt_at_cursor(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local line = cursor[1]
	local col = cursor[2] + 1 -- Convert to 1-indexed

	logger.func_entry("parser", "get_prompt_at_cursor", {
		bufnr = bufnr,
		line = line,
		col = col
	})

	local prompts = M.find_prompts_in_buffer(bufnr)

	logger.debug("parser", "get_prompt_at_cursor: checking " .. #prompts .. " prompts")

	for i, prompt in ipairs(prompts) do
		logger.debug("parser", "get_prompt_at_cursor: checking prompt " .. i .. " (lines " .. prompt.start_line .. "-" .. prompt.end_line .. ")")
		if line >= prompt.start_line and line <= prompt.end_line then
			logger.debug("parser", "get_prompt_at_cursor: cursor line " .. line .. " is within prompt line range")
			if line == prompt.start_line and col < prompt.start_col then
				logger.debug("parser", "get_prompt_at_cursor: cursor col " .. col .. " is before prompt start_col " .. prompt.start_col)
				goto continue
			end
			if line == prompt.end_line and col > prompt.end_col then
				logger.debug("parser", "get_prompt_at_cursor: cursor col " .. col .. " is after prompt end_col " .. prompt.end_col)
				goto continue
			end
			logger.debug("parser", "get_prompt_at_cursor: found prompt at cursor")
			logger.func_exit("parser", "get_prompt_at_cursor", "prompt found")
			return prompt
		end
		::continue::
	end

	logger.debug("parser", "get_prompt_at_cursor: no prompt found at cursor")
	logger.func_exit("parser", "get_prompt_at_cursor", nil)
	return nil
end

--- Get the last closed prompt in buffer
---@param bufnr? number Buffer number (default: current)
---@return CoderPrompt|nil Last prompt or nil
function M.get_last_prompt(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	
	logger.func_entry("parser", "get_last_prompt", { bufnr = bufnr })
	
	local prompts = M.find_prompts_in_buffer(bufnr)

	if #prompts > 0 then
		local last = prompts[#prompts]
		logger.debug("parser", "get_last_prompt: returning prompt at line " .. last.start_line)
		logger.func_exit("parser", "get_last_prompt", "prompt at line " .. last.start_line)
		return last
	end

	logger.debug("parser", "get_last_prompt: no prompts found")
	logger.func_exit("parser", "get_last_prompt", nil)
	return nil
end

--- Extract the prompt type from content
---@param content string Prompt content
---@return "refactor" | "add" | "document" | "explain" | "generic" Prompt type
function M.detect_prompt_type(content)
	logger.func_entry("parser", "detect_prompt_type", { content_preview = content:sub(1, 50) })
	
	local lower = content:lower()

	if lower:match("refactor") then
		logger.debug("parser", "detect_prompt_type: detected 'refactor'")
		logger.func_exit("parser", "detect_prompt_type", "refactor")
		return "refactor"
	elseif lower:match("add") or lower:match("create") or lower:match("implement") then
		logger.debug("parser", "detect_prompt_type: detected 'add'")
		logger.func_exit("parser", "detect_prompt_type", "add")
		return "add"
	elseif lower:match("document") or lower:match("comment") or lower:match("jsdoc") then
		logger.debug("parser", "detect_prompt_type: detected 'document'")
		logger.func_exit("parser", "detect_prompt_type", "document")
		return "document"
	elseif lower:match("explain") or lower:match("what") or lower:match("how") then
		logger.debug("parser", "detect_prompt_type: detected 'explain'")
		logger.func_exit("parser", "detect_prompt_type", "explain")
		return "explain"
	end

	logger.debug("parser", "detect_prompt_type: detected 'generic'")
	logger.func_exit("parser", "detect_prompt_type", "generic")
	return "generic"
end

--- Clean prompt content (trim whitespace, normalize newlines)
---@param content string Raw prompt content
---@return string Cleaned content
function M.clean_prompt(content)
	logger.func_entry("parser", "clean_prompt", { content_length = #content })
	
	-- Trim leading/trailing whitespace
	content = content:match("^%s*(.-)%s*$")
	-- Normalize multiple newlines
	content = content:gsub("\n\n\n+", "\n\n")
	
	logger.debug("parser", "clean_prompt: cleaned from " .. #content .. " chars")
	logger.func_exit("parser", "clean_prompt", "length=" .. #content)
	
	return content
end

--- Check if line contains a closing tag
---@param line string Line to check
---@param close_tag string Closing tag
---@return boolean
function M.has_closing_tag(line, close_tag)
	logger.func_entry("parser", "has_closing_tag", { line_preview = line:sub(1, 30), close_tag = close_tag })
	
	local result = line:find(utils.escape_pattern(close_tag)) ~= nil
	
	logger.debug("parser", "has_closing_tag: result=" .. tostring(result))
	logger.func_exit("parser", "has_closing_tag", result)
	
	return result
end

--- Check if buffer has any unclosed prompts
---@param bufnr? number Buffer number (default: current)
---@return boolean
function M.has_unclosed_prompts(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	
	logger.func_entry("parser", "has_unclosed_prompts", { bufnr = bufnr })
	
	local config = get_config_safe()

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local content = table.concat(lines, "\n")

	local escaped_open = utils.escape_pattern(config.patterns.open_tag)
	local escaped_close = utils.escape_pattern(config.patterns.close_tag)

	local _, open_count = content:gsub(escaped_open, "")
	local _, close_count = content:gsub(escaped_close, "")

	local has_unclosed = open_count > close_count
	
	logger.debug("parser", "has_unclosed_prompts: open=" .. open_count .. ", close=" .. close_count .. ", unclosed=" .. tostring(has_unclosed))
	logger.func_exit("parser", "has_unclosed_prompts", has_unclosed)
	
	return has_unclosed
end

--- Extract file references from prompt content
--- Matches @filename patterns but NOT @/ (closing tag)
---@param content string Prompt content
---@return string[] List of file references
function M.extract_file_references(content)
	logger.func_entry("parser", "extract_file_references", { content_length = #content })
	
	local files = {}
	-- Pattern: @ followed by word char, dot, underscore, or dash as FIRST char
	-- Then optionally more path characters including /
	-- This ensures @/ is NOT matched (/ cannot be first char)
	for file in content:gmatch("@([%w%._%-][%w%._%-/]*)") do
		if file ~= "" then
			table.insert(files, file)
			logger.debug("parser", "extract_file_references: found file reference: " .. file)
		end
	end
	
	logger.debug("parser", "extract_file_references: found " .. #files .. " file references")
	logger.func_exit("parser", "extract_file_references", files)
	
	return files
end

--- Remove file references from prompt content (for clean prompt text)
---@param content string Prompt content
---@return string Cleaned content without file references
function M.strip_file_references(content)
	logger.func_entry("parser", "strip_file_references", { content_length = #content })
	
	-- Remove @filename patterns but preserve @/ closing tag
	-- Pattern requires first char after @ to be word char, dot, underscore, or dash (NOT /)
	local result = content:gsub("@([%w%._%-][%w%._%-/]*)", "")
	
	logger.debug("parser", "strip_file_references: stripped " .. (#content - #result) .. " chars")
	logger.func_exit("parser", "strip_file_references", "length=" .. #result)
	
	return result
end

--- Check if cursor is inside an unclosed prompt tag
---@param bufnr? number Buffer number (default: current)
---@return boolean is_inside Whether cursor is inside an open tag
---@return number|nil start_line Line where the open tag starts
function M.is_cursor_in_open_tag(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	
	logger.func_entry("parser", "is_cursor_in_open_tag", { bufnr = bufnr })
	
	local config = get_config_safe()

	local cursor = vim.api.nvim_win_get_cursor(0)
	local cursor_line = cursor[1]

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, cursor_line, false)
	local escaped_open = utils.escape_pattern(config.patterns.open_tag)
	local escaped_close = utils.escape_pattern(config.patterns.close_tag)

	local open_count = 0
	local close_count = 0
	local last_open_line = nil

	for line_num, line in ipairs(lines) do
		-- Count opens on this line
		for _ in line:gmatch(escaped_open) do
			open_count = open_count + 1
			last_open_line = line_num
			logger.debug("parser", "is_cursor_in_open_tag: found open tag at line " .. line_num)
		end
		-- Count closes on this line
		for _ in line:gmatch(escaped_close) do
			close_count = close_count + 1
			logger.debug("parser", "is_cursor_in_open_tag: found close tag at line " .. line_num)
		end
	end

	local is_inside = open_count > close_count
	
	logger.debug("parser", "is_cursor_in_open_tag: open=" .. open_count .. ", close=" .. close_count .. ", is_inside=" .. tostring(is_inside) .. ", last_open_line=" .. tostring(last_open_line))
	logger.func_exit("parser", "is_cursor_in_open_tag", { is_inside = is_inside, last_open_line = last_open_line })
	
	return is_inside, is_inside and last_open_line or nil
end

--- Get the word being typed after @ symbol
---@param bufnr? number Buffer number
---@return string|nil prefix The text after @ being typed, or nil if not typing a file ref
function M.get_file_ref_prefix(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	
	logger.func_entry("parser", "get_file_ref_prefix", { bufnr = bufnr })

	local cursor = vim.api.nvim_win_get_cursor(0)
	local line = vim.api.nvim_buf_get_lines(bufnr, cursor[1] - 1, cursor[1], false)[1]
	if not line then
		logger.debug("parser", "get_file_ref_prefix: no line at cursor")
		logger.func_exit("parser", "get_file_ref_prefix", nil)
		return nil
	end

	local col = cursor[2]
	local before_cursor = line:sub(1, col)

	-- Check if we're typing after @ but not @/
	-- Match @ followed by optional path characters at end of string
	local prefix = before_cursor:match("@([%w%._%-/]*)$")

	-- Make sure it's not the closing tag pattern
	if prefix and before_cursor:sub(-2) == "@/" then
		logger.debug("parser", "get_file_ref_prefix: closing tag detected, returning nil")
		logger.func_exit("parser", "get_file_ref_prefix", nil)
		return nil
	end

	logger.debug("parser", "get_file_ref_prefix: prefix=" .. tostring(prefix))
	logger.func_exit("parser", "get_file_ref_prefix", prefix)
	
	return prefix
end

logger.info("parser", "Parser module loaded")

return M
