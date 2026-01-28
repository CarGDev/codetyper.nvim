---@mod codetyper.features.inline.simple Simple inline prompt handler
---
--- Simplified flow for /@ @/ inline prompts:
--- 1. Detect prompt → 2. Call LLM → 3. Show diff modal → 4. Accept/Reject

local M = {}

local utils = require("codetyper.support.utils")

--- Log helper
local function log(level, message)
  pcall(function()
    local logs = require("codetyper.adapters.nvim.ui.logs")
    logs.add({ type = level, message = message })
  end)
end

---@class SimpleInlineOpts
---@field bufnr number Buffer number
---@field prompt_content string The prompt text (without /@ @/)
---@field prompt_range {start_line: number, end_line: number} Line range of the tags
---@field file_path string Path to the file

--- Process a single inline prompt with simple flow
---@param opts SimpleInlineOpts
function M.process(opts)
  -- Open logs panel
  pcall(function()
    local logs_panel = require("codetyper.adapters.nvim.ui.logs_panel")
    logs_panel.ensure_open()
  end)

  local bufnr = opts.bufnr
  local prompt_range = opts.prompt_range
  local file_path = opts.file_path

  -- Get the original content (the tag region)
  local original_lines = vim.api.nvim_buf_get_lines(
    bufnr,
    prompt_range.start_line - 1,
    prompt_range.end_line,
    false
  )
  local original_content = table.concat(original_lines, "\n")

  -- Clean the prompt (remove /@ @/ markers)
  local clean_prompt = opts.prompt_content
    :gsub("^%s*/?@%s*", "")
    :gsub("%s*@/?%s*$", "")
    :gsub("/%@", "")
    :gsub("%@/", "")

  log("info", "Processing: " .. clean_prompt:sub(1, 50))

  -- Get file context (surrounding lines for better generation)
  local total_lines = vim.api.nvim_buf_line_count(bufnr)
  local context_start = math.max(1, prompt_range.start_line - 20)
  local context_end = math.min(total_lines, prompt_range.end_line + 20)
  local context_lines = vim.api.nvim_buf_get_lines(bufnr, context_start - 1, context_end, false)
  local file_context = table.concat(context_lines, "\n")

  -- Get filetype
  local filetype = vim.bo[bufnr].filetype or vim.fn.fnamemodify(file_path, ":e")

  -- Build simple prompt for LLM
  local llm_prompt = string.format([[You are a code generator. Generate ONLY the code that should replace the inline prompt tag.

FILE: %s
LANGUAGE: %s

CONTEXT (surrounding code):
```
%s
```

USER REQUEST: %s

IMPORTANT:
- Output ONLY the new code to insert, no explanations
- Do NOT include /@ or @/ markers
- Do NOT repeat existing code from context
- Match the existing code style and indentation]],
    file_path, filetype, file_context, clean_prompt)

  -- Show loading indicator
  utils.notify("Generating...", vim.log.levels.INFO)

  -- Build context for LLM
  local context = {
    file_path = file_path,
    language = filetype,
    content = file_context,
  }

  -- Call LLM
  log("request", "Sending to LLM...")
  local llm = require("codetyper.core.llm")
  llm.generate(llm_prompt, context, function(response, err)
    if err then
      log("error", "LLM error: " .. tostring(err))
      utils.notify("LLM error: " .. tostring(err), vim.log.levels.ERROR)
      return
    end

    if not response or response == "" then
      log("error", "Empty response from LLM")
      utils.notify("Empty response from LLM", vim.log.levels.WARN)
      return
    end

    log("response", "Received " .. #response .. " chars")

    -- Clean up the response (remove markdown code blocks if present)
    local generated = response
      :gsub("^```[%w]*\n", "")
      :gsub("\n```$", "")
      :gsub("^```[%w]*", "")
      :gsub("```$", "")
      :gsub("^\n+", "")  -- Remove leading newlines
      :gsub("\n+$", "")  -- Remove trailing newlines

    -- Show diff modal
    vim.schedule(function()
      M.show_diff_modal(bufnr, prompt_range, original_content, generated, file_path)
    end)
  end)
end

--- Show a simple diff modal for approval
---@param bufnr number
---@param prompt_range {start_line: number, end_line: number}
---@param original string
---@param generated string
---@param file_path string
function M.show_diff_modal(bufnr, prompt_range, original, generated, file_path)
  local diff = require("codetyper.core.diff.diff")

  diff.show_diff({
    path = file_path,
    original = original,
    modified = generated,
    operation = "edit",
  }, function(approved)
    if approved then
      -- Replace the tag region with generated code
      local new_lines = vim.split(generated, "\n", { plain = true })
      vim.api.nvim_buf_set_lines(
        bufnr,
        prompt_range.start_line - 1,
        prompt_range.end_line,
        false,
        new_lines
      )

      -- Save the file
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_call(bufnr, function()
          vim.cmd("silent write")
        end)
      end

      log("info", "Applied and saved")
      utils.notify("Applied", vim.log.levels.INFO)
    else
      log("info", "Rejected")
      utils.notify("Rejected", vim.log.levels.INFO)
    end
  end)
end

return M
