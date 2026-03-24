local M = {}

local utils = require("codetyper.support.utils")

local inject_refactor = require("codetyper.inject.inject_refactor")
local inject_add = require("codetyper.inject.inject_add")
local inject_document = require("codetyper.inject.inject_document")

--- Inject generated code into target file
---@param target_path string Path to target file
---@param code string Generated code
---@param prompt_type string Type of prompt (refactor, add, document, etc.)
function M.inject_code(target_path, code, prompt_type)
  -- Normalize the target path
  target_path = vim.fn.fnamemodify(target_path, ":p")

  -- Try to find buffer by path
  local target_buf = nil
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local buf_name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":p")
    if buf_name == target_path then
      target_buf = buf
      break
    end
  end

  -- If still not found, open the file
  if not target_buf or not vim.api.nvim_buf_is_valid(target_buf) then
    -- Check if file exists
    if utils.file_exists(target_path) then
      vim.cmd("edit " .. vim.fn.fnameescape(target_path))
      target_buf = vim.api.nvim_get_current_buf()
      utils.notify("Opened target file: " .. vim.fn.fnamemodify(target_path, ":t"))
    else
      utils.notify("Target file not found: " .. target_path, vim.log.levels.ERROR)
      return
    end
  end

  if not target_buf then
    utils.notify("Target buffer not found", vim.log.levels.ERROR)
    return
  end

  utils.notify("Injecting code into: " .. vim.fn.fnamemodify(target_path, ":t"))

  -- Different injection strategies based on prompt type
  if prompt_type == "refactor" then
    inject_refactor(target_buf, code)
  elseif prompt_type == "add" then
    inject_add(target_buf, code)
  elseif prompt_type == "document" then
    inject_document(target_buf, code)
  else
    -- For generic, auto-add instead of prompting
    inject_add(target_buf, code)
  end

  -- Mark buffer as modified and save
  vim.bo[target_buf].modified = true

  -- Auto-save the target file
  vim.schedule(function()
    if vim.api.nvim_buf_is_valid(target_buf) then
      local wins = vim.fn.win_findbuf(target_buf)
      if #wins > 0 then
        vim.api.nvim_win_call(wins[1], function()
          vim.cmd("silent! write")
        end)
      end
    end
  end)
end

return M
