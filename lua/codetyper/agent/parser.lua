---@mod codetyper.agent.parser Response parser for agent tool calls
---
--- Parses LLM responses to extract tool calls from both Claude and Ollama.

local M = {}

---@class ParsedResponse
---@field text string Text content from the response
---@field tool_calls ToolCall[] List of tool calls
---@field stop_reason string Reason the response stopped

---@class ToolCall
---@field id string Unique identifier for the tool call
---@field name string Name of the tool to call
---@field parameters table Parameters for the tool

--- Parse Claude API response for tool_use blocks
---@param response table Raw Claude API response
---@return ParsedResponse
function M.parse_claude_response(response)
  local result = {
    text = "",
    tool_calls = {},
    stop_reason = response.stop_reason or "end_turn",
  }

  if response.content then
    for _, block in ipairs(response.content) do
      if block.type == "text" then
        result.text = result.text .. (block.text or "")
      elseif block.type == "tool_use" then
        table.insert(result.tool_calls, {
          id = block.id,
          name = block.name,
          parameters = block.input or {},
        })
      end
    end
  end

  return result
end

--- Parse Ollama response for JSON tool blocks
---@param response_text string Raw text response from Ollama
---@return ParsedResponse
function M.parse_ollama_response(response_text)
  local result = {
    text = response_text,
    tool_calls = {},
    stop_reason = "end_turn",
  }

  -- Pattern to find JSON tool blocks in fenced code blocks
  local fenced_pattern = "```json%s*(%b{})%s*```"

  -- Find all fenced JSON blocks
  for json_str in response_text:gmatch(fenced_pattern) do
    local ok, parsed = pcall(vim.json.decode, json_str)
    if ok and parsed.tool and parsed.parameters then
      table.insert(result.tool_calls, {
        id = string.format("%d_%d", os.time(), math.random(10000)),
        name = parsed.tool,
        parameters = parsed.parameters,
      })
      result.stop_reason = "tool_use"
    end
  end

  -- Also try to find inline JSON (not in code blocks)
  -- Pattern for {"tool": "...", "parameters": {...}}
  if #result.tool_calls == 0 then
    local inline_pattern = '(%{"tool"%s*:%s*"[^"]+"%s*,%s*"parameters"%s*:%s*%b{}%})'
    for json_str in response_text:gmatch(inline_pattern) do
      local ok, parsed = pcall(vim.json.decode, json_str)
      if ok and parsed.tool and parsed.parameters then
        table.insert(result.tool_calls, {
          id = string.format("%d_%d", os.time(), math.random(10000)),
          name = parsed.tool,
          parameters = parsed.parameters,
        })
        result.stop_reason = "tool_use"
      end
    end
  end

  -- Clean tool JSON from displayed text
  if #result.tool_calls > 0 then
    result.text = result.text:gsub("```json%s*%b{}%s*```", "[Tool call]")
    result.text = result.text:gsub('%{"tool"%s*:%s*"[^"]+"%s*,%s*"parameters"%s*:%s*%b{}%}', "[Tool call]")
  end

  return result
end

--- Check if response contains tool calls
---@param parsed ParsedResponse Parsed response
---@return boolean
function M.has_tool_calls(parsed)
  return #parsed.tool_calls > 0
end

--- Extract just the text content, removing tool-related markup
---@param text string Response text
---@return string Cleaned text
function M.clean_text(text)
  local cleaned = text
  -- Remove tool JSON blocks
  cleaned = cleaned:gsub("```json%s*%b{}%s*```", "")
  cleaned = cleaned:gsub('%{"tool"%s*:%s*"[^"]+"%s*,%s*"parameters"%s*:%s*%b{}%}', "")
  -- Clean up extra whitespace
  cleaned = cleaned:gsub("\n\n\n+", "\n\n")
  cleaned = cleaned:gsub("^%s+", ""):gsub("%s+$", "")
  return cleaned
end

return M
