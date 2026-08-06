--- Agent loop — multi-turn: LLM → tool calls → results → LLM → final code
local flog = require("codetyper.support.flog") -- TODO: remove after debugging
local parse_response = require("codetyper.core.agent.parse_response")
local executor = require("codetyper.core.agent.executor")

local M = {}

local MAX_ITERATIONS = 5

--- Format tool results into a follow-up prompt
---@param tool_results table[] Results from execute_tools
---@return string follow_up prompt text
local function format_tool_results(tool_results)
  local parts = { "Here are the tool results:\n" }

  for _, result in ipairs(tool_results) do
    if result.type == "terminal" then
      table.insert(parts, string.format(
        "TOOL_RESULT: TERMINAL `%s`\n```\n%s\n```\n",
        result.command or "",
        result.output or ""
      ))
    elseif result.type == "mcp" then
      table.insert(parts, string.format(
        "TOOL_RESULT: MCP %s/%s\n```\n%s\n```\n",
        result.server or "", result.tool or "",
        result.output or ""
      ))
    end
  end

  table.insert(parts, "Now continue with your task using these results.")
  table.insert(parts, "If you need more information, make more TOOL: calls.")
  table.insert(parts, "If you have enough information, output the final code (FILE: operations or plain code).")

  return table.concat(parts, "\n")
end

--- Run one iteration of the agent loop
---@param event table Original event
---@param response string LLM response
---@param iteration number Current iteration (1-based)
---@param conversation table[] Message history for follow-ups
---@param on_complete fun(file_ops: table[], final_response: string) Called when loop finishes
local function run_iteration(event, response, iteration, conversation, on_complete)
  local utils = require("codetyper.support.utils")
  local root = utils.get_project_root()

  flog.info("agent.loop", string.format("iteration %d/%d, response_len=%d", iteration, MAX_ITERATIONS, #response)) -- TODO: remove after debugging

  -- Parse the response
  local file_ops, is_agent, tool_calls = parse_response(response, root, event.target_path)

  -- Execute file operations immediately (they don't need follow-up)
  if #file_ops > 0 then
    flog.info("agent.loop", string.format("executing %d file ops", #file_ops)) -- TODO: remove after debugging
    executor.execute(file_ops)
  end

  -- If no tool calls, we're done
  if #tool_calls == 0 then
    flog.info("agent.loop", "no tool calls, loop complete") -- TODO: remove after debugging
    on_complete(file_ops, response)
    return
  end

  -- Hit max iterations — execute what we have and stop
  if iteration >= MAX_ITERATIONS then
    flog.warn("agent.loop", "max iterations reached, stopping") -- TODO: remove after debugging
    vim.schedule(function()
      vim.notify("Agent: max iterations reached (" .. MAX_ITERATIONS .. ")", vim.log.levels.WARN)
    end)
    on_complete(file_ops, response)
    return
  end

  -- Execute tool calls and collect results
  flog.info("agent.loop", string.format("executing %d tool calls", #tool_calls)) -- TODO: remove after debugging

  vim.schedule(function()
    vim.notify(
      string.format("Agent: running %d tool%s (iteration %d)...",
        #tool_calls, #tool_calls > 1 and "s" or "", iteration),
      vim.log.levels.INFO
    )
  end)

  executor.execute_tools(tool_calls, function(tool_results)
    -- Build follow-up prompt with tool results
    local follow_up = format_tool_results(tool_results)

    flog.info("agent.loop", string.format("tool results collected, follow_up_len=%d", #follow_up)) -- TODO: remove after debugging

    -- Add to conversation history
    table.insert(conversation, { role = "assistant", content = response })
    table.insert(conversation, { role = "user", content = follow_up })

    -- Send follow-up to LLM
    vim.schedule(function()
      vim.notify("Agent: processing tool results...", vim.log.levels.INFO)

      local llm = require("codetyper.core.llm")
      local client = llm.get_client()

      -- Build the full prompt with conversation history
      local full_prompt = ""
      for _, msg in ipairs(conversation) do
        if msg.role == "user" then
          full_prompt = full_prompt .. msg.content .. "\n\n"
        elseif msg.role == "assistant" then
          full_prompt = full_prompt .. "[Previous response]\n" .. msg.content:sub(1, 2000) .. "\n\n"
        end
      end

      local context = {
        system_prompt = conversation.system_prompt or "",
        file_path = event.target_path,
      }

      flog.info("agent.loop", string.format("sending follow-up, prompt_len=%d", #full_prompt)) -- TODO: remove after debugging

      client.generate(full_prompt, context, function(new_response, err)
        if err or not new_response then
          flog.error("agent.loop", "follow-up failed: " .. tostring(err)) -- TODO: remove after debugging
          on_complete(file_ops, response)
          return
        end

        flog.info("agent.loop", string.format("follow-up response_len=%d", #new_response)) -- TODO: remove after debugging

        -- Recurse
        run_iteration(event, new_response, iteration + 1, conversation, on_complete)
      end)
    end)
  end)
end

--- Start the agent loop
---@param event table Original PromptEvent
---@param initial_response string First LLM response
---@param system_prompt string System prompt used
---@param on_complete fun(file_ops: table[], final_response: string) Called when done
function M.start(event, initial_response, system_prompt, on_complete)
  flog.info("agent.loop", ">>> starting agent loop") -- TODO: remove after debugging

  -- Initialize conversation with the original prompt
  -- Keep system_prompt separate from the messages array to avoid
  -- mixed hash/array table issues (ipairs skips hash keys)
  local conversation = {
    { role = "user", content = event.prompt_content or "" },
  }
  conversation.system_prompt = system_prompt

  run_iteration(event, initial_response, 1, conversation, on_complete)
end

--- Rate limit delay between tool-calling iterations (ms)
--- Copilot flags aggressive automated usage — keep a buffer.
local TOOL_LOOP_DELAY_MS = 2500

--- Max content size per tool result to avoid context window exhaustion
local MAX_TOOL_RESULT_CHARS = 4000

--- Normalize a tool call to flat format {id, name, arguments}
--- Handles both stream format ({id, name, arguments}) and
--- OpenAI message format ({id, type, function: {name, arguments}})
---@param tc table Raw tool call
---@return table Normalized {id, name, arguments}
local function normalize_tool_call(tc)
  if tc["function"] then
    -- OpenAI message format
    local args = tc["function"].arguments or "{}"
    if type(args) == "string" then
      local ok, parsed = pcall(vim.json.decode, args)
      args = ok and parsed or {}
    end
    return {
      id = tc.id or tc.call_id or "",
      name = tc["function"].name or "",
      arguments = args,
      arguments_raw = type(tc["function"].arguments) == "string"
        and tc["function"].arguments or vim.json.encode(args),
    }
  end
  -- Already flat format
  return tc
end

--- Execute native tool calls and return results
---@param tool_calls table[] Array of tool calls (stream or message format)
---@param callback fun(results: table[]) Array of {tool_call_id, role, content}
local function execute_native_tools(tool_calls, callback)
  local mcp = require("codetyper.core.agent.mcp")
  local results = {}
  local pending = #tool_calls

  if pending == 0 then
    callback(results)
    return
  end

  for _, raw_tc in ipairs(tool_calls) do
    local tc = normalize_tool_call(raw_tc)
    local tool_call_id = tc.id

    flog.info("agent.loop.native", string.format(
      "executing tool: name=%s id=%s args=%s",
      tc.name, tc.id, vim.inspect(tc.arguments):sub(1, 200)
    ))

    if tc.name == "terminal" then
      -- Terminal tool: run shell command in visible panel
      local cmd = tc.arguments and tc.arguments.command or ""
      flog.info("agent.loop.native", "terminal: " .. cmd:sub(1, 100))

      local terminal = require("codetyper.core.agent.terminal")
      terminal.run_visible(cmd, function(output, err)
        local content = err or output or ""
        if content == "" then
          content = "Command completed with no output."
        end
        if #content > MAX_TOOL_RESULT_CHARS then
          content = content:sub(1, MAX_TOOL_RESULT_CHARS) .. "\n...(truncated)"
        end
        table.insert(results, {
          role = "tool",
          tool_call_id = tool_call_id,
          content = content,
        })
        pending = pending - 1
        if pending == 0 then callback(results) end
      end)
    else
      -- MCP tool: decode server__tool name
      local server, tool = mcp.decode_tool_name(tc.name)
      if server and tool then
        flog.info("agent.loop.native", string.format("mcp: %s/%s", server, tool))
        mcp.call_tool(server, tool, tc.arguments or {}, function(output, err)
          local content = err or output or ""
          if content == "" then
            content = "Tool returned empty result. The operation may have failed silently."
          end
          if #content > MAX_TOOL_RESULT_CHARS then
            content = content:sub(1, MAX_TOOL_RESULT_CHARS) .. "\n...(truncated)"
          end
          table.insert(results, {
            role = "tool",
            tool_call_id = tool_call_id,
            content = content,
          })
          pending = pending - 1
          if pending == 0 then callback(results) end
        end)
      else
        -- Unknown tool — return error
        flog.warn("agent.loop.native", "unknown tool: " .. tc.name)
        table.insert(results, {
          role = "tool",
          tool_call_id = tool_call_id,
          content = "Error: unknown tool '" .. tc.name .. "'",
        })
        pending = pending - 1
        if pending == 0 then callback(results) end
      end
    end
  end
end

--- Run one iteration of the native agent loop
---@param event table Original event
---@param messages table[] OpenAI message history
---@param system_prompt string
---@param iteration number
---@param on_complete fun(file_ops: table[], final_response: string)
local function run_native_iteration(event, messages, system_prompt, iteration, on_complete)
  flog.info("agent.loop.native", string.format("iteration %d/%d", iteration, MAX_ITERATIONS))

  -- Get the last assistant result
  local last_msg = messages[#messages]
  local raw_content = last_msg and last_msg.content
  -- vim.NIL is truthy in Lua — treat it as empty
  local text = (raw_content and raw_content ~= vim.NIL) and raw_content or ""
  local tool_calls_raw = last_msg and last_msg.tool_calls or {}

  -- Parse and execute FILE: ops from text
  local file_ops = {}
  pcall(function()
    local utils = require("codetyper.support.utils")
    local root = utils.get_project_root()
    local ops = parse_response(text or "", root, event.target_path)
    if ops and #ops > 0 then
      flog.info("agent.loop.native", string.format("executing %d file ops", #ops))
      executor.execute(ops)
      file_ops = ops
    end
  end)

  -- No tool calls → done
  if #tool_calls_raw == 0 then
    flog.info("agent.loop.native", "no tool calls, loop complete")
    on_complete(file_ops, text or "")
    return
  end

  -- Max iterations → stop
  if iteration >= MAX_ITERATIONS then
    flog.warn("agent.loop.native", "max iterations reached")
    vim.schedule(function()
      vim.notify("Agent: max iterations reached (" .. MAX_ITERATIONS .. ")", vim.log.levels.WARN)
    end)
    on_complete(file_ops, text or "")
    return
  end

  -- Execute native tool calls
  flog.info("agent.loop.native", string.format("executing %d native tool calls", #tool_calls_raw))

  -- Build descriptive notification of what tools are being called
  local tool_names = {}
  for _, raw_tc in ipairs(tool_calls_raw) do
    local ntc = normalize_tool_call(raw_tc)
    local display = ntc.name
    if display == "terminal" and ntc.arguments and ntc.arguments.command then
      display = "$ " .. ntc.arguments.command:sub(1, 40)
    elseif display:match("__") then
      local s, t = require("codetyper.core.agent.mcp").decode_tool_name(display)
      if s and t then display = s .. "/" .. t end
    end
    table.insert(tool_names, display)
  end

  vim.schedule(function()
    vim.notify(
      string.format("Agent [%d/%d]: %s",
        iteration, MAX_ITERATIONS, table.concat(tool_names, ", ")),
      vim.log.levels.INFO
    )
  end)

  execute_native_tools(tool_calls_raw, function(tool_results)
    flog.info("agent.loop.native", string.format("got %d tool results", #tool_results))

    -- Append tool results to message history
    for _, tr in ipairs(tool_results) do
      table.insert(messages, tr)
    end

    -- Show tool results summary
    for _, tr in ipairs(tool_results) do
      local preview = (tr.content or ""):sub(1, 80):gsub("\n", " ")
      flog.info("agent.loop.native", "tool result: " .. preview)
    end

    -- Rate limit delay before sending follow-up
    vim.defer_fn(function()
      vim.schedule(function()
        vim.notify(
          string.format("Agent [%d/%d]: sending results back to model...", iteration, MAX_ITERATIONS),
          vim.log.levels.INFO
        )
      end)

      local llm = require("codetyper.core.llm")
      local client = llm.get_client()

      if not client or not client.generate_structured then
        flog.warn("agent.loop.native", "no structured client for follow-up")
        on_complete(file_ops, text or "")
        return
      end

      local context = {
        system_prompt = system_prompt,
        messages = messages,
        is_follow_up = true,
        file_path = event.target_path,
      }

      client.generate_structured("", context, {
        on_text_delta = function() end,
        on_complete = function(result)
          flog.info("agent.loop.native", string.format(
            "follow-up: text_len=%d tool_calls=%d",
            #(result.text or ""), #(result.tool_calls or {})
          ))

          -- Build assistant message for history
          local assistant_msg = {
            role = "assistant",
            content = (#(result.text or "") > 0) and result.text or vim.NIL,
          }
          -- Include tool_calls in message history if present
          if result.tool_calls and #result.tool_calls > 0 then
            assistant_msg.tool_calls = {}
            for _, tc in ipairs(result.tool_calls) do
              table.insert(assistant_msg.tool_calls, {
                id = tc.id,
                type = "function",
                ["function"] = {
                  name = tc.name,
                  arguments = tc.arguments_raw or vim.json.encode(tc.arguments or {}),
                },
              })
            end
          end
          table.insert(messages, assistant_msg)

          -- Recurse with updated tool_calls
          -- Temporarily attach tool_calls to last message for iteration check
          local last = messages[#messages]
          last.tool_calls = assistant_msg.tool_calls or {}

          run_native_iteration(event, messages, system_prompt, iteration + 1, on_complete)
        end,
        on_error = function(err)
          flog.error("agent.loop.native", "follow-up failed: " .. tostring(err))
          on_complete(file_ops, text or "")
        end,
      })
    end, TOOL_LOOP_DELAY_MS)
  end)
end

--- Start a native agent loop using structured API tool_calls
---@param event table Original PromptEvent
---@param result table WorkerResult with tool_calls and system_prompt
---@param on_complete fun(file_ops: table[], final_response: string)
function M.start_native(event, result, on_complete)
  flog.info("agent.loop.native", string.format(
    ">>> starting native agent loop: %d tool calls",
    result.tool_calls and #result.tool_calls or 0
  ))

  -- Use the system prompt from the worker (the full agent tier prompt with
  -- FILE: instructions, tool format, reasoning rules). Falls back to a
  -- minimal intent modifier if not available.
  local system_prompt = result.system_prompt or ""
  if system_prompt == "" then
    pcall(function()
      local intent_mod = require("codetyper.core.intent")
      if event.intent then
        system_prompt = intent_mod.get_prompt_modifier(event.intent)
      end
    end)
  end

  -- Build initial message history
  local messages = {
    { role = "system", content = system_prompt },
    { role = "user", content = event.prompt_content or "" },
  }

  -- First assistant response with tool_calls
  local assistant_msg = {
    role = "assistant",
    content = (#(result.response or "") > 0) and result.response or vim.NIL,
  }
  if result.tool_calls and #result.tool_calls > 0 then
    assistant_msg.tool_calls = {}
    for _, tc in ipairs(result.tool_calls) do
      table.insert(assistant_msg.tool_calls, {
        id = tc.id,
        type = "function",
        ["function"] = {
          name = tc.name,
          arguments = tc.arguments_raw or vim.json.encode(tc.arguments or {}),
        },
      })
    end
  end
  table.insert(messages, assistant_msg)

  -- Start the loop from the first tool call execution
  run_native_iteration(event, messages, system_prompt, 1, on_complete)
end

return M
