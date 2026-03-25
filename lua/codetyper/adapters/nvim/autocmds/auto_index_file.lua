local utils = require("codetyper.support.utils")
local autocmds_state = require("codetyper.adapters.nvim.autocmds.state")
local is_supported_extension = require("codetyper.adapters.nvim.autocmds.is_supported_extension")
local should_ignore_for_coder = require("codetyper.adapters.nvim.autocmds.should_ignore_for_coder")

--- Auto-index a file by creating/opening its coder companion
---@param bufnr number Buffer number
local function auto_index_file(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  if autocmds_state.auto_indexed_buffers[bufnr] then
    return
  end

  local filepath = vim.api.nvim_buf_get_name(bufnr)
  if not filepath or filepath == "" then
    return
  end

  if utils.is_coder_file(filepath) then
    return
  end

  local buftype = vim.bo[bufnr].buftype
  if buftype ~= "" then
    return
  end

  local ext = vim.fn.fnamemodify(filepath, ":e")
  if ext == "" or not is_supported_extension(ext) then
    return
  end

  if should_ignore_for_coder(filepath) then
    return
  end

  local codetyper = require("codetyper")
  local config = codetyper.get_config()
  if config and config.auto_index == false then
    return
  end

  autocmds_state.auto_indexed_buffers[bufnr] = true

  local coder_path = utils.get_coder_path(filepath)

  local coder_exists = utils.file_exists(coder_path)

  if not coder_exists then
    local filename = vim.fn.fnamemodify(filepath, ":t")
    local file_ext = vim.fn.fnamemodify(filepath, ":e")

    local comment_prefix = "--"
    local comment_block_start = "--[["
    local comment_block_end = "]]"
    if
      file_ext == "ts"
      or file_ext == "tsx"
      or file_ext == "js"
      or file_ext == "jsx"
      or file_ext == "java"
      or file_ext == "c"
      or file_ext == "cpp"
      or file_ext == "cs"
      or file_ext == "go"
      or file_ext == "rs"
    then
      comment_prefix = "//"
      comment_block_start = "/*"
      comment_block_end = "*/"
    elseif file_ext == "py" or file_ext == "rb" or file_ext == "yaml" or file_ext == "yml" then
      comment_prefix = "#"
      comment_block_start = '"""'
      comment_block_end = '"""'
    end

    local content = ""
    pcall(function()
      local lines = vim.fn.readfile(filepath)
      if lines then
        content = table.concat(lines, "\n")
      end
    end)

    local functions = extract_functions(content, file_ext)
    local classes = extract_classes(content, file_ext)
    local imports = extract_imports(content, file_ext)

    local pseudo_code = {}

    table.insert(
      pseudo_code,
      comment_prefix
        .. " ═══════════════════════════════════════════════════════════"
    )
    table.insert(pseudo_code, comment_prefix .. " CODER COMPANION: " .. filename)
    table.insert(
      pseudo_code,
      comment_prefix
        .. " ═══════════════════════════════════════════════════════════"
    )
    table.insert(pseudo_code, comment_prefix .. " This file describes the business logic and behavior of " .. filename)
    table.insert(pseudo_code, comment_prefix .. " Edit this pseudo-code to guide code generation.")
    table.insert(pseudo_code, comment_prefix .. "")

    table.insert(
      pseudo_code,
      comment_prefix
        .. " ─────────────────────────────────────────────────────────────"
    )
    table.insert(pseudo_code, comment_prefix .. " MODULE PURPOSE:")
    table.insert(
      pseudo_code,
      comment_prefix
        .. " ─────────────────────────────────────────────────────────────"
    )
    table.insert(pseudo_code, comment_prefix .. " TODO: Describe what this module/file is responsible for")
    table.insert(pseudo_code, comment_prefix .. ' Example: "Handles user authentication and session management"')
    table.insert(pseudo_code, comment_prefix .. "")

    if #imports > 0 then
      table.insert(
        pseudo_code,
        comment_prefix
          .. " ─────────────────────────────────────────────────────────────"
      )
      table.insert(pseudo_code, comment_prefix .. " DEPENDENCIES:")
      table.insert(
        pseudo_code,
        comment_prefix
          .. " ─────────────────────────────────────────────────────────────"
      )
      for _, imp in ipairs(imports) do
        table.insert(pseudo_code, comment_prefix .. " • " .. imp)
      end
      table.insert(pseudo_code, comment_prefix .. "")
    end

    if #classes > 0 then
      table.insert(
        pseudo_code,
        comment_prefix
          .. " ─────────────────────────────────────────────────────────────"
      )
      table.insert(pseudo_code, comment_prefix .. " CLASSES:")
      table.insert(
        pseudo_code,
        comment_prefix
          .. " ─────────────────────────────────────────────────────────────"
      )
      for _, class in ipairs(classes) do
        table.insert(pseudo_code, comment_prefix .. "")
        table.insert(pseudo_code, comment_prefix .. " class " .. class.name .. ":")
        table.insert(pseudo_code, comment_prefix .. "   PURPOSE: TODO - describe what this class represents")
        table.insert(pseudo_code, comment_prefix .. "   RESPONSIBILITIES:")
        table.insert(pseudo_code, comment_prefix .. "     - TODO: list main responsibilities")
      end
      table.insert(pseudo_code, comment_prefix .. "")
    end

    if #functions > 0 then
      table.insert(
        pseudo_code,
        comment_prefix
          .. " ─────────────────────────────────────────────────────────────"
      )
      table.insert(pseudo_code, comment_prefix .. " FUNCTIONS:")
      table.insert(
        pseudo_code,
        comment_prefix
          .. " ─────────────────────────────────────────────────────────────"
      )
      for _, func in ipairs(functions) do
        table.insert(pseudo_code, comment_prefix .. "")
        table.insert(pseudo_code, comment_prefix .. " " .. func.name .. "():")
        table.insert(pseudo_code, comment_prefix .. "   PURPOSE: TODO - what does this function do?")
        table.insert(pseudo_code, comment_prefix .. "   INPUTS: TODO - describe parameters")
        table.insert(pseudo_code, comment_prefix .. "   OUTPUTS: TODO - describe return value")
        table.insert(pseudo_code, comment_prefix .. "   BEHAVIOR:")
        table.insert(pseudo_code, comment_prefix .. "     - TODO: describe step-by-step logic")
      end
      table.insert(pseudo_code, comment_prefix .. "")
    end

    if #functions == 0 and #classes == 0 then
      table.insert(
        pseudo_code,
        comment_prefix
          .. " ─────────────────────────────────────────────────────────────"
      )
      table.insert(pseudo_code, comment_prefix .. " PLANNED STRUCTURE:")
      table.insert(
        pseudo_code,
        comment_prefix
          .. " ─────────────────────────────────────────────────────────────"
      )
      table.insert(pseudo_code, comment_prefix .. " TODO: Describe what you want to build in this file")
      table.insert(pseudo_code, comment_prefix .. "")
      table.insert(pseudo_code, comment_prefix .. " Example pseudo-code:")

      table.insert(pseudo_code, comment_prefix .. " Create a module that:")
      table.insert(pseudo_code, comment_prefix .. " 1. Exports a main function")
      table.insert(pseudo_code, comment_prefix .. " 2. Handles errors gracefully")
      table.insert(pseudo_code, comment_prefix .. " 3. Returns structured data")
      table.insert(pseudo_code, comment_prefix .. "")
    end

    table.insert(
      pseudo_code,
      comment_prefix
        .. " ─────────────────────────────────────────────────────────────"
    )
    table.insert(pseudo_code, comment_prefix .. " BUSINESS RULES:")
    table.insert(
      pseudo_code,
      comment_prefix
        .. " ─────────────────────────────────────────────────────────────"
    )
    table.insert(pseudo_code, comment_prefix .. " TODO: Document any business rules, constraints, or requirements")
    table.insert(pseudo_code, comment_prefix .. " Example:")
    table.insert(pseudo_code, comment_prefix .. "   - Users must be authenticated before accessing this feature")
    table.insert(pseudo_code, comment_prefix .. "   - Data must be validated before saving")
    table.insert(pseudo_code, comment_prefix .. "   - Errors should be logged but not exposed to users")
    table.insert(pseudo_code, comment_prefix .. "")

    table.insert(
      pseudo_code,
      comment_prefix
        .. " ═══════════════════════════════════════════════════════════"
    )
    table.insert(
      pseudo_code,
      comment_prefix
        .. " ═══════════════════════════════════════════════════════════"
    )
    table.insert(pseudo_code, "")

    utils.write_file(coder_path, table.concat(pseudo_code, "\n"))
  end

  local coder_filename = vim.fn.fnamemodify(coder_path, ":t")
  if coder_exists then
    utils.notify("Coder companion available: " .. coder_filename, vim.log.levels.DEBUG)
  else
    utils.notify("Created coder companion: " .. coder_filename, vim.log.levels.INFO)
  end
end

return auto_index_file
