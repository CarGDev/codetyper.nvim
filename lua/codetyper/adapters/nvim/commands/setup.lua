local utils = require("codetyper.support.utils")
local transform = require("codetyper.core.transform")
local coder_cmd = require("codetyper.adapters.nvim.commands.coder_cmd")
local cmd_tree = require("codetyper.adapters.nvim.commands.cmd_tree")
local cmd_tree_view = require("codetyper.adapters.nvim.commands.cmd_tree_view")
local cmd_index_project = require("codetyper.adapters.nvim.commands.cmd_index_project")
local cmd_index_status = require("codetyper.adapters.nvim.commands.cmd_index_status")
local setup_keymaps = require("codetyper.adapters.nvim.commands.setup_keymaps")

--- Setup all commands
local function setup()
  vim.api.nvim_create_user_command("Coder", coder_cmd, {
    nargs = "?",
    complete = function()
      return {
        "version",
        "tree",
        "tree-view",
        "reset",
        "gitignore",
        "transform-selection",
        "index-project",
        "index-status",
        "llm-stats",
        "llm-reset-stats",
        "cost",
        "cost-clear",
        "credentials",
        "switch-provider",
        "model",
      }
    end,
    desc = "Codetyper.nvim commands",
  })

  vim.api.nvim_create_user_command("CoderTree", function()
    cmd_tree()
  end, { desc = "Refresh tree.log" })

  vim.api.nvim_create_user_command("CoderTreeView", function()
    cmd_tree_view()
  end, { desc = "View tree.log" })

  vim.api.nvim_create_user_command("CoderTransformSelection", function()
    transform.cmd_transform_selection()
  end, { desc = "Transform visual selection with custom prompt input" })

  vim.api.nvim_create_user_command("CoderIndexProject", function()
    cmd_index_project()
  end, { desc = "Index the entire project" })

  vim.api.nvim_create_user_command("CoderIndexStatus", function()
    cmd_index_status()
  end, { desc = "Show project index status" })

  -- TODO: re-enable CoderMemories, CoderForget when memory UI is reworked
  -- TODO: re-enable CoderFeedback when feedback loop is reworked
  -- TODO: re-enable CoderBrain when brain management UI is reworked

  vim.api.nvim_create_user_command("CoderCost", function()
    local cost_window = require("codetyper.window.cost")
    cost_window.toggle()
  end, { desc = "Show LLM cost estimation window" })

  -- TODO: re-enable CoderAddApiKey when multi-provider support returns

  vim.api.nvim_create_user_command("CoderCredentials", function()
    local credentials = require("codetyper.config.credentials")
    credentials.show_status()
  end, { desc = "Show credentials status" })

  vim.api.nvim_create_user_command("CoderSwitchProvider", function()
    local credentials = require("codetyper.config.credentials")
    credentials.interactive_switch_provider()
  end, { desc = "Switch active LLM provider" })

  vim.api.nvim_create_user_command("CoderModel", function(opts)
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

    if opts.args and opts.args ~= "" then
      local model_cost = credentials.get_copilot_model_cost(opts.args) or "custom"
      credentials.set_credentials("copilot", { model = opts.args, configured = true })
      utils.notify("Copilot model set to: " .. opts.args .. " — " .. model_cost, vim.log.levels.INFO)
      return
    end

    credentials.interactive_copilot_config(true)
  end, {
    nargs = "?",
    desc = "Quick switch Copilot model (only available with Copilot provider)",
    complete = function()
      local codetyper = require("codetyper")
      local credentials = require("codetyper.config.credentials")
      local config = codetyper.get_config()
      if config.llm.provider == "copilot" then
        return credentials.get_copilot_model_names()
      end
      return {}
    end,
  })

  setup_keymaps()
end

return setup
