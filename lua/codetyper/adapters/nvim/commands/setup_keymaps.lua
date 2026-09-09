local transform = require("codetyper.core.transform")
local model_menu = require("codetyper.adapters.nvim.ui.model_menu")

local function configured_mapping(config, name, aliases)
  local configured = config and config.keymaps or {}
  local value = configured[name]
  if value == nil then
    for _, alias in ipairs(aliases or {}) do
      if configured[alias] ~= nil then
        value = configured[alias]
        break
      end
    end
  end
  return value
end

local function mapping_options(default, configured)
  if configured == false then
    return nil
  end

  local result = vim.deepcopy(default)
  if type(configured) == "string" then
    result.lhs = configured
  elseif type(configured) == "table" then
    result.lhs = configured.lhs or configured[1] or result.lhs
    result.mode = configured.mode or result.mode
    result.desc = configured.desc or result.desc
    result.silent = configured.silent
    if configured.modes then
      result.mode = configured.modes
    end
  end
  return result
end

local function set_mapping(default, configured)
  local mapping = mapping_options(default, configured)
  if not mapping then
    return
  end
  vim.keymap.set(mapping.mode, mapping.lhs, mapping.rhs, {
    silent = mapping.silent ~= false,
    desc = mapping.desc,
  })
end

--- Setup default keymaps for transform, model, and terminal commands.
---@param config table|nil Codetyper configuration containing keymaps
local function setup_keymaps(config)
  local transform_mapping = configured_mapping(config, "transform", { "transform_selection" })
  local model_mapping = configured_mapping(config, "model", { "model_menu", "select_model" })
  local terminal_mapping = configured_mapping(config, "terminal", {})

  set_mapping({
    mode = "v",
    lhs = "<leader>ctt",
    rhs = function()
      transform.cmd_transform_selection()
    end,
    desc = "Coder: Transform selection with prompt",
  }, transform_mapping)
  set_mapping({
    mode = "n",
    lhs = "<leader>ctt",
    rhs = function()
      transform.cmd_transform_selection()
    end,
    desc = "Coder: Open prompt window",
  }, transform_mapping)

  set_mapping({
    mode = "n",
    lhs = "<leader>ctm",
    rhs = function()
      model_menu.open()
    end,
    desc = "Coder: Select provider model",
  }, model_mapping)

  set_mapping({
    mode = "n",
    lhs = "<leader>ter",
    rhs = function()
      local terminal = require("codetyper.window.terminal")
      terminal.toggle()
    end,
    desc = "Coder: Toggle terminal",
  }, terminal_mapping)
end

return setup_keymaps
