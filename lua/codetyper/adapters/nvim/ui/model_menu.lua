--- Provider-labelled, asynchronous Coder model selection for Neovim.
local catalog_module = require("codetyper.core.llm.model_catalog")

local M = {}

local PROVIDER_LABELS = {
  ollama = "Ollama",
  copilot = "GitHub Copilot",
  claude = "Anthropic",
  openai = "OpenAI (ChatGPT Plus/Pro)",
}

local active_session = nil
local active_catalog = nil
local default_catalog = nil

---@param provider string
---@return string
function M.provider_label(provider)
  return PROVIDER_LABELS[provider] or (provider:gsub("^%l", string.upper))
end

---@param descriptor table
---@return string
function M.format_item(descriptor)
  local provider = M.provider_label(descriptor.provider or "unknown")
  local name = descriptor.name or descriptor.id or "unknown"
  local id = descriptor.id or name
  if name == id then
    return string.format("[%s] %s", provider, name)
  end
  return string.format("[%s] %s (%s)", provider, name, id)
end

---@param descriptor table
---@return string
local function completion_value(descriptor)
  return string.format("%s/%s", descriptor.provider, descriptor.id)
end

---@return table
local function empty_snapshot()
  return { status = "empty", revision = 0, models = {}, providers = {} }
end

---@param options table|nil
---@return table
local function make_default_catalog(options)
  options = options or {}
  local ollama = require("codetyper.core.llm.providers.ollama.models")
  local copilot = require("codetyper.core.llm.providers.copilot.models")
  local claude = require("codetyper.core.llm.providers.claude.models")
  local openai = require("codetyper.core.llm.providers.openai.models")

  return catalog_module.new({
    ttl = options.ttl,
    providers = {
      ollama = function(callback)
        return ollama.fetch(options.ollama_host, callback)
      end,
      copilot = function(callback)
        return copilot.fetch(callback)
      end,
      claude = function(callback)
        return claude.fetch(callback, options.anthropic)
      end,
      openai = openai.source(options.openai),
    },
  })
end

---@param options table|nil
---@return table
local function get_catalog(options)
  if options and options.catalog then
    return options.catalog
  end
  if not default_catalog then
    default_catalog = make_default_catalog(options)
  end
  return default_catalog
end

---@return table
function M.snapshot()
  if active_catalog and active_catalog.snapshot then
    return active_catalog.snapshot()
  end
  return empty_snapshot()
end

--- Cancel the currently displayed or loading model menu.
function M.cancel()
  if not active_session then
    return
  end
  active_session.cancelled = true
  if active_session.handle and active_session.handle.cancel then
    active_session.handle.cancel()
  end
  active_session = nil
end

---@param choice table
---@param options table|nil
---@return boolean, string|nil
function M.apply_choice(choice, options)
  if not choice then
    return false, "cancelled"
  end

  options = options or {}
  local credentials = options.credentials or require("codetyper.config.credentials")
  local provider, model = choice.provider, choice.id
  if type(provider) ~= "string" or provider == "" or type(model) ~= "string" or model == "" then
    return false, "The selected model has no provider or model ID"
  end

  if credentials.set_credentials then
    local ok = credentials.set_credentials(provider, { model = model, configured = true })
    if ok == false then
      return false, "Failed to save the selected model"
    end
  end
  if credentials.set_active_provider then
    local ok = credentials.set_active_provider(provider)
    if ok == false then
      return false, "Failed to activate the selected provider"
    end
  end
  if options.on_select then
    options.on_select(choice)
  end
  return true, nil
end

---@param value string
---@param options table|nil
---@return boolean, string|nil
function M.select_argument(value, options)
  options = options or {}
  if type(value) ~= "string" or value == "" then
    return false, "missing model"
  end

  local provider, id = value:match("^([%w_-]+)/(.+)$")
  local snapshot = M.snapshot()
  local match
  for _, descriptor in ipairs(snapshot.models or {}) do
    if descriptor.id == (id or value) and (not provider or descriptor.provider == provider) then
      match = descriptor
      break
    end
  end

  if not match then
    if not provider then
      provider = options.provider
      if not provider then
        local ok, codetyper = pcall(require, "codetyper")
        local config = ok and codetyper.get_config and codetyper.get_config() or nil
        provider = config and config.llm and config.llm.provider or "copilot"
      end
      id = value
    end
    match = { id = id, name = id, provider = provider }
  end

  return M.apply_choice(match, options)
end

---@param arglead string|nil
---@return string[]
function M.complete(arglead)
  arglead = arglead or ""
  local needle = arglead:lower()
  local result = {}
  for _, descriptor in ipairs(M.snapshot().models or {}) do
    local candidate = completion_value(descriptor)
    if needle == "" or candidate:lower():find(needle, 1, true) or descriptor.id:lower():find(needle, 1, true) then
      result[#result + 1] = candidate
    end
  end
  table.sort(result)
  return result
end

---@param options table|nil
---@return table handle
function M.open(options)
  options = options or {}
  M.cancel()

  local session = { cancelled = false, handle = nil }
  active_session = session
  active_catalog = get_catalog(options)

  local function publish(snapshot)
    if session.cancelled or active_session ~= session then
      return
    end
    if options.on_state then
      options.on_state(snapshot)
    end
    if snapshot.status == "loading" or snapshot.status == "cancelled" then
      return
    end
    if not snapshot.models or #snapshot.models == 0 then
      if options.on_error then
        options.on_error(snapshot)
      end
      return
    end

    vim.ui.select(snapshot.models, {
      prompt = options.prompt or "Select model:",
      format_item = options.format_item or M.format_item,
    }, function(choice)
      if session.cancelled or active_session ~= session or not choice then
        return
      end
      M.apply_choice(choice, options)
      if options.on_done then
        options.on_done(choice)
      end
    end)
  end

  session.handle = active_catalog.refresh(publish)
  return {
    cancel = function()
      if session.cancelled then
        return
      end
      session.cancelled = true
      if session.handle and session.handle.cancel then
        session.handle.cancel()
      end
      if active_session == session then
        active_session = nil
      end
    end,
  }
end

--- Dispatch a :CoderModel command argument or open the menu.
---@param value string|nil
---@param options table|nil
---@return boolean, string|nil
function M.command(value, options)
  if value and value ~= "" then
    return M.select_argument(value, options)
  end
  M.open(options)
  return true, nil
end

return M
