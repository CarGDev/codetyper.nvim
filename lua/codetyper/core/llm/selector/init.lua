--- Selector — wires explicit routing, fallback selection, and accuracy.
local M = {}

local select_provider = require("codetyper.core.llm.selector.select")
local ponder_mod = require("codetyper.core.llm.selector.ponder")
local accuracy = require("codetyper.core.llm.selector.accuracy")
local flog = require("codetyper.support.flog") -- TODO: remove after debugging
local SAFE_TOOL_STATUSES = {
  available = true,
  unavailable = true,
  stale = true,
  error = true,
  cancelled = true,
}

M.select_provider = select_provider
M.should_ponder = ponder_mod.should_ponder
M.ponder = ponder_mod.ponder
M.get_accuracy_stats = accuracy.get_stats
M.reset_accuracy_stats = accuracy.reset
M.report_feedback = accuracy.record

local function get_client(provider)
  local llm = require("codetyper.core.llm")
  return llm.get_client(provider)
end

local function resolve_capabilities(client, context, provider)
  if type(context) == "table" and type(context.tool_capabilities) == "table" then
    return context.tool_capabilities
  end
  if provider == "copilot" and client and type(client.get_tool_capabilities) == "function" then
    local ok, capabilities = pcall(client.get_tool_capabilities, context or {})
    if ok and type(capabilities) == "table" then
      return capabilities
    end
  end
  return {}
end

local function route_mode(client, selection, context, capabilities)
  if selection.provider == "copilot"
    and context.is_project_task == true
    and capabilities.native_tools == true
    and (capabilities.provider == nil or capabilities.provider == "copilot")
    and type(client.generate_structured) == "function"
  then
    return "native"
  end
  if capabilities.marker_tools == true then
    return "marker"
  end
  return "none"
end

local function copy_capabilities(capabilities, provider, mode)
  local result = {
    provider = provider,
    native_tools = mode == "native",
    marker_tools = mode == "marker",
  }
  if type(capabilities) ~= "table" then
    return result
  end

  if type(capabilities.limits) == "table" then
    result.limits = {}
    for _, key in ipairs({ "max_result_chars", "max_query_chars", "max_nodes", "max_items" }) do
      if type(capabilities.limits[key]) == "number" then
        result.limits[key] = math.floor(capabilities.limits[key])
      end
    end
  end

  local source = capabilities.available_tools
  if type(source) ~= "table" then
    source = capabilities.tools
  end
  if type(source) == "table" then
    result.available_tools = {}
    for _, tool in ipairs(source) do
      if type(tool) == "table" and type(tool.name) == "string" then
        local name = tool.name:match("^[%w_%-]+$")
        if name then
          local entry = { name = name:sub(1, 64) }
          if type(tool.marker) == "string" and tool.marker:match("^TOOL:[A-Z_]+$") then
            entry.marker = tool.marker
          end
          if type(tool.status) == "string" and SAFE_TOOL_STATUSES[tool.status] then
            entry.status = tool.status
          end
          if type(tool.available) == "boolean" then
            entry.available = tool.available
          end
          if type(tool.stale) == "boolean" then
            entry.stale = tool.stale
          end
          result.available_tools[#result.available_tools + 1] = entry
        end
      end
    end
  end
  return result
end

local function request_context(context, selection, mode, capabilities)
  local result = vim.deepcopy(context or {})
  result.provider = selection.provider
  result.tool_capabilities = copy_capabilities(capabilities, selection.provider, mode)
  if mode ~= "native" then
    -- The marker/no-tool route must not forward native schemas to a provider
    -- that cannot dispatch them.
    result.tools = nil
  end
  return result
end

local function dispatch_generation(prompt, context, selection, client, callback)
  local capabilities = resolve_capabilities(client, context, selection.provider)
  local mode = route_mode(client, selection, context, capabilities)
  local routed_context = request_context(context, selection, mode, capabilities)
  local metadata = {
    provider = selection.provider,
    explicit = selection.explicit,
    tool_mode = mode,
    confidence = selection.confidence,
  }
  local finished = false
  local function finish(response, err, extra)
    if finished then
      return
    end
    finished = true
    if extra then
      for key, value in pairs(extra) do
        metadata[key] = value
      end
    end
    callback(response, err, metadata)
  end

  if mode == "native" then
    local ok, handle = pcall(client.generate_structured, prompt, routed_context, {
      on_text_delta = function() end,
      on_complete = function(result)
        result = type(result) == "table" and result or {}
        finish(
          type(result.text) == "string" and result.text or "",
          nil,
          {
            structured = true,
            tool_calls = type(result.tool_calls) == "table" and result.tool_calls or {},
            usage = result.usage,
            finish_reason = result.finish_reason,
            system_prompt = routed_context.system_prompt,
          }
        )
      end,
      on_error = function(err)
        finish(nil, err, { structured = true })
      end,
    })
    if not ok then
      finish(nil, handle, { structured = true })
    end
    return handle
  end

  if type(client.generate) ~= "function" then
    finish(nil, "selected provider client cannot generate", nil)
    return { cancel = function() end }
  end

  local ok, handle = pcall(client.generate, prompt, routed_context, function(response, err, usage)
    finish(response, err, { usage = usage })
  end)
  if not ok then
    finish(nil, handle, nil)
  end
  return handle or { cancel = function() end }
end

--- Smart generate with automatic provider selection and pondering
---@param prompt string
---@param context table
---@param callback fun(response: string|nil, error: string|nil, metadata: table|nil)
function M.smart_generate(prompt, context, callback)
  context = context or {}
  local selection = select_provider(prompt, context)

  flog.info(
    "selector",
    string.format( -- TODO: remove after debugging
      "provider=%s confidence=%.0f%% memories=%d reason=%s",
      selection.provider,
      selection.confidence * 100,
      selection.memory_count,
      selection.reason
    )
  )

  pcall(function()
    local logs_add = require("codetyper.adapters.nvim.ui.logs.add")
    logs_add({
      type = "info",
      message = string.format("LLM: %s (%.0f%%, %s)", selection.provider, selection.confidence * 100, selection.reason),
    })
  end)

  if selection.error then
    callback(nil, selection.error, {
      provider = selection.provider,
      explicit = selection.explicit,
      tool_mode = selection.tool_mode or "none",
    })
    return
  end

  local ok_client, client = pcall(get_client, selection.provider)
  if not ok_client or not client then
    callback(nil, ok_client and "selected provider client is unavailable" or client, {
      provider = selection.provider,
      explicit = selection.explicit,
      tool_mode = selection.tool_mode or "none",
    })
    return
  end

  local function handle_generated(response, err, metadata)
    if err then
      if selection.provider == "ollama" and not selection.explicit then
        flog.info("selector", "Ollama failed (" .. tostring(err) .. "), falling back to Copilot")
        -- Record failure so accuracy stats reflect it
        accuracy.record("ollama", false)
        local fallback_selection = {
          provider = "copilot",
          explicit = false,
          confidence = selection.confidence,
        }
        local fallback_ok, copilot = pcall(get_client, "copilot")
        if not fallback_ok or not copilot then
          callback(nil, fallback_ok and "Copilot client is unavailable" or copilot, {
            provider = "copilot",
            fallback = true,
            original_provider = "ollama",
            original_error = err,
            tool_mode = "none",
          })
          return
        end
        return dispatch_generation(prompt, context, fallback_selection, copilot, function(fb_response, fb_err, fb_metadata)
          fb_metadata.fallback = true
          fb_metadata.original_provider = "ollama"
          fb_metadata.original_error = err
          callback(fb_response, fb_err, fb_metadata)
        end)
      end
      callback(nil, err, metadata)
      return
    end

    if selection.provider == "ollama" and not selection.explicit and ponder_mod.should_ponder(selection.confidence) then
      ponder_mod.ponder(prompt, context, response, function(result)
        if result.ollama_correct then
          metadata.pondered = true
          metadata.agreement = result.agreement_score
          callback(response, nil, metadata)
        else
          callback(result.verifier_response, nil, {
            provider = "copilot",
            pondered = true,
            agreement = result.agreement_score,
            original_provider = "ollama",
            corrected = true,
            explicit = false,
            tool_mode = "marker",
          })
        end
      end)
    else
      metadata.pondered = false
      callback(response, nil, metadata)
    end
  end

  return dispatch_generation(prompt, context, selection, client, handle_generated)
end

return M
