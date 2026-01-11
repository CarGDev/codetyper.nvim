---@mod codetyper.commands Command definitions for Codetyper.nvim

local M = {}

local utils = require("codetyper.utils")
local window = require("codetyper.window")

--- Open coder view for current file or select one
---@param opts? table Command options
local function cmd_open(opts)
  opts = opts or {}

  local current_file = vim.fn.expand("%:p")

  -- If no file is open, prompt user to select one
  if current_file == "" or vim.bo.buftype ~= "" then
    -- Use telescope or vim.ui.select to pick a file
    if pcall(require, "telescope") then
      require("telescope.builtin").find_files({
        prompt_title = "Select file for Coder",
        attach_mappings = function(prompt_bufnr, map)
          local actions = require("telescope.actions")
          local action_state = require("telescope.actions.state")

          actions.select_default:replace(function()
            actions.close(prompt_bufnr)
            local selection = action_state.get_selected_entry()
            if selection then
              local target_path = selection.path or selection[1]
              local coder_path = utils.get_coder_path(target_path)
              window.open_split(target_path, coder_path)
            end
          end)
          return true
        end,
      })
    else
      -- Fallback to input prompt
      vim.ui.input({ prompt = "Enter file path: " }, function(input)
        if input and input ~= "" then
          local target_path = vim.fn.fnamemodify(input, ":p")
          local coder_path = utils.get_coder_path(target_path)
          window.open_split(target_path, coder_path)
        end
      end)
    end
    return
  end

  local target_path, coder_path

  -- Check if current file is a coder file
  if utils.is_coder_file(current_file) then
    coder_path = current_file
    target_path = utils.get_target_path(current_file)
  else
    target_path = current_file
    coder_path = utils.get_coder_path(current_file)
  end

  window.open_split(target_path, coder_path)
end

--- Close coder view
local function cmd_close()
  window.close_split()
end

--- Toggle coder view
local function cmd_toggle()
  local current_file = vim.fn.expand("%:p")

  if current_file == "" then
    utils.notify("No file in current buffer", vim.log.levels.WARN)
    return
  end

  local target_path, coder_path

  if utils.is_coder_file(current_file) then
    coder_path = current_file
    target_path = utils.get_target_path(current_file)
  else
    target_path = current_file
    coder_path = utils.get_coder_path(current_file)
  end

  window.toggle_split(target_path, coder_path)
end

--- Build enhanced user prompt with context
---@param clean_prompt string The cleaned user prompt
---@param context table Context information
---@return string Enhanced prompt
local function build_user_prompt(clean_prompt, context)
  local enhanced = "TASK: " .. clean_prompt .. "\n\n"
  
  enhanced = enhanced .. "REQUIREMENTS:\n"
  enhanced = enhanced .. "- Generate ONLY " .. (context.language or "code") .. " code\n"
  enhanced = enhanced .. "- NO markdown code blocks (no ```)\n"
  enhanced = enhanced .. "- NO explanations or comments about what you did\n"
  enhanced = enhanced .. "- Match the coding style of the existing file exactly\n"
  enhanced = enhanced .. "- Output must be ready to insert directly into the file\n"
  
  return enhanced
end

--- Process prompt at cursor and generate code
local function cmd_process()
  local parser = require("codetyper.parser")
  local llm = require("codetyper.llm")

  local bufnr = vim.api.nvim_get_current_buf()
  local current_file = vim.fn.expand("%:p")

  if not utils.is_coder_file(current_file) then
    utils.notify("Not a coder file. Use *.coder.* files", vim.log.levels.WARN)
    return
  end

  local prompt = parser.get_last_prompt(bufnr)
  if not prompt then
    utils.notify("No prompt found. Use /@ your prompt @/", vim.log.levels.WARN)
    return
  end

  local target_path = utils.get_target_path(current_file)
  local prompt_type = parser.detect_prompt_type(prompt.content)
  local context = llm.build_context(target_path, prompt_type)
  local clean_prompt = parser.clean_prompt(prompt.content)
  
  -- Build enhanced prompt with explicit instructions
  local enhanced_prompt = build_user_prompt(clean_prompt, context)

  utils.notify("Processing: " .. clean_prompt:sub(1, 50) .. "...", vim.log.levels.INFO)

  llm.generate(enhanced_prompt, context, function(response, err)
    if err then
      utils.notify("Generation failed: " .. err, vim.log.levels.ERROR)
      return
    end

    if response then
      -- Inject code into target file
      local inject = require("codetyper.inject")
      inject.inject_code(target_path, response, prompt_type)
      utils.notify("Code generated and injected!", vim.log.levels.INFO)
    end
  end)
end

--- Show plugin status
local function cmd_status()
  local codetyper = require("codetyper")
  local config = codetyper.get_config()
  local tree = require("codetyper.tree")

  local stats = tree.get_stats()

  local status = {
    "Codetyper.nvim Status",
    "====================",
    "",
    "Provider: " .. config.llm.provider,
  }

  if config.llm.provider == "claude" then
    local has_key = (config.llm.claude.api_key or vim.env.ANTHROPIC_API_KEY) ~= nil
    table.insert(status, "Claude API Key: " .. (has_key and "configured" or "NOT SET"))
    table.insert(status, "Claude Model: " .. config.llm.claude.model)
  else
    table.insert(status, "Ollama Host: " .. config.llm.ollama.host)
    table.insert(status, "Ollama Model: " .. config.llm.ollama.model)
  end

  table.insert(status, "")
  table.insert(status, "Window Position: " .. config.window.position)
  table.insert(status, "Window Width: " .. tostring(config.window.width * 100) .. "%")
  table.insert(status, "")
  table.insert(status, "View Open: " .. (window.is_open() and "yes" or "no"))
  table.insert(status, "")
  table.insert(status, "Project Stats:")
  table.insert(status, "  Files: " .. stats.files)
  table.insert(status, "  Directories: " .. stats.directories)
  table.insert(status, "  Tree Log: " .. (tree.get_tree_log_path() or "N/A"))

  utils.notify(table.concat(status, "\n"))
end

--- Refresh tree.log manually
local function cmd_tree()
  local tree = require("codetyper.tree")
  if tree.update_tree_log() then
    utils.notify("Tree log updated: " .. tree.get_tree_log_path())
  else
    utils.notify("Failed to update tree log", vim.log.levels.ERROR)
  end
end

--- Open tree.log file
local function cmd_tree_view()
  local tree = require("codetyper.tree")
  local tree_log_path = tree.get_tree_log_path()

  if not tree_log_path then
    utils.notify("Could not find tree.log", vim.log.levels.WARN)
    return
  end

  -- Ensure tree is up to date
  tree.update_tree_log()

  -- Open in a new split
  vim.cmd("vsplit " .. vim.fn.fnameescape(tree_log_path))
  vim.bo.readonly = true
  vim.bo.modifiable = false
end

--- Reset processed prompts to allow re-processing
local function cmd_reset()
  local autocmds = require("codetyper.autocmds")
  autocmds.reset_processed()
end

--- Force update gitignore
local function cmd_gitignore()
  local gitignore = require("codetyper.gitignore")
  gitignore.force_update()
end

--- Open ask panel
local function cmd_ask()
  local ask = require("codetyper.ask")
  ask.open()
end

--- Close ask panel
local function cmd_ask_close()
  local ask = require("codetyper.ask")
  ask.close()
end

--- Toggle ask panel
local function cmd_ask_toggle()
  local ask = require("codetyper.ask")
  ask.toggle()
end

--- Clear ask history
local function cmd_ask_clear()
  local ask = require("codetyper.ask")
  ask.clear_history()
end

--- Switch focus between coder and target windows
local function cmd_focus()
  if not window.is_open() then
    utils.notify("Coder view not open", vim.log.levels.WARN)
    return
  end

  local current_win = vim.api.nvim_get_current_win()
  if current_win == window.get_coder_win() then
    window.focus_target()
  else
    window.focus_coder()
  end
end

--- Transform inline /@ @/ tags in current file
--- Works on ANY file, not just .coder.* files
local function cmd_transform()
  local parser = require("codetyper.parser")
  local llm = require("codetyper.llm")

  local bufnr = vim.api.nvim_get_current_buf()
  local filepath = vim.fn.expand("%:p")

  if filepath == "" then
    utils.notify("No file in current buffer", vim.log.levels.WARN)
    return
  end

  -- Find all prompts in the current buffer
  local prompts = parser.find_prompts_in_buffer(bufnr)

  if #prompts == 0 then
    utils.notify("No /@ @/ tags found in current file", vim.log.levels.INFO)
    return
  end

  utils.notify("Found " .. #prompts .. " prompt(s) to transform...", vim.log.levels.INFO)

  -- Build context for this file
  local ext = vim.fn.fnamemodify(filepath, ":e")
  local context = llm.build_context(filepath, "code_generation")

  -- Process prompts in reverse order (bottom to top) to maintain line numbers
  local sorted_prompts = {}
  for i = #prompts, 1, -1 do
    table.insert(sorted_prompts, prompts[i])
  end

  -- Track how many are being processed
  local pending = #sorted_prompts
  local completed = 0
  local errors = 0

  -- Process each prompt
  for _, prompt in ipairs(sorted_prompts) do
    local clean_prompt = parser.clean_prompt(prompt.content)
    local prompt_type = parser.detect_prompt_type(prompt.content)

    -- Build enhanced user prompt
    local enhanced_prompt = "TASK: " .. clean_prompt .. "\n\n"
    enhanced_prompt = enhanced_prompt .. "REQUIREMENTS:\n"
    enhanced_prompt = enhanced_prompt .. "- Generate ONLY " .. (context.language or "code") .. " code\n"
    enhanced_prompt = enhanced_prompt .. "- NO markdown code blocks (no ```)\n"
    enhanced_prompt = enhanced_prompt .. "- NO explanations or comments about what you did\n"
    enhanced_prompt = enhanced_prompt .. "- Match the coding style of the existing file exactly\n"
    enhanced_prompt = enhanced_prompt .. "- Output must be ready to insert directly into the file\n"

    utils.notify("Processing: " .. clean_prompt:sub(1, 40) .. "...", vim.log.levels.INFO)

    -- Generate code for this prompt
    llm.generate(enhanced_prompt, context, function(response, err)
      if err then
        utils.notify("Failed: " .. err, vim.log.levels.ERROR)
        errors = errors + 1
      elseif response then
        -- Replace the prompt tag with generated code
        vim.schedule(function()
          -- Get current buffer lines
          local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

          -- Calculate the exact range to replace
          local start_line = prompt.start_line
          local end_line = prompt.end_line

          -- Find the full lines containing the tags
          local start_line_content = lines[start_line] or ""
          local end_line_content = lines[end_line] or ""

          -- Check if there's content before the opening tag on the same line
          local codetyper = require("codetyper")
          local config = codetyper.get_config()
          local before_tag = ""
          local after_tag = ""

          local open_pos = start_line_content:find(utils.escape_pattern(config.patterns.open_tag))
          if open_pos and open_pos > 1 then
            before_tag = start_line_content:sub(1, open_pos - 1)
          end

          local close_pos = end_line_content:find(utils.escape_pattern(config.patterns.close_tag))
          if close_pos then
            local after_close = close_pos + #config.patterns.close_tag
            if after_close <= #end_line_content then
              after_tag = end_line_content:sub(after_close)
            end
          end

          -- Build the replacement lines
          local replacement_lines = vim.split(response, "\n", { plain = true })

          -- Add before/after content if any
          if before_tag ~= "" and #replacement_lines > 0 then
            replacement_lines[1] = before_tag .. replacement_lines[1]
          end
          if after_tag ~= "" and #replacement_lines > 0 then
            replacement_lines[#replacement_lines] = replacement_lines[#replacement_lines] .. after_tag
          end

          -- Replace the lines in buffer
          vim.api.nvim_buf_set_lines(bufnr, start_line - 1, end_line, false, replacement_lines)

          completed = completed + 1
          if completed + errors >= pending then
            utils.notify(
              "Transform complete: " .. completed .. " succeeded, " .. errors .. " failed",
              errors > 0 and vim.log.levels.WARN or vim.log.levels.INFO
            )
          end
        end)
      end
    end)
  end
end

--- Transform prompts within a line range (for visual selection)
---@param start_line number Start line (1-indexed)
---@param end_line number End line (1-indexed)
local function cmd_transform_range(start_line, end_line)
  local parser = require("codetyper.parser")
  local llm = require("codetyper.llm")

  local bufnr = vim.api.nvim_get_current_buf()
  local filepath = vim.fn.expand("%:p")

  if filepath == "" then
    utils.notify("No file in current buffer", vim.log.levels.WARN)
    return
  end

  -- Find all prompts in the current buffer
  local all_prompts = parser.find_prompts_in_buffer(bufnr)

  -- Filter prompts that are within the selected range
  local prompts = {}
  for _, prompt in ipairs(all_prompts) do
    if prompt.start_line >= start_line and prompt.end_line <= end_line then
      table.insert(prompts, prompt)
    end
  end

  if #prompts == 0 then
    utils.notify("No /@ @/ tags found in selection (lines " .. start_line .. "-" .. end_line .. ")", vim.log.levels.INFO)
    return
  end

  utils.notify("Found " .. #prompts .. " prompt(s) in selection to transform...", vim.log.levels.INFO)

  -- Build context for this file
  local context = llm.build_context(filepath, "code_generation")

  -- Process prompts in reverse order (bottom to top) to maintain line numbers
  local sorted_prompts = {}
  for i = #prompts, 1, -1 do
    table.insert(sorted_prompts, prompts[i])
  end

  local pending = #sorted_prompts
  local completed = 0
  local errors = 0

  for _, prompt in ipairs(sorted_prompts) do
    local clean_prompt = parser.clean_prompt(prompt.content)

    local enhanced_prompt = "TASK: " .. clean_prompt .. "\n\n"
    enhanced_prompt = enhanced_prompt .. "REQUIREMENTS:\n"
    enhanced_prompt = enhanced_prompt .. "- Generate ONLY " .. (context.language or "code") .. " code\n"
    enhanced_prompt = enhanced_prompt .. "- NO markdown code blocks (no ```)\n"
    enhanced_prompt = enhanced_prompt .. "- NO explanations or comments about what you did\n"
    enhanced_prompt = enhanced_prompt .. "- Match the coding style of the existing file exactly\n"
    enhanced_prompt = enhanced_prompt .. "- Output must be ready to insert directly into the file\n"

    utils.notify("Processing: " .. clean_prompt:sub(1, 40) .. "...", vim.log.levels.INFO)

    llm.generate(enhanced_prompt, context, function(response, err)
      if err then
        utils.notify("Failed: " .. err, vim.log.levels.ERROR)
        errors = errors + 1
      elseif response then
        vim.schedule(function()
          local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
          local p_start_line = prompt.start_line
          local p_end_line = prompt.end_line

          local start_line_content = lines[p_start_line] or ""
          local end_line_content = lines[p_end_line] or ""

          local codetyper = require("codetyper")
          local config = codetyper.get_config()
          local before_tag = ""
          local after_tag = ""

          local open_pos = start_line_content:find(utils.escape_pattern(config.patterns.open_tag))
          if open_pos and open_pos > 1 then
            before_tag = start_line_content:sub(1, open_pos - 1)
          end

          local close_pos = end_line_content:find(utils.escape_pattern(config.patterns.close_tag))
          if close_pos then
            local after_close = close_pos + #config.patterns.close_tag
            if after_close <= #end_line_content then
              after_tag = end_line_content:sub(after_close)
            end
          end

          local replacement_lines = vim.split(response, "\n", { plain = true })

          if before_tag ~= "" and #replacement_lines > 0 then
            replacement_lines[1] = before_tag .. replacement_lines[1]
          end
          if after_tag ~= "" and #replacement_lines > 0 then
            replacement_lines[#replacement_lines] = replacement_lines[#replacement_lines] .. after_tag
          end

          vim.api.nvim_buf_set_lines(bufnr, p_start_line - 1, p_end_line, false, replacement_lines)

          completed = completed + 1
          if completed + errors >= pending then
            utils.notify(
              "Transform complete: " .. completed .. " succeeded, " .. errors .. " failed",
              errors > 0 and vim.log.levels.WARN or vim.log.levels.INFO
            )
          end
        end)
      end
    end)
  end
end

--- Command wrapper for visual selection transform
local function cmd_transform_visual()
  -- Get visual selection marks
  local start_line = vim.fn.line("'<")
  local end_line = vim.fn.line("'>")
  cmd_transform_range(start_line, end_line)
end

--- Transform a single prompt at cursor position
local function cmd_transform_at_cursor()
  local parser = require("codetyper.parser")
  local llm = require("codetyper.llm")

  local bufnr = vim.api.nvim_get_current_buf()
  local filepath = vim.fn.expand("%:p")

  if filepath == "" then
    utils.notify("No file in current buffer", vim.log.levels.WARN)
    return
  end

  -- Find prompt at cursor
  local prompt = parser.get_prompt_at_cursor(bufnr)

  if not prompt then
    utils.notify("No /@ @/ tag at cursor position", vim.log.levels.WARN)
    return
  end

  local clean_prompt = parser.clean_prompt(prompt.content)
  local context = llm.build_context(filepath, "code_generation")

  -- Build enhanced user prompt
  local enhanced_prompt = "TASK: " .. clean_prompt .. "\n\n"
  enhanced_prompt = enhanced_prompt .. "REQUIREMENTS:\n"
  enhanced_prompt = enhanced_prompt .. "- Generate ONLY " .. (context.language or "code") .. " code\n"
  enhanced_prompt = enhanced_prompt .. "- NO markdown code blocks (no ```)\n"
  enhanced_prompt = enhanced_prompt .. "- NO explanations or comments about what you did\n"
  enhanced_prompt = enhanced_prompt .. "- Match the coding style of the existing file exactly\n"
  enhanced_prompt = enhanced_prompt .. "- Output must be ready to insert directly into the file\n"

  utils.notify("Transforming: " .. clean_prompt:sub(1, 40) .. "...", vim.log.levels.INFO)

  llm.generate(enhanced_prompt, context, function(response, err)
    if err then
      utils.notify("Transform failed: " .. err, vim.log.levels.ERROR)
      return
    end

    if response then
      vim.schedule(function()
        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        local start_line = prompt.start_line
        local end_line = prompt.end_line

        local start_line_content = lines[start_line] or ""
        local end_line_content = lines[end_line] or ""

        local codetyper = require("codetyper")
        local config = codetyper.get_config()
        local before_tag = ""
        local after_tag = ""

        local open_pos = start_line_content:find(utils.escape_pattern(config.patterns.open_tag))
        if open_pos and open_pos > 1 then
          before_tag = start_line_content:sub(1, open_pos - 1)
        end

        local close_pos = end_line_content:find(utils.escape_pattern(config.patterns.close_tag))
        if close_pos then
          local after_close = close_pos + #config.patterns.close_tag
          if after_close <= #end_line_content then
            after_tag = end_line_content:sub(after_close)
          end
        end

        local replacement_lines = vim.split(response, "\n", { plain = true })

        if before_tag ~= "" and #replacement_lines > 0 then
          replacement_lines[1] = before_tag .. replacement_lines[1]
        end
        if after_tag ~= "" and #replacement_lines > 0 then
          replacement_lines[#replacement_lines] = replacement_lines[#replacement_lines] .. after_tag
        end

        vim.api.nvim_buf_set_lines(bufnr, start_line - 1, end_line, false, replacement_lines)
        utils.notify("Transform complete!", vim.log.levels.INFO)
      end)
    end
  end)
end

--- Main command dispatcher
---@param args table Command arguments
local function coder_cmd(args)
  local subcommand = args.fargs[1] or "toggle"

  local commands = {
    open = cmd_open,
    close = cmd_close,
    toggle = cmd_toggle,
    process = cmd_process,
    status = cmd_status,
    focus = cmd_focus,
    tree = cmd_tree,
    ["tree-view"] = cmd_tree_view,
    reset = cmd_reset,
    ask = cmd_ask,
    ["ask-close"] = cmd_ask_close,
    ["ask-toggle"] = cmd_ask_toggle,
    ["ask-clear"] = cmd_ask_clear,
    gitignore = cmd_gitignore,
    transform = cmd_transform,
    ["transform-cursor"] = cmd_transform_at_cursor,
  }

  local cmd_fn = commands[subcommand]
  if cmd_fn then
    cmd_fn(args)
  else
    utils.notify("Unknown subcommand: " .. subcommand, vim.log.levels.ERROR)
  end
end

--- Setup all commands
function M.setup()
  vim.api.nvim_create_user_command("Coder", coder_cmd, {
    nargs = "?",
    complete = function()
      return {
        "open", "close", "toggle", "process", "status", "focus",
        "tree", "tree-view", "reset", "gitignore",
        "ask", "ask-close", "ask-toggle", "ask-clear",
        "transform", "transform-cursor",
      }
    end,
    desc = "Codetyper.nvim commands",
  })

  -- Convenience aliases
  vim.api.nvim_create_user_command("CoderOpen", function()
    cmd_open()
  end, { desc = "Open Coder view" })

  vim.api.nvim_create_user_command("CoderClose", function()
    cmd_close()
  end, { desc = "Close Coder view" })

  vim.api.nvim_create_user_command("CoderToggle", function()
    cmd_toggle()
  end, { desc = "Toggle Coder view" })

  vim.api.nvim_create_user_command("CoderProcess", function()
    cmd_process()
  end, { desc = "Process prompt and generate code" })

  vim.api.nvim_create_user_command("CoderTree", function()
    cmd_tree()
  end, { desc = "Refresh tree.log" })

  vim.api.nvim_create_user_command("CoderTreeView", function()
    cmd_tree_view()
  end, { desc = "View tree.log" })

  -- Ask panel commands
  vim.api.nvim_create_user_command("CoderAsk", function()
    cmd_ask()
  end, { desc = "Open Ask panel" })

  vim.api.nvim_create_user_command("CoderAskToggle", function()
    cmd_ask_toggle()
  end, { desc = "Toggle Ask panel" })

  vim.api.nvim_create_user_command("CoderAskClear", function()
    cmd_ask_clear()
  end, { desc = "Clear Ask history" })

  -- Transform commands (inline /@ @/ tag replacement)
  vim.api.nvim_create_user_command("CoderTransform", function()
    cmd_transform()
  end, { desc = "Transform all /@ @/ tags in current file" })

  vim.api.nvim_create_user_command("CoderTransformCursor", function()
    cmd_transform_at_cursor()
  end, { desc = "Transform /@ @/ tag at cursor" })

  vim.api.nvim_create_user_command("CoderTransformVisual", function(opts)
    local start_line = opts.line1
    local end_line = opts.line2
    cmd_transform_range(start_line, end_line)
  end, { range = true, desc = "Transform /@ @/ tags in visual selection" })

  -- Setup default keymaps
  M.setup_keymaps()
end

--- Setup default keymaps for transform commands
function M.setup_keymaps()
  -- Visual mode: transform selected /@ @/ tags
  vim.keymap.set("v", "<leader>ctt", ":<C-u>CoderTransformVisual<CR>", { 
    silent = true, 
    desc = "Coder: Transform selected tags" 
  })

  -- Normal mode: transform tag at cursor
  vim.keymap.set("n", "<leader>ctt", "<cmd>CoderTransformCursor<CR>", { 
    silent = true, 
    desc = "Coder: Transform tag at cursor" 
  })

  -- Normal mode: transform all tags in file
  vim.keymap.set("n", "<leader>ctT", "<cmd>CoderTransform<CR>", { 
    silent = true, 
    desc = "Coder: Transform all tags in file" 
  })
end

return M
