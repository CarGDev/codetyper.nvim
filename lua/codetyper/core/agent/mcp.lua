--- MCP bridge - interface to mcphub.nvim for tool listing and execution
local flog = require("codetyper.support.flog") -- TODO: remove after debugging

local M = {}

local function inspect_hub()
  local ok, mcphub = pcall(require, "mcphub")
  if not ok or type(mcphub) ~= "table" or type(mcphub.get_hub_instance) ~= "function" then
    return { status = "absent" }
  end
  local instance_ok, hub = pcall(mcphub.get_hub_instance)
  if not instance_ok or type(hub) ~= "table" then
    return { status = "absent" }
  end
  if type(hub.is_ready) ~= "function" then
    return { status = "error", error = "mcphub readiness is unavailable" }
  end
  local ready_ok, ready = pcall(hub.is_ready, hub)
  if not ready_ok then
    return { status = "error", error = "mcphub readiness check failed" }
  end
  if ready ~= true then
    return { status = "not_ready", error = "mcphub is not ready" }
  end
  return { status = "ready", hub = hub }
end

--- Get the mcphub hub instance (nil if not available)
---@return table|nil hub
local function get_hub()
  local state = inspect_hub()
  if state.status == "ready" then
    return state.hub
  end
  return nil
end

local function safe_error(value, fallback)
  local message = type(value) == "string" and value or ""
  local lower = message:lower()
  if
    lower:find("api[_%-]?key", 1, false)
    or lower:find("authorization", 1, true)
    or lower:find("bearer", 1, true)
    or lower:find("password", 1, true)
    or lower:find("secret", 1, true)
    or lower:find("credential", 1, true)
    or lower:find("access[_%-]?token", 1, false)
  then
    return fallback
  end
  message = message:gsub("[%c]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  return message ~= "" and message:sub(1, 512) or fallback
end

--- Return the safe readiness state of the optional mcphub integration.
function M.get_hub_state()
  local state = inspect_hub()
  return { status = state.status, error = state.error }
end

--- Return mcphub tools through the same seam used by existing MCP calls.
function M.get_hub_tools()
  local state = inspect_hub()
  if state.status ~= "ready" then
    return nil, state.error or "mcphub is unavailable"
  end
  if type(state.hub.get_tools) ~= "function" then
    return nil, "mcphub tool listing is unavailable"
  end
  local ok, tools = pcall(state.hub.get_tools, state.hub)
  if not ok or type(tools) ~= "table" then
    return nil, "mcphub tool listing failed"
  end
  return tools
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

--- Check whether a named MCP tool is present in the ready, filtered hub list.
--- Filesystem and shell tools remain unavailable even if the hub advertises
--- them, matching the native API exclusion boundary.
---@param server_name string
---@param tool_name string
---@return boolean
function M.is_tool_allowed(server_name, tool_name)
  if type(server_name) ~= "string" or type(tool_name) ~= "string" or server_name == "" or tool_name == "" then
    return false
  end
  if EXCLUDED_MCP_TOOLS[tool_name] then
    return false
  end
  local state = inspect_hub()
  if state.status ~= "ready" or type(state.hub.get_tools) ~= "function" then
    return false
  end
  local ok, tools = pcall(state.hub.get_tools, state.hub)
  if not ok or type(tools) ~= "table" then
    return false
  end
  for _, tool in ipairs(tools) do
    if tool.server_name == server_name and tool.name == tool_name then
      return true
    end
  end
  return false
end

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
    -- Skip filesystem/shell tools - handled by FILE: markers and terminal
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
    return { cancel = function() end }
  end

  flog.info("mcp", string.format("calling tool: %s/%s", server_name, tool_name)) -- TODO: remove after debugging

  local ok, handle = pcall(hub.call_tool, hub, server_name, tool_name, arguments or {}, {
    callback = function(response, err)
      if err then
        flog.error("mcp", "tool call failed") -- TODO: remove after debugging
        callback(nil, safe_error(err, "MCP tool call failed"))
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
  if not ok then
    callback(nil, "MCP tool call failed")
    return { cancel = function() end }
  end
  return handle or { cancel = function() end }
end

return M
