---@mod codetyper.parser Parser for /@ @/ prompt tags

local logger = require("codetyper.support.logger")

local M = {}

M.find_prompts = require("codetyper.parser.find_prompts")
M.find_prompts_in_buffer = require("codetyper.parser.find_prompts_in_buffer")
M.get_prompt_at_cursor = require("codetyper.parser.get_prompt_at_cursor")
M.get_last_prompt = require("codetyper.parser.get_last_prompt")
M.detect_prompt_type = require("codetyper.parser.detect_prompt_type")
M.clean_prompt = require("codetyper.parser.clean_prompt")
M.has_closing_tag = require("codetyper.parser.has_closing_tag")
M.has_unclosed_prompts = require("codetyper.parser.has_unclosed_prompts")
M.extract_file_references = require("codetyper.parser.extract_file_references")
M.strip_file_references = require("codetyper.parser.strip_file_references")
M.is_cursor_in_open_tag = require("codetyper.parser.is_cursor_in_open_tag")
M.get_file_ref_prefix = require("codetyper.parser.get_file_ref_prefix")

logger.info("parser", "Parser module loaded")

return M
