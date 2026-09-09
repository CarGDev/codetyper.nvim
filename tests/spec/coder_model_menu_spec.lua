local injected = {}

local function clear_module(name)
  if injected[name] == nil then
    injected[name] = { present = package.loaded[name] ~= nil, value = package.loaded[name] }
  end
  package.loaded[name] = nil
end

local function restore_modules()
  for name, previous in pairs(injected) do
    package.loaded[name] = previous.present and previous.value or nil
  end
  injected = {}
end

local function model(id, provider, name)
  return {
    id = id,
    name = name or id,
    provider = provider,
    capabilities = { streaming = false },
  }
end

describe("Coder model menu", function()
  local original_select
  local original_keymap_set
  local original_create_user_command

  before_each(function()
    injected = {}
    original_select = vim.ui.select
    original_keymap_set = vim.keymap.set
    original_create_user_command = vim.api.nvim_create_user_command
    clear_module("codetyper.adapters.nvim.ui.model_menu")
    clear_module("codetyper.adapters.nvim.commands.setup_keymaps")
    clear_module("codetyper.adapters.nvim.commands.setup")
  end)

  after_each(function()
    vim.ui.select = original_select
    vim.keymap.set = original_keymap_set
    vim.api.nvim_create_user_command = original_create_user_command
    restore_modules()
  end)

  it("labels every provider and exposes provider-qualified completion", function()
    local models = {
      model("claude-sonnet-4-5", "claude", "Claude Sonnet 4.5"),
      model("gpt-4o", "copilot"),
      model("gpt-5.5", "openai", "GPT-5.5"),
      model("llama3:8b", "ollama"),
    }
    local select_options
    vim.ui.select = function(_, options)
      select_options = options
    end

    local menu = require("codetyper.adapters.nvim.ui.model_menu")
    menu.open({
      catalog = {
        snapshot = function()
          return { status = "ready", models = models }
        end,
        refresh = function(callback)
          callback({ status = "ready", models = models })
          return { cancel = function() end }
        end,
      },
      credentials = { set_credentials = function() end, set_active_provider = function() end },
    })

    assert.matches("Anthropic", select_options.format_item(models[1]))
    assert.matches("GitHub Copilot", select_options.format_item(models[2]))
    assert.matches("OpenAI %(ChatGPT Plus/Pro%)", select_options.format_item(models[3]))
    assert.matches("Ollama", select_options.format_item(models[4]))
    assert.same({ "claude/claude-sonnet-4-5" }, menu.complete("claude/"))
    assert.same({ "openai/gpt-5.5" }, menu.complete("openai/"))
    assert.same({ "ollama/llama3:8b" }, menu.complete("llama3"))
  end)

  it("cancels an in-flight refresh and does not mutate on refresh or menu cancellation", function()
    local refresh_callback
    local cancelled = false
    local selected = 0
    local saved = 0
    vim.ui.select = function(_, _, callback)
      selected = selected + 1
      callback(nil)
    end

    local menu = require("codetyper.adapters.nvim.ui.model_menu")
    local handle = menu.open({
      catalog = {
        snapshot = function()
          return { status = "loading", models = {} }
        end,
        refresh = function(callback)
          refresh_callback = callback
          return {
            cancel = function()
              cancelled = true
            end,
          }
        end,
      },
      credentials = {
        set_credentials = function()
          saved = saved + 1
        end,
        set_active_provider = function()
          saved = saved + 1
        end,
      },
    })

    handle.cancel()
    refresh_callback({ status = "ready", models = { model("late", "claude") } })
    assert.is_true(cancelled)
    assert.are.equal(0, selected)
    assert.are.equal(0, saved)

    local ready_catalog = {
      snapshot = function()
        return { status = "ready", models = { model("cancelled", "copilot") } }
      end,
      refresh = function(callback)
        callback({ status = "ready", models = { model("cancelled", "copilot") } })
        return { cancel = function() end }
      end,
    }
    menu.open({
      catalog = ready_catalog,
      credentials = {
        set_credentials = function()
          saved = saved + 1
        end,
        set_active_provider = function()
          saved = saved + 1
        end,
      },
    })
    assert.are.equal(1, selected)
    assert.are.equal(0, saved)
  end)

  it("registers provider-backed command completion and stores the selected provider", function()
    local models = { model("claude-3-7-sonnet", "claude", "Claude 3.7 Sonnet") }
    local commands = {}
    local selected_provider, selected_model
    vim.api.nvim_create_user_command = function(name, callback, options)
      commands[name] = { callback = callback, options = options }
    end
    vim.ui.select = function(items, _, callback)
      callback(items[1])
    end

    local menu = require("codetyper.adapters.nvim.ui.model_menu")
    menu.open({
      catalog = {
        snapshot = function()
          return { status = "ready", models = models }
        end,
        refresh = function(callback)
          callback({ status = "ready", models = models })
          return { cancel = function() end }
        end,
      },
      credentials = {
        set_credentials = function(provider, values)
          selected_provider, selected_model = provider, values.model
        end,
        set_active_provider = function(provider)
          selected_provider = provider
        end,
      },
    })

    clear_module("codetyper.config.credentials")
    package.loaded["codetyper.config.credentials"] = {
      set_credentials = function(provider, values)
        selected_provider, selected_model = provider, values.model
      end,
      set_active_provider = function(provider)
        selected_provider = provider
      end,
    }
    require("codetyper.adapters.nvim.commands.setup")()
    assert.same({ "claude/claude-3-7-sonnet" }, commands.Coder.options.complete("", "Coder model ", 0))
    assert.is_not_nil(commands.CoderModel)
    assert.same({ "claude/claude-3-7-sonnet" }, commands.CoderModel.options.complete(""))
    commands.CoderModel.callback({ args = "claude/claude-3-7-sonnet" })
    assert.are.equal("claude", selected_provider)
    assert.are.equal("claude-3-7-sonnet", selected_model)
  end)

  it("keeps default mappings configurable and disables only false entries", function()
    local mappings = {}
    vim.keymap.set = function(mode, lhs, rhs, options)
      mappings[lhs] = { mode = mode, rhs = rhs, options = options }
    end

    local setup_keymaps = require("codetyper.adapters.nvim.commands.setup_keymaps")
    setup_keymaps({})
    assert.is_not_nil(mappings["<leader>ctm"])
    assert.is_not_nil(mappings["<leader>ctt"])

    mappings = {}
    setup_keymaps({ keymaps = { model = "<leader>custom", terminal = false } })
    assert.is_not_nil(mappings["<leader>custom"])
    assert.is_nil(mappings["<leader>ctm"])
    assert.is_nil(mappings["<leader>ter"])
    assert.is_not_nil(mappings["<leader>ctt"])
  end)
end)
