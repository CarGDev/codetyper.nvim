local utils = require("codetyper.support.utils")
local transform = require("codetyper.core.transform")
local cmd_reset = require("codetyper.adapters.nvim.commands.cmd_reset")
local cmd_index_project = require("codetyper.adapters.nvim.commands.cmd_index_project")
local cmd_index_status = require("codetyper.adapters.nvim.commands.cmd_index_status")
local cmd_llm_stats = require("codetyper.adapters.nvim.commands.cmd_llm_stats")
local cmd_llm_reset_stats = require("codetyper.adapters.nvim.commands.cmd_llm_reset_stats")
local model_menu = require("codetyper.adapters.nvim.ui.model_menu")

--- Main command dispatcher
---@param args table Command arguments
local function coder_cmd(args)
  local subcommand = args.fargs[1] or "version"

  local commands = {
    ["version"] = function()
      local codetyper = require("codetyper")
      utils.notify("Codetyper.nvim " .. codetyper.version, vim.log.levels.INFO)
    end,
    reset = cmd_reset,
    ["transform-selection"] = transform.cmd_transform_selection,
    ["index-project"] = cmd_index_project,
    ["index-status"] = cmd_index_status,
    ["llm-stats"] = cmd_llm_stats,
    ["llm-reset-stats"] = cmd_llm_reset_stats,
    ["cost"] = function()
      local cost_window = require("codetyper.window.cost")
      cost_window.toggle()
    end,
    ["cost-clear"] = function()
      local session = require("codetyper.core.cost.session")
      session.clear()
    end,
    ["terminal"] = function()
      local terminal = require("codetyper.window.terminal")
      terminal.toggle()
    end,
    ["queue"] = function()
      local queue_window = require("codetyper.window.queue")
      queue_window.toggle()
    end,
    ["autotrigger"] = function()
      local constants = require("codetyper.constants.constants")
      constants.autotrigger = not constants.autotrigger
      vim.notify(
        "Coder autotrigger: " .. (constants.autotrigger and "ON (auto)" or "OFF (manual)"),
        vim.log.levels.INFO
      )
    end,
    ["process"] = function()
      -- Manual trigger: process all /@ @/ tags in current buffer
      local check_all = require("codetyper.adapters.nvim.autocmds.check_all_prompts")
      check_all()
    end,
    ["credentials"] = function()
      local credentials = require("codetyper.config.credentials")
      credentials.show_status()
    end,
    ["auth"] = function()
      local requested_provider = args.fargs[2]
      if requested_provider == "openai" then
        local openai_auth = require("codetyper.core.llm.providers.openai.auth")
        local mode = args.fargs[3] or "browser"
        openai_auth.start(mode, function(_, err)
          if err then
            utils.notify("OpenAI ChatGPT authentication failed: " .. err, vim.log.levels.ERROR)
          else
            utils.notify("Connected to OpenAI (ChatGPT Plus/Pro) successfully!", vim.log.levels.INFO)
          end
        end)
        return
      end
      local auth = require("codetyper.core.llm.providers.copilot.auth")
      auth.is_valid(function(valid)
        if valid then
          utils.notify("Already connected to GitHub Copilot.", vim.log.levels.INFO)
          return
        end

        local device_auth = require("codetyper.core.llm.providers.copilot.device_auth")
        device_auth.start(function(success, err)
          if success then
            utils.notify("Connected to GitHub Copilot successfully!", vim.log.levels.INFO)
          else
            utils.notify("GitHub Copilot authentication failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
          end
        end)
      end)
    end,
    ["switch-provider"] = function()
      local credentials = require("codetyper.config.credentials")
      credentials.interactive_switch_provider()
    end,
    ["model"] = function(cmd_args)
      model_menu.command(cmd_args.fargs[2])
    end,
  }

  local cmd_fn = commands[subcommand]
  if cmd_fn then
    cmd_fn(args)
  else
    utils.notify("Unknown subcommand: " .. subcommand, vim.log.levels.ERROR)
  end
end

return coder_cmd
