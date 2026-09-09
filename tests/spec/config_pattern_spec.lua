local injected = {}

local function save_module(name)
  if injected[name] == nil then
    injected[name] = {
      present = package.loaded[name] ~= nil,
      value = package.loaded[name],
    }
  end
end

local function clear_module(name)
  save_module(name)
  package.loaded[name] = nil
end

local function replace_module(name, value)
  save_module(name)
  package.loaded[name] = value
end

local function restore_modules()
  for name, previous in pairs(injected) do
    package.loaded[name] = previous.present and previous.value or nil
  end
  injected = {}
end

describe("provider configuration and companion paths", function()
  local original_anthropic_key

  before_each(function()
    original_anthropic_key = vim.env.ANTHROPIC_API_KEY
    vim.env.ANTHROPIC_API_KEY = nil
  end)

  after_each(function()
    vim.env.ANTHROPIC_API_KEY = original_anthropic_key
    restore_modules()
  end)

  it("provides typed provider defaults and validates setup choices", function()
    clear_module("codetyper.constants.defaults")
    local defaults = require("codetyper.constants.defaults")

    local config = defaults.setup({ llm = { provider = "claude" } })
    assert.are.equal("claude", config.llm.provider)
    assert.is_table(config.llm.ollama)
    assert.is_table(config.llm.copilot)
    assert.is_table(config.llm.claude)
    assert.is_table(config.llm.openai)
    assert.are.equal("*.codetyper.*", config.patterns.file_pattern)
    assert.are.equal("<leader>ctm", config.keymaps.model)
    assert.is_true(defaults.validate(config))

    assert.has_error(function()
      defaults.setup({ llm = { provider = "unsupported" } })
    end)
  end)

  it("accepts OpenAI ChatGPT subscription configuration without treating it as an API key", function()
    clear_module("codetyper.constants.defaults")
    local defaults = require("codetyper.constants.defaults")
    local config = defaults.setup({ llm = { provider = "openai", openai = { model = "gpt-5.5" } } })

    assert.are.equal("openai", config.llm.provider)
    assert.are.equal("gpt-5.5", config.llm.openai.model)
    assert.is_true(defaults.validate(config))
    assert.is_nil(config.llm.openai.api_key)
  end)

  it("recognizes only dotted codetyper companion files", function()
    clear_module("codetyper.support.utils")
    local utils = require("codetyper.support.utils")

    assert.is_true(utils.is_coder_file("src/index.codetyper.lua"))
    assert.is_true(utils.is_coder_file("src/index.codetyper.test.lua"))
    assert.is_false(utils.is_coder_file("src/index.coder.lua"))
    assert.is_false(utils.is_coder_file("src/index.codetyper/lua"))
    assert.is_false(utils.is_coder_file("src/.codetyper.lua"))

    assert.are.equal("src/index.lua", utils.get_target_path("src/index.codetyper.lua"))
    assert.are.equal("src/index.codetyper.lua", utils.get_coder_path("src/index.lua"))
    assert.are.equal("index.codetyper.lua", utils.get_coder_path("index.lua"))
  end)

  it("scrubs Anthropic secrets from legacy data and persisted payloads", function()
    local persisted
    local legacy_data = {
      version = 1,
      providers = {
        claude = {
          api_key = "legacy-anthropic-secret",
          model = "claude-sonnet-4-5",
        },
      },
    }
    local fake_utils = {
      ensure_dir = function()
        return true
      end,
      read_file = function()
        return vim.json.encode(legacy_data)
      end,
      write_file = function(_, content)
        persisted = content
        return true
      end,
    }
    replace_module("codetyper.support.utils", fake_utils)
    clear_module("codetyper.config.credentials")
    local credentials = require("codetyper.config.credentials")

    local loaded = credentials.load()
    assert.is_nil(loaded.providers.claude.api_key)
    assert.are.equal("claude-sonnet-4-5", loaded.providers.claude.model)

    vim.env.ANTHROPIC_API_KEY = "environment-anthropic-secret"
    assert.are.equal("environment-anthropic-secret", credentials.get_api_key("claude"))
    assert.is_true(credentials.set_credentials("claude", {
      api_key = "new-anthropic-secret",
      model = "claude-3-7-sonnet",
    }))

    assert.is_not_nil(persisted)
    assert.is_nil(vim.json.decode(persisted).providers.claude.api_key)
    assert.is_false(persisted:find("legacy-anthropic-secret", 1, true) ~= nil)
    assert.is_false(persisted:find("new-anthropic-secret", 1, true) ~= nil)
    assert.is_false(persisted:find("environment-anthropic-secret", 1, true) ~= nil)
  end)

  it("uses the canonical companion path when building context", function()
    local original_filereadable = vim.fn.filereadable
    local original_readfile = vim.fn.readfile
    local target_path = "src/index.lua"
    local companion_path = "src/index.codetyper.lua"

    vim.fn.filereadable = function(path)
      return path == companion_path and 1 or 0
    end
    vim.fn.readfile = function(path)
      if path == target_path then
        return { "return true" }
      end
      if path == companion_path then
        return { "Use the repository error convention." }
      end
      return {}
    end

    replace_module("codetyper.features.indexer", {
      get_context_for = function()
        return nil
      end,
    })
    replace_module("codetyper.core.memory", {
      is_initialized = function()
        return false
      end,
    })
    replace_module("codetyper.core.agent.architecture", {
      get_architecture_context = function()
        return ""
      end,
    })
    replace_module("codetyper.core.llm.shared.resolve_deps", {
      resolve = function()
        return {}
      end,
      format_context = function()
        return ""
      end,
    })
    clear_module("codetyper.core.llm.shared.build_context")

    local ok, context = pcall(function()
      return require("codetyper.core.llm.shared.build_context")({ target_path = target_path })
    end)

    vim.fn.filereadable = original_filereadable
    vim.fn.readfile = original_readfile

    assert.is_true(ok)
    assert.are.equal("\n\n--- Coder Context ---\nUse the repository error convention.", context.coder)
  end)

  it("does not derive another companion from an existing companion file", function()
    local original_filereadable = vim.fn.filereadable
    local original_readfile = vim.fn.readfile
    local target_path = "src/index.codetyper.lua"

    vim.fn.filereadable = function()
      return 1
    end
    vim.fn.readfile = function(path)
      if path == target_path then
        return { "-- companion content" }
      end
      return { "-- unexpected nested companion" }
    end

    replace_module("codetyper.features.indexer", {
      get_context_for = function()
        return nil
      end,
    })
    replace_module("codetyper.core.memory", {
      is_initialized = function()
        return false
      end,
    })
    replace_module("codetyper.core.agent.architecture", {
      get_architecture_context = function()
        return ""
      end,
    })
    replace_module("codetyper.core.llm.shared.resolve_deps", {
      resolve = function()
        return {}
      end,
      format_context = function()
        return ""
      end,
    })
    clear_module("codetyper.core.llm.shared.build_context")

    local ok, context = pcall(function()
      return require("codetyper.core.llm.shared.build_context")({ target_path = target_path })
    end)

    vim.fn.filereadable = original_filereadable
    vim.fn.readfile = original_readfile

    assert.is_true(ok)
    assert.are.equal("", context.coder)
  end)
end)
