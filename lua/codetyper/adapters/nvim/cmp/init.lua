---@mod codetyper.cmp_source Completion source for nvim-cmp
---@brief [[
--- Provides intelligent code completions using the brain, indexer, and LLM.
--- Integrates with nvim-cmp as a custom source.
---@brief ]]

local M = {}

local has_cmp = require("codetyper.adapters.nvim.cmp.has_cmp")
local get_brain_completions = require("codetyper.adapters.nvim.cmp.get_brain_completions")
local get_indexer_completions = require("codetyper.adapters.nvim.cmp.get_indexer_completions")
local get_buffer_completions = require("codetyper.adapters.nvim.cmp.get_buffer_completions")
local get_copilot_suggestion = require("codetyper.adapters.nvim.cmp.get_copilot_suggestion")

local source = require("codetyper.utils.cmp_source")

--- Complete
---@param params table
---@param callback fun(response: table|nil)
function source:complete(params, callback)
  local prefix = params.context.cursor_before_line:match("[%w_]+$") or ""

  if #prefix < 2 then
    callback({ items = {}, isIncomplete = true })
    return
  end

  -- Collect completions from brain, indexer, and buffer
  local items = {}
  local seen = {}

  -- Get brain completions (highest priority)
  local brain_completions_success, brain_items = pcall(get_brain_completions, prefix)
  if brain_completions_success and brain_items then
    for _, item in ipairs(brain_items) do
      if not seen[item.label] then
        seen[item.label] = true
        item.sortText = "1" .. item.label
        table.insert(items, item)
      end
    end
  end

  -- Get indexer completions
  local indexer_completions_success, indexer_items = pcall(get_indexer_completions, prefix)
  if indexer_completions_success and indexer_items then
    for _, item in ipairs(indexer_items) do
      if not seen[item.label] then
        seen[item.label] = true
        item.sortText = "2" .. item.label
        table.insert(items, item)
      end
    end
  end

  -- Get buffer completions as fallback (lower priority)
  local bufnr = params.context.bufnr
  if bufnr then
    local buffer_completions_success, buffer_items = pcall(get_buffer_completions, prefix, bufnr)
    if buffer_completions_success and buffer_items then
      for _, item in ipairs(buffer_items) do
        if not seen[item.label] then
          seen[item.label] = true
          item.sortText = "3" .. item.label
          table.insert(items, item)
        end
      end
    end
  end

  -- If Copilot is installed, prefer its suggestion as a top-priority completion
  local copilot_installed = pcall(require, "copilot")
  if copilot_installed then
    local suggestion = nil
    local copilot_suggestion_success, copilot_suggestion_result = pcall(get_copilot_suggestion, prefix)
    if copilot_suggestion_success then
      suggestion = copilot_suggestion_result
    end
    if suggestion and suggestion ~= "" then
      local first_line = suggestion:match("([^\n]+)") or suggestion
      if not seen[first_line] then
        seen[first_line] = true
        table.insert(items, 1, {
          label = first_line,
          kind = 1,
          detail = "[copilot]",
          documentation = suggestion,
          sortText = "0" .. first_line,
        })
      end
    end
  end

  callback({
    items = items,
    isIncomplete = #items >= 50,
  })
end

--- Setup the completion source
function M.setup()
  if not has_cmp() then
    return false
  end

  local cmp = require("cmp")
  local new_source = source.new()

  -- Register the source
  cmp.register_source("codetyper", new_source)

  return true
end

--- Check if source is registered
---@return boolean
function M.is_registered()
  local cmp_loaded, cmp = pcall(require, "cmp")
  if not cmp_loaded then
    return false
  end

  local config = cmp.get_config()
  if config and config.sources then
    for _, src in ipairs(config.sources) do
      if src.name == "codetyper" then
        return true
      end
    end
  end

  return false
end

--- Get source for manual registration
function M.get_source()
  return source
end

return M
