local utils = require("codetyper.support.utils")
local constants = require("codetyper.constants.constants")
local AUGROUP = constants.AUGROUP
local PROMPT_PROCESS_DEBOUNCE_MS = constants.PROMPT_PROCESS_DEBOUNCE_MS
local check_for_closed_prompt_with_preference = require("codetyper.adapters.nvim.autocmds.check_for_closed_prompt_with_preference")
local check_all_prompts_with_preference = require("codetyper.adapters.nvim.autocmds.check_all_prompts_with_preference")
local auto_index_file = require("codetyper.adapters.nvim.autocmds.auto_index_file")
local update_brain_from_file = require("codetyper.adapters.nvim.autocmds.update_brain_from_file")

--- Setup autocommands
local function setup()
  local group = vim.api.nvim_create_augroup(AUGROUP, { clear = true })

  vim.api.nvim_create_autocmd("InsertLeave", {
    group = group,
    pattern = "*",
    callback = function()
      local buftype = vim.bo.buftype
      if buftype ~= "" then
        return
      end
      local filepath = vim.fn.expand("%:p")
      if utils.is_coder_file(filepath) and vim.bo.modified then
        vim.cmd("silent! write")
      end
      check_for_closed_prompt_with_preference()
    end,
    desc = "Check for closed prompt tags on InsertLeave",
  })

  vim.api.nvim_create_autocmd("ModeChanged", {
    group = group,
    pattern = "*",
    callback = function(ev)
      local old_mode = ev.match:match("^(.-):")
      if old_mode then
        constants.previous_mode = old_mode
      end
    end,
    desc = "Track previous mode for visual mode detection",
  })

  vim.api.nvim_create_autocmd("ModeChanged", {
    group = group,
    pattern = "*:n",
    callback = function()
      local buftype = vim.bo.buftype
      if buftype ~= "" then
        return
      end

      if constants.is_processing then
        return
      end

      if constants.previous_mode == "v" or constants.previous_mode == "V" or constants.previous_mode == "\22" then
        return
      end

      if constants.prompt_process_timer then
        constants.prompt_process_timer:stop()
        constants.prompt_process_timer = nil
      end

      constants.prompt_process_timer = vim.defer_fn(function()
        constants.prompt_process_timer = nil
        local mode = vim.api.nvim_get_mode().mode
        if mode ~= "n" then
          return
        end
        check_all_prompts_with_preference()
      end, PROMPT_PROCESS_DEBOUNCE_MS)
    end,
    desc = "Auto-process closed prompts when entering normal mode",
  })

  vim.api.nvim_create_autocmd("CursorHold", {
    group = group,
    pattern = "*",
    callback = function()
      local buftype = vim.bo.buftype
      if buftype ~= "" then
        return
      end
      if constants.is_processing then
        return
      end
      local mode = vim.api.nvim_get_mode().mode
      if mode == "n" then
        check_all_prompts_with_preference()
      end
    end,
    desc = "Auto-process closed prompts when idle in normal mode",
  })

  -- Clean up processed_prompts and inline placeholders when buffer is deleted
  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = group,
    pattern = "*",
    callback = function(ev)
      local bufnr = ev.buf
      -- Purge processed_prompts entries for this buffer
      for key, _ in pairs(constants.processed_prompts) do
        if key:match("^" .. bufnr .. ":") then
          constants.processed_prompts[key] = nil
        end
      end
      -- Clean up any orphaned inline placeholders for this buffer
      pcall(function()
        local tp = require("codetyper.core.thinking_placeholder")
        if tp.cleanup_buffer then
          tp.cleanup_buffer(bufnr)
        end
      end)
    end,
    desc = "Clean up processed prompts and placeholders on buffer close",
  })

  vim.api.nvim_create_autocmd({ "BufWritePost", "BufNewFile" }, {
    group = group,
    pattern = "*",
    callback = function(ev)
      local filepath = ev.file or vim.fn.expand("%:p")
      if filepath:match("node_modules") or filepath:match("%.git/") then
        return
      end

      local indexer_loaded, indexer = pcall(require, "codetyper.features.indexer")
      if indexer_loaded then
        indexer.schedule_index_file(filepath)
      end

      local brain_loaded, brain = pcall(require, "codetyper.core.memory")
      if brain_loaded and brain.is_initialized and brain.is_initialized() then
        vim.defer_fn(function()
          update_brain_from_file(filepath)
        end, 500)
      end
    end,
    desc = "Update index and brain on file creation/save",
  })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    pattern = "*",
    callback = function()
      local brain_loaded, brain = pcall(require, "codetyper.core.memory")
      if brain_loaded and brain.is_initialized and brain.is_initialized() then
        brain.shutdown()
      end
    end,
    desc = "Shutdown brain and flush pending changes",
  })

  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    pattern = "*",
    callback = function(ev)
      vim.defer_fn(function()
        auto_index_file(ev.buf)
      end, 100)
    end,
    desc = "Auto-index source files with coder companion",
  })

  local thinking_setup = require("codetyper.adapters.nvim.ui.thinking.setup")
  thinking_setup()
end

return setup
