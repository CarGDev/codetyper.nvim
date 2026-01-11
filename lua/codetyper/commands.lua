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

  llm.generate(clean_prompt, context, function(response, err)
    if err then
      utils.notify("Generation failed: " .. err, vim.log.levels.ERROR)
      return
    end

    if response then
      -- Inject code into target file
      local inject = require("codetyper.inject")
      inject.inject_code(target_path, response, prompt_type)
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
end

return M
