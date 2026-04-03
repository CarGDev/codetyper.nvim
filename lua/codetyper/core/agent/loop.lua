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
  local file_ops, is_agent, tool_calls = parse_response(response, root)

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

return M
