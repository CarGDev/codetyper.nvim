--- MCP bridge — interface to mcphub.nvim for tool listing and execution
local flog = require("codetyper.support.flog") -- TODO: remove after debugging

local M = {}

--- Get the mcphub hub instance (nil if not available)
---@return table|nil hub
local function get_hub()
  local ok, mcphub = pcall(require, "mcphub")
  if not ok then
    return nil
  end
  local hub = mcphub.get_hub_instance()
  if hub and hub:is_ready() then
    return hub
  end
  return nil
end

--- Check if MCP is available
---@return boolean
function M.is_available()
  return get_hub() ~= nil
end

--- Get all available tools formatted for the agent prompt
---@return string tools_description Formatted tool list for system prompt
function M.get_tools_for_prompt()
  local hub = get_hub()
  if not hub then
    return ""
  end

  local tools = hub:get_tools()
  if not tools or #tools == 0 then
    return ""
  end

  local parts = { "\n\n--- Available MCP Tools ---" }
  parts[#parts + 1] = "You can call these tools using TOOL:MCP markers:"
  parts[#parts + 1] = ""

  for _, tool in ipairs(tools) do
    local desc = tool.description or ""
    if #desc > 100 then
      desc = desc:sub(1, 97) .. "..."
    end
    parts[#parts + 1] = string.format("- %s/%s: %s", tool.server_name or "unknown", tool.name, desc)

    -- Show input schema fields if present
    if tool.inputSchema and tool.inputSchema.properties then
      local params = {}
      for param_name, param_info in pairs(tool.inputSchema.properties) do
        local ptype = param_info.type or "any"
        table.insert(params, param_name .. ":" .. ptype)
      end
      if #params > 0 then
        parts[#parts + 1] = "  params: " .. table.concat(params, ", ")
      end
    end
  end

  flog.info("mcp", string.format("loaded %d tools for prompt", #tools)) -- TODO: remove after debugging

  return table.concat(parts, "\n")
end

--- Call an MCP tool
---@param server_name string Server name
---@param tool_name string Tool name
---@param arguments table Tool arguments
---@param callback fun(result: string|nil, error: string|nil)
function M.call_tool(server_name, tool_name, arguments, callback)
  local hub = get_hub()
  if not hub then
    callback(nil, "MCP hub not available")
    return
  end

  flog.info("mcp", string.format("calling tool: %s/%s", server_name, tool_name)) -- TODO: remove after debugging

  hub:call_tool(server_name, tool_name, arguments or {}, {
    callback = function(response, err)
      if err then
        flog.error("mcp", "tool call failed: " .. tostring(err)) -- TODO: remove after debugging
        callback(nil, tostring(err))
        return
      end

      -- Extract text from response
      local result_text = ""
      if response and response.result then
        if type(response.result) == "string" then
          result_text = response.result
        elseif response.result.text then
          result_text = response.result.text
        elseif response.result.content then
          -- MCP content array format
          for _, item in ipairs(response.result.content) do
            if item.text then
              result_text = result_text .. item.text .. "\n"
            end
          end
        else
          result_text = vim.inspect(response.result)
        end
      end

      flog.info("mcp", string.format("tool result: %d chars", #result_text)) -- TODO: remove after debugging
      callback(result_text, nil)
    end,
    parse_response = true,
  })
end

return M
