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

  if config.llm.provider == "ollama" then
    table.insert(status, "Ollama Host: " .. config.llm.ollama.host)
    table.insert(status, "Ollama Model: " .. config.llm.ollama.model)
  elseif config.llm.provider == "openai" then
    local has_key = (config.llm.openai.api_key or vim.env.OPENAI_API_KEY) ~= nil
    table.insert(status, "OpenAI API Key: " .. (has_key and "configured" or "NOT SET"))
    table.insert(status, "OpenAI Model: " .. config.llm.openai.model)
  elseif config.llm.provider == "gemini" then
    local has_key = (config.llm.gemini.api_key or vim.env.GEMINI_API_KEY) ~= nil
    table.insert(status, "Gemini API Key: " .. (has_key and "configured" or "NOT SET"))
    table.insert(status, "Gemini Model: " .. config.llm.gemini.model)
  elseif config.llm.provider == "copilot" then
    table.insert(status, "Copilot Model: " .. config.llm.copilot.model)
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

--- Open agent panel
local function cmd_agent()
  local agent_ui = require("codetyper.agent.ui")
  agent_ui.open()
end

--- Close agent panel
local function cmd_agent_close()
  local agent_ui = require("codetyper.agent.ui")
  agent_ui.close()
end

--- Toggle agent panel
local function cmd_agent_toggle()
  local agent_ui = require("codetyper.agent.ui")
  agent_ui.toggle()
end

--- Stop running agent
local function cmd_agent_stop()
  local agent = require("codetyper.agent")
  if agent.is_running() then
    agent.stop()
    utils.notify("Agent stopped")
  else
    utils.notify("No agent running", vim.log.levels.INFO)
  end
end

--- Run the agentic loop with a task
---@param task string The task to accomplish
---@param agent_name? string Optional agent name
local function cmd_agentic_run(task, agent_name)
  local agentic = require("codetyper.agent.agentic")
  local logs_panel = require("codetyper.logs_panel")
  local logs = require("codetyper.agent.logs")

  -- Open logs panel
  logs_panel.open()

  logs.info("Starting agentic task: " .. task:sub(1, 50) .. "...")
  utils.notify("Running agentic task...", vim.log.levels.INFO)

  -- Get current file for context
  local current_file = vim.fn.expand("%:p")
  local files = {}
  if current_file ~= "" then
    table.insert(files, current_file)
  end

  agentic.run({
    task = task,
    files = files,
    agent = agent_name or "coder",
    on_status = function(status)
      logs.thinking(status)
    end,
    on_tool_start = function(name, args)
      logs.info("Tool: " .. name)
    end,
    on_tool_end = function(name, result, err)
      if err then
        logs.error(name .. " failed: " .. err)
      else
        logs.debug(name .. " completed")
      end
    end,
    on_file_change = function(path, action)
      logs.info("File " .. action .. ": " .. path)
    end,
    on_message = function(msg)
      if msg.role == "assistant" and type(msg.content) == "string" and msg.content ~= "" then
        logs.thinking(msg.content:sub(1, 100) .. "...")
      end
    end,
    on_complete = function(result, err)
      if err then
        logs.error("Task failed: " .. err)
        utils.notify("Agentic task failed: " .. err, vim.log.levels.ERROR)
      else
        logs.info("Task completed successfully")
        utils.notify("Agentic task completed!", vim.log.levels.INFO)
        if result and result ~= "" then
          -- Show summary in a float
          vim.schedule(function()
            vim.notify("Result:\n" .. result:sub(1, 500), vim.log.levels.INFO)
          end)
        end
      end
    end,
  })
end

--- List available agents
local function cmd_agentic_list()
  local agentic = require("codetyper.agent.agentic")
  local agents = agentic.list_agents()

  local lines = {
    "Available Agents",
    "================",
    "",
  }

  for _, agent in ipairs(agents) do
    local badge = agent.builtin and "[builtin]" or "[custom]"
    table.insert(lines, string.format("  %s %s", agent.name, badge))
    table.insert(lines, string.format("    %s", agent.description))
    table.insert(lines, "")
  end

  table.insert(lines, "Use :CoderAgenticRun <task> [agent] to run a task")
  table.insert(lines, "Use :CoderAgenticInit to create custom agents")

  utils.notify(table.concat(lines, "\n"))
end

--- Initialize .coder/agents/ and .coder/rules/ directories
local function cmd_agentic_init()
  local agentic = require("codetyper.agent.agentic")
  agentic.init()

  local agents_dir = vim.fn.getcwd() .. "/.coder/agents"
  local rules_dir = vim.fn.getcwd() .. "/.coder/rules"

  local lines = {
    "Initialized Coder directories:",
    "",
    "  " .. agents_dir,
    "    - example.md (template for custom agents)",
    "",
    "  " .. rules_dir,
    "    - code-style.md (template for project rules)",
    "",
    "Edit these files to customize agent behavior.",
    "Create new .md files to add more agents/rules.",
  }

  utils.notify(table.concat(lines, "\n"))
end

--- Show chat type switcher modal (Ask/Agent)
local function cmd_type_toggle()
  local switcher = require("codetyper.chat_switcher")
  switcher.show()
end

--- Toggle logs panel
local function cmd_logs_toggle()
  local logs_panel = require("codetyper.logs_panel")
  logs_panel.toggle()
end

--- Show scheduler status and queue info
local function cmd_queue_status()
  local scheduler = require("codetyper.agent.scheduler")
  local queue = require("codetyper.agent.queue")
  local parser = require("codetyper.parser")

  local status = scheduler.status()
  local bufnr = vim.api.nvim_get_current_buf()
  local filepath = vim.fn.expand("%:p")

  local lines = {
    "Scheduler Status",
    "================",
    "",
    "Running: " .. (status.running and "yes" or "NO"),
    "Paused: " .. (status.paused and "yes" or "no"),
    "Active Workers: " .. status.active_workers,
    "",
    "Queue Stats:",
    "  Pending: " .. status.queue_stats.pending,
    "  Processing: " .. status.queue_stats.processing,
    "  Completed: " .. status.queue_stats.completed,
    "  Cancelled: " .. status.queue_stats.cancelled,
    "",
  }

  -- Check current buffer for prompts
  if filepath ~= "" then
    local prompts = parser.find_prompts_in_buffer(bufnr)
    table.insert(lines, "Current Buffer: " .. vim.fn.fnamemodify(filepath, ":t"))
    table.insert(lines, "  Prompts found: " .. #prompts)
    for i, p in ipairs(prompts) do
      local preview = p.content:sub(1, 30):gsub("\n", " ")
      table.insert(lines, string.format("    %d. Line %d: %s...", i, p.start_line, preview))
    end
  end

  utils.notify(table.concat(lines, "\n"))
end

--- Manually trigger queue processing for current buffer
local function cmd_queue_process()
  local autocmds = require("codetyper.autocmds")
  local logs_panel = require("codetyper.logs_panel")

  -- Open logs panel to show progress
  logs_panel.open()

  -- Check all prompts in current buffer
  autocmds.check_all_prompts()

  utils.notify("Triggered queue processing for current buffer")
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
  local logs_panel = require("codetyper.logs_panel")
  local logs = require("codetyper.agent.logs")

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

  -- Open the logs panel to show generation progress
  logs_panel.open()
  logs.info("Transform started: " .. #prompts .. " prompt(s)")

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

    logs.info("Processing: " .. clean_prompt:sub(1, 40) .. "...")
    utils.notify("Processing: " .. clean_prompt:sub(1, 40) .. "...", vim.log.levels.INFO)

    -- Generate code for this prompt
    llm.generate(enhanced_prompt, context, function(response, err)
      if err then
        logs.error("Failed: " .. err)
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
            local msg = "Transform complete: " .. completed .. " succeeded, " .. errors .. " failed"
            logs.info(msg)
            utils.notify(msg, errors > 0 and vim.log.levels.WARN or vim.log.levels.INFO)
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
  local logs_panel = require("codetyper.logs_panel")
  local logs = require("codetyper.agent.logs")

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

  -- Open the logs panel to show generation progress
  logs_panel.open()
  logs.info("Transform selection: " .. #prompts .. " prompt(s)")

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

    logs.info("Processing: " .. clean_prompt:sub(1, 40) .. "...")
    utils.notify("Processing: " .. clean_prompt:sub(1, 40) .. "...", vim.log.levels.INFO)

    llm.generate(enhanced_prompt, context, function(response, err)
      if err then
        logs.error("Failed: " .. err)
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
            local msg = "Transform complete: " .. completed .. " succeeded, " .. errors .. " failed"
            logs.info(msg)
            utils.notify(msg, errors > 0 and vim.log.levels.WARN or vim.log.levels.INFO)
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

--- Index the entire project
local function cmd_index_project()
  local indexer = require("codetyper.indexer")

  utils.notify("Indexing project...", vim.log.levels.INFO)

  indexer.index_project(function(index)
    if index then
      local msg = string.format(
        "Indexed: %d files, %d functions, %d classes, %d exports",
        index.stats.files,
        index.stats.functions,
        index.stats.classes,
        index.stats.exports
      )
      utils.notify(msg, vim.log.levels.INFO)
    else
      utils.notify("Failed to index project", vim.log.levels.ERROR)
    end
  end)
end

--- Show index status
local function cmd_index_status()
  local indexer = require("codetyper.indexer")
  local memory = require("codetyper.indexer.memory")

  local status = indexer.get_status()
  local mem_stats = memory.get_stats()

  local lines = {
    "Project Index Status",
    "====================",
    "",
  }

  if status.indexed then
    table.insert(lines, "Status: Indexed")
    table.insert(lines, "Project Type: " .. (status.project_type or "unknown"))
    table.insert(lines, "Last Indexed: " .. os.date("%Y-%m-%d %H:%M:%S", status.last_indexed))
    table.insert(lines, "")
    table.insert(lines, "Stats:")
    table.insert(lines, "  Files: " .. (status.stats.files or 0))
    table.insert(lines, "  Functions: " .. (status.stats.functions or 0))
    table.insert(lines, "  Classes: " .. (status.stats.classes or 0))
    table.insert(lines, "  Exports: " .. (status.stats.exports or 0))
  else
    table.insert(lines, "Status: Not indexed")
    table.insert(lines, "Run :CoderIndexProject to index")
  end

  table.insert(lines, "")
  table.insert(lines, "Memories:")
  table.insert(lines, "  Patterns: " .. mem_stats.patterns)
  table.insert(lines, "  Conventions: " .. mem_stats.conventions)
  table.insert(lines, "  Symbols: " .. mem_stats.symbols)

  utils.notify(table.concat(lines, "\n"))
end

--- Show learned memories
local function cmd_memories()
  local memory = require("codetyper.indexer.memory")

  local all = memory.get_all()
  local lines = {
    "Learned Memories",
    "================",
    "",
    "Patterns:",
  }

  local pattern_count = 0
  for _, mem in pairs(all.patterns) do
    pattern_count = pattern_count + 1
    if pattern_count <= 10 then
      table.insert(lines, "  - " .. (mem.content or ""):sub(1, 60))
    end
  end
  if pattern_count > 10 then
    table.insert(lines, "  ... and " .. (pattern_count - 10) .. " more")
  elseif pattern_count == 0 then
    table.insert(lines, "  (none)")
  end

  table.insert(lines, "")
  table.insert(lines, "Conventions:")

  local conv_count = 0
  for _, mem in pairs(all.conventions) do
    conv_count = conv_count + 1
    if conv_count <= 10 then
      table.insert(lines, "  - " .. (mem.content or ""):sub(1, 60))
    end
  end
  if conv_count > 10 then
    table.insert(lines, "  ... and " .. (conv_count - 10) .. " more")
  elseif conv_count == 0 then
    table.insert(lines, "  (none)")
  end

  utils.notify(table.concat(lines, "\n"))
end

--- Clear memories
---@param pattern string|nil Optional pattern to match
local function cmd_forget(pattern)
  local memory = require("codetyper.indexer.memory")

  if not pattern or pattern == "" then
    -- Confirm before clearing all
    vim.ui.select({ "Yes", "No" }, {
      prompt = "Clear all memories?",
    }, function(choice)
      if choice == "Yes" then
        memory.clear()
        utils.notify("All memories cleared", vim.log.levels.INFO)
      end
    end)
  else
    memory.clear(pattern)
    utils.notify("Cleared memories matching: " .. pattern, vim.log.levels.INFO)
  end
end

--- Transform a single prompt at cursor position
local function cmd_transform_at_cursor()
  local parser = require("codetyper.parser")
  local llm = require("codetyper.llm")
  local logs_panel = require("codetyper.logs_panel")
  local logs = require("codetyper.agent.logs")

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

  -- Open the logs panel to show generation progress
  logs_panel.open()

  local clean_prompt = parser.clean_prompt(prompt.content)
  local context = llm.build_context(filepath, "code_generation")

  logs.info("Transform cursor: " .. clean_prompt:sub(1, 40) .. "...")

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
      logs.error("Transform failed: " .. err)
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
        logs.info("Transform complete!")
        utils.notify("Transform complete!", vim.log.levels.INFO)
      end)
    end
  end)
end

--- Main command dispatcher
---@param args table Command arguments
--- Show LLM accuracy statistics
local function cmd_llm_stats()
  local llm = require("codetyper.llm")
  local stats = llm.get_accuracy_stats()

  local lines = {
    "LLM Provider Accuracy Statistics",
    "================================",
    "",
    string.format("Ollama:"),
    string.format("  Total requests: %d", stats.ollama.total),
    string.format("  Correct: %d", stats.ollama.correct),
    string.format("  Accuracy: %.1f%%", stats.ollama.accuracy * 100),
    "",
    string.format("Copilot:"),
    string.format("  Total requests: %d", stats.copilot.total),
    string.format("  Correct: %d", stats.copilot.correct),
    string.format("  Accuracy: %.1f%%", stats.copilot.accuracy * 100),
    "",
    "Note: Smart selection prefers Ollama when brain memories",
    "provide enough context. Accuracy improves over time via",
    "pondering (verification with other LLMs).",
  }

  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

--- Report feedback on last LLM response
---@param was_good boolean Whether the response was good
local function cmd_llm_feedback(was_good)
  local llm = require("codetyper.llm")
  -- Get the last used provider from logs or default
  local provider = "ollama" -- Default assumption

  -- Try to get actual last provider from logs
  pcall(function()
    local logs = require("codetyper.agent.logs")
    local entries = logs.get(10)
    for i = #entries, 1, -1 do
      local entry = entries[i]
      if entry.message and entry.message:match("^LLM:") then
        provider = entry.message:match("LLM: (%w+)") or provider
        break
      end
    end
  end)

  llm.report_feedback(provider, was_good)
  local feedback_type = was_good and "positive" or "negative"
  utils.notify(string.format("Reported %s feedback for %s", feedback_type, provider), vim.log.levels.INFO)
end

--- Reset LLM accuracy statistics
local function cmd_llm_reset_stats()
  local selector = require("codetyper.llm.selector")
  selector.reset_accuracy_stats()
  utils.notify("LLM accuracy statistics reset", vim.log.levels.INFO)
end

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
    agent = cmd_agent,
    ["agent-close"] = cmd_agent_close,
    ["agent-toggle"] = cmd_agent_toggle,
    ["agent-stop"] = cmd_agent_stop,
    ["type-toggle"] = cmd_type_toggle,
    ["logs-toggle"] = cmd_logs_toggle,
    ["queue-status"] = cmd_queue_status,
    ["queue-process"] = cmd_queue_process,
    -- Agentic commands
    ["agentic-run"] = function(args)
      local task = table.concat(vim.list_slice(args.fargs, 2), " ")
      if task == "" then
        utils.notify("Usage: Coder agentic-run <task> [agent]", vim.log.levels.WARN)
        return
      end
      cmd_agentic_run(task)
    end,
    ["agentic-list"] = cmd_agentic_list,
    ["agentic-init"] = cmd_agentic_init,
    ["index-project"] = cmd_index_project,
    ["index-status"] = cmd_index_status,
    memories = cmd_memories,
    forget = function(args)
      cmd_forget(args.fargs[2])
    end,
    ["auto-toggle"] = function()
      local preferences = require("codetyper.preferences")
      preferences.toggle_auto_process()
    end,
    ["auto-set"] = function(args)
      local preferences = require("codetyper.preferences")
      local arg = (args[1] or ""):lower()
      if arg == "auto" or arg == "automatic" or arg == "on" then
        preferences.set_auto_process(true)
        utils.notify("Set to automatic mode", vim.log.levels.INFO)
      elseif arg == "manual" or arg == "off" then
        preferences.set_auto_process(false)
        utils.notify("Set to manual mode", vim.log.levels.INFO)
      else
        local auto = preferences.is_auto_process_enabled()
        if auto == nil then
          utils.notify("Mode not set yet (will ask on first prompt)", vim.log.levels.INFO)
        else
          local mode = auto and "automatic" or "manual"
          utils.notify("Currently in " .. mode .. " mode", vim.log.levels.INFO)
        end
      end
    end,
    -- LLM smart selection commands
    ["llm-stats"] = cmd_llm_stats,
    ["llm-feedback-good"] = function()
      cmd_llm_feedback(true)
    end,
    ["llm-feedback-bad"] = function()
      cmd_llm_feedback(false)
    end,
    ["llm-reset-stats"] = cmd_llm_reset_stats,
    -- Cost tracking commands
    ["cost"] = function()
      local cost = require("codetyper.cost")
      cost.toggle()
    end,
    ["cost-clear"] = function()
      local cost = require("codetyper.cost")
      cost.clear()
    end,
    -- Credentials management commands
    ["add-api-key"] = function()
      local credentials = require("codetyper.credentials")
      credentials.interactive_add()
    end,
    ["remove-api-key"] = function()
      local credentials = require("codetyper.credentials")
      credentials.interactive_remove()
    end,
    ["credentials"] = function()
      local credentials = require("codetyper.credentials")
      credentials.show_status()
    end,
    ["switch-provider"] = function()
      local credentials = require("codetyper.credentials")
      credentials.interactive_switch_provider()
    end,
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
        "agent", "agent-close", "agent-toggle", "agent-stop",
        "agentic-run", "agentic-list", "agentic-init",
        "type-toggle", "logs-toggle",
        "queue-status", "queue-process",
        "index-project", "index-status", "memories", "forget",
        "auto-toggle", "auto-set",
        "llm-stats", "llm-feedback-good", "llm-feedback-bad", "llm-reset-stats",
        "cost", "cost-clear",
        "add-api-key", "remove-api-key", "credentials", "switch-provider",
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

  -- Agent commands
  vim.api.nvim_create_user_command("CoderAgent", function()
    cmd_agent()
  end, { desc = "Open Agent panel" })

  vim.api.nvim_create_user_command("CoderAgentToggle", function()
    cmd_agent_toggle()
  end, { desc = "Toggle Agent panel" })

  vim.api.nvim_create_user_command("CoderAgentStop", function()
    cmd_agent_stop()
  end, { desc = "Stop running agent" })

  -- Agentic commands (full IDE-like agent functionality)
  vim.api.nvim_create_user_command("CoderAgenticRun", function(opts)
    local task = opts.args
    if task == "" then
      vim.ui.input({ prompt = "Task: " }, function(input)
        if input and input ~= "" then
          cmd_agentic_run(input)
        end
      end)
    else
      cmd_agentic_run(task)
    end
  end, {
    desc = "Run agentic task (IDE-like multi-file changes)",
    nargs = "*",
  })

  vim.api.nvim_create_user_command("CoderAgenticList", function()
    cmd_agentic_list()
  end, { desc = "List available agents" })

  vim.api.nvim_create_user_command("CoderAgenticInit", function()
    cmd_agentic_init()
  end, { desc = "Initialize .coder/agents/ and .coder/rules/ directories" })

  -- Chat type switcher command
  vim.api.nvim_create_user_command("CoderType", function()
    cmd_type_toggle()
  end, { desc = "Show Ask/Agent mode switcher" })

  -- Logs panel command
  vim.api.nvim_create_user_command("CoderLogs", function()
    cmd_logs_toggle()
  end, { desc = "Toggle logs panel" })

  -- Index command - open coder companion for current file
  vim.api.nvim_create_user_command("CoderIndex", function()
    local autocmds = require("codetyper.autocmds")
    autocmds.open_coder_companion()
  end, { desc = "Open coder companion for current file" })

  -- Project indexer commands
  vim.api.nvim_create_user_command("CoderIndexProject", function()
    cmd_index_project()
  end, { desc = "Index the entire project" })

  vim.api.nvim_create_user_command("CoderIndexStatus", function()
    cmd_index_status()
  end, { desc = "Show project index status" })

  vim.api.nvim_create_user_command("CoderMemories", function()
    cmd_memories()
  end, { desc = "Show learned memories" })

  vim.api.nvim_create_user_command("CoderForget", function(opts)
    cmd_forget(opts.args ~= "" and opts.args or nil)
  end, {
    desc = "Clear memories (optionally matching pattern)",
    nargs = "?",
  })

  -- Queue commands
  vim.api.nvim_create_user_command("CoderQueueStatus", function()
    cmd_queue_status()
  end, { desc = "Show scheduler and queue status" })

  vim.api.nvim_create_user_command("CoderQueueProcess", function()
    cmd_queue_process()
  end, { desc = "Manually trigger queue processing" })

  -- Preferences commands
  vim.api.nvim_create_user_command("CoderAutoToggle", function()
    local preferences = require("codetyper.preferences")
    preferences.toggle_auto_process()
  end, { desc = "Toggle automatic/manual prompt processing" })

  vim.api.nvim_create_user_command("CoderAutoSet", function(opts)
    local preferences = require("codetyper.preferences")
    local arg = opts.args:lower()
    if arg == "auto" or arg == "automatic" or arg == "on" then
      preferences.set_auto_process(true)
      vim.notify("Codetyper: Set to automatic mode", vim.log.levels.INFO)
    elseif arg == "manual" or arg == "off" then
      preferences.set_auto_process(false)
      vim.notify("Codetyper: Set to manual mode", vim.log.levels.INFO)
    else
      -- Show current mode
      local auto = preferences.is_auto_process_enabled()
      if auto == nil then
        vim.notify("Codetyper: Mode not set yet (will ask on first prompt)", vim.log.levels.INFO)
      else
        local mode = auto and "automatic" or "manual"
        vim.notify("Codetyper: Currently in " .. mode .. " mode", vim.log.levels.INFO)
      end
    end
  end, {
    desc = "Set prompt processing mode (auto/manual)",
    nargs = "?",
    complete = function()
      return { "auto", "manual" }
    end,
  })

  -- Brain feedback command - teach the brain from your experience
  vim.api.nvim_create_user_command("CoderFeedback", function(opts)
    local brain = require("codetyper.brain")
    if not brain.is_initialized() then
      vim.notify("Brain not initialized", vim.log.levels.WARN)
      return
    end

    local feedback_type = opts.args:lower()
    local current_file = vim.fn.expand("%:p")

    if feedback_type == "good" or feedback_type == "accept" or feedback_type == "+" then
      -- Learn positive feedback
      brain.learn({
        type = "user_feedback",
        file = current_file,
        timestamp = os.time(),
        data = {
          feedback = "accepted",
          description = "User marked code as good/accepted",
        },
      })
      vim.notify("Brain: Learned positive feedback ✓", vim.log.levels.INFO)

    elseif feedback_type == "bad" or feedback_type == "reject" or feedback_type == "-" then
      -- Learn negative feedback
      brain.learn({
        type = "user_feedback",
        file = current_file,
        timestamp = os.time(),
        data = {
          feedback = "rejected",
          description = "User marked code as bad/rejected",
        },
      })
      vim.notify("Brain: Learned negative feedback ✗", vim.log.levels.INFO)

    elseif feedback_type == "stats" or feedback_type == "status" then
      -- Show brain stats
      local stats = brain.stats()
      local msg = string.format(
        "Brain Stats:\n• Nodes: %d\n• Edges: %d\n• Pending: %d\n• Deltas: %d",
        stats.node_count or 0,
        stats.edge_count or 0,
        stats.pending_changes or 0,
        stats.delta_count or 0
      )
      vim.notify(msg, vim.log.levels.INFO)

    else
      vim.notify("Usage: CoderFeedback <good|bad|stats>", vim.log.levels.INFO)
    end
  end, {
    desc = "Give feedback to the brain (good/bad/stats)",
    nargs = "?",
    complete = function()
      return { "good", "bad", "stats" }
    end,
  })

  -- Brain stats command
  vim.api.nvim_create_user_command("CoderBrain", function(opts)
    local brain = require("codetyper.brain")
    if not brain.is_initialized() then
      vim.notify("Brain not initialized", vim.log.levels.WARN)
      return
    end

    local action = opts.args:lower()

    if action == "stats" or action == "" then
      local stats = brain.stats()
      local lines = {
        "╭─────────────────────────────────╮",
        "│       CODETYPER BRAIN           │",
        "╰─────────────────────────────────╯",
        "",
        string.format("  Nodes: %d", stats.node_count or 0),
        string.format("  Edges: %d", stats.edge_count or 0),
        string.format("  Deltas: %d", stats.delta_count or 0),
        string.format("  Pending: %d", stats.pending_changes or 0),
        "",
        "  The more you use Codetyper,",
        "  the smarter it becomes!",
      }
      vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)

    elseif action == "commit" then
      local hash = brain.commit("Manual commit")
      if hash then
        vim.notify("Brain: Committed changes (hash: " .. hash:sub(1, 8) .. ")", vim.log.levels.INFO)
      else
        vim.notify("Brain: Nothing to commit", vim.log.levels.INFO)
      end

    elseif action == "flush" then
      brain.flush()
      vim.notify("Brain: Flushed to disk", vim.log.levels.INFO)

    elseif action == "prune" then
      local pruned = brain.prune()
      vim.notify("Brain: Pruned " .. pruned .. " low-value nodes", vim.log.levels.INFO)

    else
      vim.notify("Usage: CoderBrain <stats|commit|flush|prune>", vim.log.levels.INFO)
    end
  end, {
    desc = "Brain management commands",
    nargs = "?",
    complete = function()
      return { "stats", "commit", "flush", "prune" }
    end,
  })

  -- Cost estimation command
  vim.api.nvim_create_user_command("CoderCost", function()
    local cost = require("codetyper.cost")
    cost.toggle()
  end, { desc = "Show LLM cost estimation window" })

  -- Credentials management commands
  vim.api.nvim_create_user_command("CoderAddApiKey", function()
    local credentials = require("codetyper.credentials")
    credentials.interactive_add()
  end, { desc = "Add or update LLM provider API key" })

  vim.api.nvim_create_user_command("CoderRemoveApiKey", function()
    local credentials = require("codetyper.credentials")
    credentials.interactive_remove()
  end, { desc = "Remove LLM provider credentials" })

  vim.api.nvim_create_user_command("CoderCredentials", function()
    local credentials = require("codetyper.credentials")
    credentials.show_status()
  end, { desc = "Show credentials status" })

  vim.api.nvim_create_user_command("CoderSwitchProvider", function()
    local credentials = require("codetyper.credentials")
    credentials.interactive_switch_provider()
  end, { desc = "Switch active LLM provider" })

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

  -- Agent keymaps
  vim.keymap.set("n", "<leader>ca", "<cmd>CoderAgentToggle<CR>", {
    silent = true,
    desc = "Coder: Toggle Agent panel"
  })

  -- Index keymap - open coder companion
  vim.keymap.set("n", "<leader>ci", "<cmd>CoderIndex<CR>", {
    silent = true,
    desc = "Coder: Open coder companion for file"
  })
end

return M
