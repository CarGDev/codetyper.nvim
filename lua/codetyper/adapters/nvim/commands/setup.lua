local utils = require("codetyper.support.utils")
local transform = require("codetyper.core.transform")
local coder_cmd = require("codetyper.adapters.nvim.commands.coder_cmd")
local cmd_index_project = require("codetyper.adapters.nvim.commands.cmd_index_project")
local cmd_index_status = require("codetyper.adapters.nvim.commands.cmd_index_status")
local setup_keymaps = require("codetyper.adapters.nvim.commands.setup_keymaps")
local model_menu = require("codetyper.adapters.nvim.ui.model_menu")

local CODER_COMMANDS = {
  "version",
  "reset",
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
  "auth",
}

local function complete_coder(arglead, cmdline)
  if cmdline and cmdline:match("^%s*Coder%s+model%s+") then
    return model_menu.complete(arglead)
  end
  return CODER_COMMANDS
end

--- Setup all commands
local function setup()
  vim.api.nvim_create_user_command("Coder", coder_cmd, {
    nargs = "?",
    complete = complete_coder,
    desc = "Codetyper.nvim commands",
  })

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

  vim.api.nvim_create_user_command("CoderAutotrigger", function()
    local ct_constants = require("codetyper.constants.constants")
    ct_constants.autotrigger = not ct_constants.autotrigger
    vim.notify(
      "Coder autotrigger: " .. (ct_constants.autotrigger and "ON (auto)" or "OFF (manual)"),
      vim.log.levels.INFO
    )
  end, { desc = "Toggle /@ @/ auto-trigger (auto/manual)" })

  vim.api.nvim_create_user_command("CoderProcess", function()
    local check_all = require("codetyper.adapters.nvim.autocmds.check_all_prompts")
    check_all()
  end, { desc = "Manually process /@ @/ tags in current buffer" })

  -- TODO: re-enable CoderAddApiKey when multi-provider support returns

  vim.api.nvim_create_user_command("CoderCredentials", function()
    local credentials = require("codetyper.config.credentials")
    credentials.show_status()
  end, { desc = "Show credentials status" })

  vim.api.nvim_create_user_command("CoderSwitchProvider", function()
    local credentials = require("codetyper.config.credentials")
    credentials.interactive_switch_provider()
  end, { desc = "Switch active LLM provider" })

  vim.api.nvim_create_user_command("CoderAuth", function()
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
  end, { desc = "Connect to GitHub Copilot (only runs the auth flow if not already connected)" })

  vim.api.nvim_create_user_command("CoderModel", function(opts)
    model_menu.command(opts.args)
  end, {
    nargs = "?",
    desc = "Select a provider-labelled model",
    complete = function(arglead)
      return model_menu.complete(arglead)
    end,
  })

  local codetyper = require("codetyper")
  setup_keymaps(codetyper.get_config())
end

return setup
