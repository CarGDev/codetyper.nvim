local utils = require("codetyper.support.utils")
local AUGROUP = require("codetyper.constants.constants").AUGROUP
local processed_prompts = require("codetyper.constants.constants").processed_prompts
local is_processing = require("codetyper.constants.constants").is_processing
local previous_mode = require("codetyper.constants.constants").previous_mode
local prompt_process_timer = require("codetyper.constants.constants").prompt_process_timer
local PROMPT_PROCESS_DEBOUNCE_MS = require("codetyper.constants.constants").PROMPT_PROCESS_DEBOUNCE_MS
local schedule_tree_update = require("codetyper.adapters.nvim.autocmds.schedule_tree_update")
local check_for_closed_prompt_with_preference = require("codetyper.adapters.nvim.autocmds.check_for_closed_prompt_with_preference")
local check_all_prompts_with_preference = require("codetyper.adapters.nvim.autocmds.check_all_prompts_with_preference")
local set_coder_filetype = require("codetyper.adapters.nvim.autocmds.set_coder_filetype")
local clear_auto_opened = require("codetyper.adapters.nvim.autocmds.clear_auto_opened")
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
        previous_mode = old_mode
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

      if is_processing then
        return
      end

      if previous_mode == "v" or previous_mode == "V" or previous_mode == "\22" then
        return
      end

      if prompt_process_timer then
        prompt_process_timer:stop()
        prompt_process_timer = nil
      end

      prompt_process_timer = vim.defer_fn(function()
        prompt_process_timer = nil
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
      if is_processing then
        return
      end
      local mode = vim.api.nvim_get_mode().mode
      if mode == "n" then
        check_all_prompts_with_preference()
      end
    end,
    desc = "Auto-process closed prompts when idle in normal mode",
  })

  vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
    group = group,
    pattern = "*.codetyper/*",
    callback = function()
      set_coder_filetype()
    end,
    desc = "Set filetype for coder files",
  })

  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    pattern = "*.codetyper/*",
    callback = function(ev)
      local bufnr = ev.buf
      for key, _ in pairs(processed_prompts) do
        if key:match("^" .. bufnr .. ":") then
          processed_prompts[key] = nil
        end
      end
      clear_auto_opened(bufnr)
    end,
    desc = "Cleanup on coder buffer close",
  })

  vim.api.nvim_create_autocmd({ "BufWritePost", "BufNewFile" }, {
    group = group,
    pattern = "*",
    callback = function(ev)
      local filepath = ev.file or vim.fn.expand("%:p")
      if filepath:match("%.codetyper%.") or filepath:match("tree%.log$") then
        return
      end
      if filepath:match("node_modules") or filepath:match("%.git/") or filepath:match("%.codetyper/") then
        return
      end
      schedule_tree_update()

      local indexer_loaded, indexer = pcall(require, "codetyper.indexer")
      if indexer_loaded then
        indexer.schedule_index_file(filepath)
      end

      local brain_loaded, brain = pcall(require, "codetyper.brain")
      if brain_loaded and brain.is_initialized and brain.is_initialized() then
        vim.defer_fn(function()
          update_brain_from_file(filepath)
        end, 500)
      end
    end,
    desc = "Update tree.log, index, and brain on file creation/save",
  })

  vim.api.nvim_create_autocmd("BufDelete", {
    group = group,
    pattern = "*",
    callback = function(ev)
      local filepath = ev.file or ""
      if filepath == "" or filepath:match("%.codetyper%.") or filepath:match("tree%.log$") then
        return
      end
      schedule_tree_update()
    end,
    desc = "Update tree.log on file deletion",
  })

  vim.api.nvim_create_autocmd("DirChanged", {
    group = group,
    pattern = "*",
    callback = function()
      schedule_tree_update()
    end,
    desc = "Update tree.log on directory change",
  })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    pattern = "*",
    callback = function()
      local brain_loaded, brain = pcall(require, "codetyper.brain")
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
