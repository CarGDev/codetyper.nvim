local utils = require("codetyper.support.utils")
local transform = require("codetyper.core.transform")
local cmd_reset = require("codetyper.adapters.nvim.commands.cmd_reset")
local cmd_index_project = require("codetyper.adapters.nvim.commands.cmd_index_project")
local cmd_index_status = require("codetyper.adapters.nvim.commands.cmd_index_status")
local cmd_llm_stats = require("codetyper.adapters.nvim.commands.cmd_llm_stats")
local cmd_llm_reset_stats = require("codetyper.adapters.nvim.commands.cmd_llm_reset_stats")

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
    ["switch-provider"] = function()
      local credentials = require("codetyper.config.credentials")
      credentials.interactive_switch_provider()
    end,
    ["model"] = function(cmd_args)
      local credentials = require("codetyper.config.credentials")
      local codetyper = require("codetyper")
      local config = codetyper.get_config()
      local provider = config.llm.provider

      if provider ~= "copilot" then
        utils.notify(
          "CoderModel is only available when using Copilot provider. Current: " .. provider:upper(),
          vim.log.levels.WARN
        )
        return
      end

      local model_arg = cmd_args.fargs[2]
      if model_arg and model_arg ~= "" then
        local model_cost = credentials.get_copilot_model_cost(model_arg) or "custom"
        credentials.set_credentials("copilot", { model = model_arg, configured = true })
        utils.notify("Copilot model set to: " .. model_arg .. " — " .. model_cost, vim.log.levels.INFO)
      else
        credentials.interactive_copilot_config(true)
      end
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
