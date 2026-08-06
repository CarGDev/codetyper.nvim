--- SSE stream accumulator for Copilot chat/completions API
--- Processes decoded JSON chunks into a structured result.
--- Pure data module — minimal vim dependency, testable outside Neovim.
local M = {}

-- vim.NIL is used by vim.json.decode for JSON null values.
-- Outside Neovim (testing), treat nil as the null sentinel.
local JSON_NULL = vim and vim.NIL or nil

---@class StreamAccumulator
---@field text string Accumulated response text
---@field tool_calls table<number, {id: string, name: string, arguments: string}>
---@field usage table|nil Token usage from final chunk
---@field finish_reason string|nil "stop" | "tool_calls" | "length"

--- Create a new stream accumulator
---@return StreamAccumulator
function M.new()
  return {
    text = "",
    tool_calls = {},
    usage = nil,
    finish_reason = nil,
  }
end

--- Process a single decoded JSON chunk from the SSE stream.
--- Returns deltas for real-time UI updates.
---@param acc StreamAccumulator
---@param chunk table Decoded JSON from one SSE data line
---@return table { text_delta: string|nil, tool_name: string|nil }
function M.process_chunk(acc, chunk)
  local result = { text_delta = nil, tool_name = nil }

  if not chunk or not chunk.choices or not chunk.choices[1] then
    -- Usage-only chunk (sent at end by some models)
    if chunk and chunk.usage then
      acc.usage = chunk.usage
    end
    return result
  end

  local choice = chunk.choices[1]
  local delta = choice.delta

  if delta then
    -- Text content delta
    if delta.content and delta.content ~= JSON_NULL then
      acc.text = acc.text .. delta.content
      result.text_delta = delta.content
    end

    -- Tool calls delta — accumulate per index
    if delta.tool_calls then
      for _, tc in ipairs(delta.tool_calls) do
        local idx = (tc.index or 0) + 1 -- Lua 1-indexed
        if not acc.tool_calls[idx] then
          -- First chunk for this tool call: has id and function.name
          acc.tool_calls[idx] = {
            id = tc.id or "",
            name = (tc["function"] and tc["function"].name) or "",
            arguments = (tc["function"] and tc["function"].arguments) or "",
          }
          result.tool_name = acc.tool_calls[idx].name
        else
          -- Subsequent chunks: concatenate arguments
          if tc["function"] and tc["function"].arguments then
            acc.tool_calls[idx].arguments = acc.tool_calls[idx].arguments
              .. tc["function"].arguments
          end
        end
      end
    end
  end

  -- Finish reason
  if choice.finish_reason and choice.finish_reason ~= JSON_NULL then
    acc.finish_reason = choice.finish_reason
  end

  -- Usage (some models include in final chunk)
  if chunk.usage then
    acc.usage = chunk.usage
  end

  return result
end

--- Finalize the accumulated stream into a structured result.
--- Parses tool call argument JSON strings into tables.
---@param acc StreamAccumulator
---@return table { text: string, tool_calls: table[], usage: table|nil, finish_reason: string|nil }
function M.get_result(acc)
  local tool_calls = {}

  -- Convert indexed tool_calls to array, parse arguments JSON
  for _, tc in pairs(acc.tool_calls) do
    local args = {}
    if tc.arguments and tc.arguments ~= "" then
      local ok, parsed = pcall(vim.json.decode, tc.arguments)
      if ok then
        args = parsed
      end
    end
    table.insert(tool_calls, {
      id = tc.id,
      name = tc.name,
      arguments = args,
      arguments_raw = tc.arguments, -- keep raw JSON for multi-turn history
    })
  end

  return {
    text = acc.text,
    tool_calls = tool_calls,
    usage = acc.usage,
    finish_reason = acc.finish_reason,
  }
end

return M
