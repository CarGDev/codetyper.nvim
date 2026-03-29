local utils = require("codetyper.support.utils")
local transform = require("codetyper.core.transform")
local cmd_tree = require("codetyper.adapters.nvim.commands.cmd_tree")
local cmd_tree_view = require("codetyper.adapters.nvim.commands.cmd_tree_view")
local cmd_reset = require("codetyper.adapters.nvim.commands.cmd_reset")
local cmd_gitignore = require("codetyper.adapters.nvim.commands.cmd_gitignore")
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
    tree = cmd_tree,
    ["tree-view"] = cmd_tree_view,
    reset = cmd_reset,
    gitignore = cmd_gitignore,
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
