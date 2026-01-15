---@mod codetyper.agent Agent orchestration for Codetyper.nvim
---
--- Manages the agentic conversation loop with tool execution.

local M = {}

local tools = require("codetyper.agent.tools")
local executor = require("codetyper.agent.executor")
local parser = require("codetyper.agent.parser")
local diff = require("codetyper.agent.diff")
local utils = require("codetyper.utils")
local logs = require("codetyper.agent.logs")

---@class AgentState
---@field conversation table[] Message history for multi-turn
---@field pending_tool_results table[] Results waiting to be sent back
---@field is_running boolean Whether agent loop is active
---@field max_iterations number Maximum tool call iterations

local state = {
  conversation = {},
  pending_tool_results = {},
  is_running = false,
  max_iterations = 10,
  current_iteration = 0,
}

---@class AgentCallbacks
---@field on_text fun(text: string) Called when text content is received
---@field on_tool_start fun(name: string) Called when a tool starts
---@field on_tool_result fun(name: string, result: string) Called when a tool completes
---@field on_complete fun() Called when agent finishes
---@field on_error fun(err: string) Called on error

--- Reset agent state for new conversation
function M.reset()
  state.conversation = {}
  state.pending_tool_results = {}
  state.is_running = false
  state.current_iteration = 0
end

--- Check if agent is currently running
---@return boolean
function M.is_running()
  return state.is_running
end

--- Stop the agent
function M.stop()
  state.is_running = false
  utils.notify("Agent stopped")
end

--- Main agent entry point
---@param prompt string User's request
---@param context table File context
---@param callbacks AgentCallbacks Callback functions
function M.run(prompt, context, callbacks)
  if state.is_running then
    callbacks.on_error("Agent is already running")
    return
  end

  logs.info("Starting agent run")
  logs.debug("Prompt length: " .. #prompt .. " chars")

  state.is_running = true
  state.current_iteration = 0

  -- Add user message to conversation
  table.insert(state.conversation, {
    role = "user",
    content = prompt,
  })

  -- Start the agent loop
  M.agent_loop(context, callbacks)
end

--- The core agent loop
---@param context table File context
---@param callbacks AgentCallbacks
function M.agent_loop(context, callbacks)
  if not state.is_running then
    callbacks.on_complete()
    return
  end

  state.current_iteration = state.current_iteration + 1
  logs.info(string.format("Agent loop iteration %d/%d", state.current_iteration, state.max_iterations))

  if state.current_iteration > state.max_iterations then
    logs.error("Max iterations reached")
    callbacks.on_error("Max iterations reached (" .. state.max_iterations .. ")")
    state.is_running = false
    return
  end

  local llm = require("codetyper.llm")
  local client = llm.get_client()

  -- Check if client supports tools
  if not client.generate_with_tools then
    logs.error("Provider does not support agent mode")
    callbacks.on_error("Current LLM provider does not support agent mode")
    state.is_running = false
    return
  end

  logs.thinking("Calling LLM with " .. #state.conversation .. " messages...")

  -- Generate with tools enabled
  client.generate_with_tools(state.conversation, context, tools.definitions, function(response, err)
    if err then
      state.is_running = false
      callbacks.on_error(err)
      return
    end

    -- Parse response based on provider
    local codetyper = require("codetyper")
    local config = codetyper.get_config()
    local parsed

    -- Copilot uses Claude-like response format
    if config.llm.provider == "copilot" then
      parsed = parser.parse_claude_response(response)
      table.insert(state.conversation, {
        role = "assistant",
        content = parsed.text or "",
        tool_calls = parsed.tool_calls,
        _raw_content = response.content,
      })
    else
      -- For Ollama, response is the text directly
      if type(response) == "string" then
        parsed = parser.parse_ollama_response(response)
      else
        parsed = parser.parse_ollama_response(response.response or "")
      end
      -- Add assistant response to conversation
      table.insert(state.conversation, {
        role = "assistant",
        content = parsed.text,
        tool_calls = parsed.tool_calls,
      })
    end

    -- Display any text content
    if parsed.text and parsed.text ~= "" then
      local clean_text = parser.clean_text(parsed.text)
      if clean_text ~= "" then
        callbacks.on_text(clean_text)
      end
    end

    -- Check for tool calls
    if #parsed.tool_calls > 0 then
      logs.info(string.format("Processing %d tool call(s)", #parsed.tool_calls))
      -- Process tool calls sequentially
      M.process_tool_calls(parsed.tool_calls, 1, context, callbacks)
    else
      -- No more tool calls, agent is done
      logs.info("No tool calls, finishing agent loop")
      state.is_running = false
      callbacks.on_complete()
    end
  end)
end

--- Process tool calls one at a time
---@param tool_calls table[] List of tool calls
---@param index number Current index
---@param context table File context
---@param callbacks AgentCallbacks
function M.process_tool_calls(tool_calls, index, context, callbacks)
  if not state.is_running then
    callbacks.on_complete()
    return
  end

  if index > #tool_calls then
    -- All tools processed, continue agent loop with results
    M.continue_with_results(context, callbacks)
    return
  end

  local tool_call = tool_calls[index]
  callbacks.on_tool_start(tool_call.name)

  executor.execute(tool_call.name, tool_call.parameters, function(result)
    if result.requires_approval then
      logs.tool(tool_call.name, "approval", "Waiting for user approval")
      -- Show diff preview and wait for user decision
      local show_fn
      if result.diff_data.operation == "bash" then
        show_fn = function(_, cb)
          diff.show_bash_approval(result.diff_data.modified:gsub("^%$ ", ""), cb)
        end
      else
        show_fn = diff.show_diff
      end

      show_fn(result.diff_data, function(approval_result)
        -- Handle both old (boolean) and new (table) approval result formats
        local approved = type(approval_result) == "table" and approval_result.approved or approval_result
        local permission_level = type(approval_result) == "table" and approval_result.permission_level or nil

        if approved then
          local log_msg = "User approved"
          if permission_level == "allow_session" then
            log_msg = "Allowed for session"
          elseif permission_level == "allow_list" then
            log_msg = "Added to allow list"
          elseif permission_level == "auto" then
            log_msg = "Auto-approved"
          end
          logs.tool(tool_call.name, "approved", log_msg)

          -- Apply the change
          executor.apply_change(result.diff_data, function(apply_result)
            -- Store result for sending back to LLM
            table.insert(state.pending_tool_results, {
              tool_use_id = tool_call.id,
              name = tool_call.name,
              result = apply_result.result,
            })
            callbacks.on_tool_result(tool_call.name, apply_result.result)
            -- Process next tool call
            M.process_tool_calls(tool_calls, index + 1, context, callbacks)
          end)
        else
          logs.tool(tool_call.name, "rejected", "User rejected")
          -- User rejected
          table.insert(state.pending_tool_results, {
            tool_use_id = tool_call.id,
            name = tool_call.name,
            result = "User rejected this change",
          })
          callbacks.on_tool_result(tool_call.name, "Rejected by user")
          M.process_tool_calls(tool_calls, index + 1, context, callbacks)
        end
      end)
    else
      -- No approval needed (read_file), store result immediately
      table.insert(state.pending_tool_results, {
        tool_use_id = tool_call.id,
        name = tool_call.name,
        result = result.result,
      })

      -- For read_file, just show a brief confirmation
      local display_result = result.result
      if tool_call.name == "read_file" and result.success then
        display_result = "[Read " .. #result.result .. " bytes]"
      end
      callbacks.on_tool_result(tool_call.name, display_result)

      M.process_tool_calls(tool_calls, index + 1, context, callbacks)
    end
  end)
end

--- Continue the loop after tool execution
---@param context table File context
---@param callbacks AgentCallbacks
function M.continue_with_results(context, callbacks)
  if #state.pending_tool_results == 0 then
    state.is_running = false
    callbacks.on_complete()
    return
  end

  -- Build tool results message
  local codetyper = require("codetyper")
  local config = codetyper.get_config()

  -- Copilot uses Claude-like format for tool results
  if config.llm.provider == "copilot" then
    -- Claude-style tool_result blocks
    local content = {}
    for _, result in ipairs(state.pending_tool_results) do
      table.insert(content, {
        type = "tool_result",
        tool_use_id = result.tool_use_id,
        content = result.result,
      })
    end
    table.insert(state.conversation, {
      role = "user",
      content = content,
    })
  else
    -- Ollama format: plain text describing results
    local result_text = "Tool results:\n"
    for _, result in ipairs(state.pending_tool_results) do
      result_text = result_text .. "\n[" .. result.name .. "]: " .. result.result .. "\n"
    end
    table.insert(state.conversation, {
      role = "user",
      content = result_text,
    })
  end

  state.pending_tool_results = {}

  -- Continue the loop
  M.agent_loop(context, callbacks)
end

--- Get conversation history
---@return table[]
function M.get_conversation()
  return state.conversation
end

--- Set max iterations
---@param max number Maximum iterations
function M.set_max_iterations(max)
  state.max_iterations = max
end

return M
