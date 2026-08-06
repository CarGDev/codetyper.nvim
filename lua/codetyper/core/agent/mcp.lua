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

--- Sanitize a string for OpenAI function name (must match ^[a-zA-Z0-9_-]+$)
---@param s string
---@return string
local function sanitize_name(s)
  return (s or "unknown"):gsub("[^%w_%-]", "_")
end

--- Encode server + tool name into a single function name for the API
---@param server string
---@param tool string
---@return string
function M.encode_tool_name(server, tool)
  return sanitize_name(server) .. "__" .. sanitize_name(tool)
end

--- Decode an encoded function name back into server + tool
---@param encoded string
---@return string|nil server
---@return string|nil tool
function M.decode_tool_name(encoded)
  if not encoded or type(encoded) ~= "string" then
    return nil, nil
  end
  local server, tool = encoded:match("^(.-)__(.+)$")
  return server, tool
end

--- MCP tool names that overlap with FILE:/terminal and cause path conflicts.
--- These are excluded from the native API tools since the agent prompt
--- already handles file operations via FILE: markers and the terminal tool.
local EXCLUDED_MCP_TOOLS = {
  write_file = true,
  read_text_file = true,
  read_file = true,
  create_file = true,
  edit_file = true,
  delete_file = true,
  rename_file = true,
  move_file = true,
  copy_file = true,
  list_directory = true,
  create_directory = true,
  read_directory = true,
  search_files = true,
  find_files = true,
  glob = true,
  execute_command = true,
  run_command = true,
  shell = true,
}

--- Get all available MCP tools in OpenAI function-calling format
--- Excludes filesystem/shell tools that overlap with FILE: and terminal.
---@return table[] tools Array of {type: "function", function: {name, description, parameters}}
function M.get_tools_for_api()
  local hub = get_hub()
  if not hub then
    return {}
  end

  local tools = hub:get_tools()
  if not tools or #tools == 0 then
    return {}
  end

  local result = {}
  local skipped = 0
  for _, tool in ipairs(tools) do
    -- Skip filesystem/shell tools — handled by FILE: markers and terminal
    if EXCLUDED_MCP_TOOLS[tool.name] then
      skipped = skipped + 1
    else
      local name = M.encode_tool_name(tool.server_name or "unknown", tool.name)
      local desc = tool.description or ""
      if #desc > 200 then
        desc = desc:sub(1, 197) .. "..."
      end

      table.insert(result, {
        type = "function",
        ["function"] = {
          name = name,
          description = desc,
          parameters = tool.inputSchema or { type = "object", properties = {} },
        },
      })
    end
  end

  flog.info("mcp", string.format("built %d tools for API (%d filesystem/shell excluded)", #result, skipped))
  return result
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
