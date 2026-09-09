local injected = {}

local function replace_module(name, value)
  if injected[name] == nil then
    injected[name] = { present = package.loaded[name] ~= nil, value = package.loaded[name] }
  end
  package.loaded[name] = value
end

local function clear_module(name)
  replace_module(name, nil)
end

local function restore_modules()
  for name, previous in pairs(injected) do
    package.loaded[name] = previous.present and previous.value or nil
  end
  injected = {}
end

local function load_resolver(auth, config, credentials)
  replace_module("codetyper.core.llm.providers.copilot.auth", auth)
  replace_module("codetyper.support.flog", {
    info = function() end,
    warn = function() end,
    error = function() end,
    debug = function() end,
  })
  replace_module("codetyper", config and { get_config = function() return config end } or nil)
  replace_module("codetyper.config.credentials", credentials or {
    get_active_provider = function() return nil end,
  })
  clear_module("codetyper.core.llm.provider_resolver")
  return require("codetyper.core.llm.provider_resolver")
end

local function load_selector_select(provider_resolver)
  replace_module("codetyper.core.llm.provider_resolver", provider_resolver)
  replace_module("codetyper.core.llm.selector.accuracy", {
    load = function() end,
    get_ollama_confidence = function() return 0 end,
  })
  replace_module("codetyper.core.memory", {
    is_initialized = function() return false end,
  })
  clear_module("codetyper.core.llm.selector.select")
  return require("codetyper.core.llm.selector.select")
end

describe("provider routing", function()
  local original_jobstart

  before_each(function()
    injected = {}
    original_jobstart = vim.fn.jobstart
  end)

  after_each(function()
    vim.fn.jobstart = original_jobstart
    restore_modules()
  end)

  it("routes explicit Claude and Copilot choices without consulting fallback", function()
    local auth_checks = 0
    local resolver = load_resolver({
      is_valid = function(callback)
        auth_checks = auth_checks + 1
        callback(false)
      end,
    }, {
      llm = { ollama = { host = "http://ollama.test" } },
    })

    local claude, claude_error
    resolver.resolve(function(provider, err)
      claude, claude_error = provider, err
    end, "claude")
    assert.are.equal("claude", claude)
    assert.is_nil(claude_error)

    local copilot = resolver.resolve_sync("copilot")
    assert.are.equal("copilot", copilot)
    assert.are.equal(0, auth_checks)
  end)

  it("routes an explicit OpenAI subscription choice without consulting Copilot or Ollama", function()
    local auth_checks = 0
    local resolver = load_resolver({
      is_valid = function()
        auth_checks = auth_checks + 1
        return false
      end,
    }, {
      llm = { ollama = { host = "http://ollama.test" } },
    })

    local selected, selection_error
    resolver.resolve(function(provider, err)
      selected, selection_error = provider, err
    end, "openai")

    assert.are.equal("openai", selected)
    assert.is_nil(selection_error)
    assert.are.equal(0, auth_checks)
  end)

  it("prefers authenticated Copilot and falls back to reachable Ollama", function()
    local jobstarts = 0
    vim.fn.jobstart = function(_, opts)
      jobstarts = jobstarts + 1
      opts.on_stdout(1, { "200" })
      return 1
    end

    local resolver = load_resolver({
      is_valid = function(callback)
        callback(false)
      end,
    }, {
      llm = { ollama = { host = "http://ollama.test" } },
    })

    local fallback_provider, fallback_error
    resolver.resolve(function(provider, err)
      fallback_provider, fallback_error = provider, err
    end)
    assert.are.equal("ollama", fallback_provider)
    assert.is_nil(fallback_error)
    assert.are.equal(1, jobstarts)

    local authenticated_resolver = load_resolver({
      is_valid = function(callback)
        callback(true)
      end,
    }, {
      llm = { ollama = { host = "http://ollama.test" } },
    })
    local primary_provider, primary_error
    authenticated_resolver.resolve(function(provider, err)
      primary_provider, primary_error = provider, err
    end)
    assert.are.equal("copilot", primary_provider)
    assert.is_nil(primary_error)
    assert.are.equal(1, jobstarts)
  end)

  it("exposes explicit Claude and Copilot clients through the LLM facade", function()
    local claude = { name = "claude-client" }
    local copilot = { name = "copilot-client" }
    local openai = { name = "openai-client" }
    replace_module("codetyper.core.llm.providers.claude", claude)
    replace_module("codetyper.core.llm.providers.copilot", copilot)
    replace_module("codetyper.core.llm.providers.openai", openai)
    replace_module("codetyper.core.llm.provider_resolver", {
      resolve_sync = function() return "copilot" end,
    })
    clear_module("codetyper.core.llm")

    local llm = require("codetyper.core.llm")
    assert.are.equal(claude, llm.get_client("claude"))
    assert.are.equal(copilot, llm.get_client("copilot"))
    assert.are.equal(openai, llm.get_client("openai"))
  end)

  it("keeps an explicit OpenAI selector choice instead of replacing it with fallback", function()
    local selector = load_selector_select({
      resolve_sync = function()
        error("implicit provider resolution must not run for explicit choices")
      end,
      validate_provider = function(provider)
        return provider == "openai", provider == "openai" and nil or "unsupported"
      end,
    })

    local selection = selector("use ChatGPT subscription", {
      provider = "openai",
      model = "gpt-5.5",
    })
    assert.are.equal("openai", selection.provider)
    assert.is_true(selection.explicit)
    assert.matches("Explicit", selection.reason)
  end)

  it("keeps an explicit selector provider instead of replacing it with the fallback", function()
    local selector = load_selector_select({
      resolve_sync = function()
        error("implicit provider resolution must not run for explicit choices")
      end,
      validate_provider = function(provider)
        return provider == "claude", provider == "claude" and nil or "unsupported"
      end,
    })

    local selection = selector("write a function", {
      provider = "claude",
      file_path = "init.lua",
    })
    assert.are.equal("claude", selection.provider)
    assert.is_true(selection.explicit)
    assert.matches("Explicit", selection.reason)
  end)

  it("marks a persisted explicit Ollama choice so generation cannot escalate away", function()
    local selector = load_selector_select({
      get_explicit_provider = function()
        return "ollama"
      end,
      resolve_sync = function()
        return "ollama"
      end,
      validate_provider = function(provider)
        return provider == "ollama", provider == "ollama" and nil or "unsupported"
      end,
    })

    local selection = selector("write a function", { file_path = "init.lua" })
    assert.are.equal("ollama", selection.provider)
    assert.is_true(selection.explicit)
    assert.are.equal("Explicit provider: ollama", selection.reason)
  end)

  it("uses the selected provider in smart generation and does not silently switch it", function()
    local claude_calls, copilot_calls = 0, 0
    replace_module("codetyper.core.llm.selector.select", function()
      return {
        provider = "claude",
        explicit = true,
        confidence = 1,
        memory_count = 0,
        reason = "Explicit provider: claude",
      }
    end)
    replace_module("codetyper.core.llm.selector.ponder", {
      should_ponder = function() return false end,
      ponder = function() error("explicit provider must not be pondered") end,
    })
    replace_module("codetyper.core.llm.selector.accuracy", {
      get_stats = function() return {} end,
      reset = function() end,
      record = function() end,
    })
    replace_module("codetyper.support.flog", {
      info = function() end,
      warn = function() end,
      error = function() end,
      debug = function() end,
    })
    replace_module("codetyper.core.llm.providers.claude", {
      generate = function(_, _, callback)
        claude_calls = claude_calls + 1
        callback("claude response", nil)
      end,
    })
    replace_module("codetyper.core.llm.providers.copilot", {
      generate = function()
        copilot_calls = copilot_calls + 1
        error("Copilot must not replace explicit Claude")
      end,
    })
    clear_module("codetyper.core.llm.selector")

    local selector = require("codetyper.core.llm.selector")
    local response, response_error, metadata
    selector.smart_generate("prompt", { provider = "claude" }, function(text, err, result)
      response, response_error, metadata = text, err, result
    end)

    assert.are.equal("claude response", response)
    assert.is_nil(response_error)
    assert.are.equal("claude", metadata.provider)
    assert.are.equal(1, claude_calls)
    assert.are.equal(0, copilot_calls)
  end)

  it("preserves explicit provider intent from queue through scheduler and worker seams", function()
    local queue = require("codetyper.core.events.queue")
    queue.clear()
    local event = queue.enqueue({
      provider = "claude",
      worker_type = "copilot",
      prompt_content = "use the selected provider",
      priority = 1,
    })
    local dequeued = queue.dequeue()
    assert.are.equal(event.id, dequeued.id)
    assert.are.equal("claude", dequeued.provider)

    replace_module("codetyper.core.events.queue", {})
    replace_module("codetyper.core.diff.patch", {})
    replace_module("codetyper.core.scheduler.worker", {})
    replace_module("codetyper.core.llm.confidence", {})
    replace_module("codetyper.adapters.nvim.ui.context_modal.setup", function() end)
    replace_module("codetyper.adapters.nvim.ui.context_modal.open", function() end)
    replace_module("codetyper.support.logger", {})
    replace_module("codetyper.support.flog", {
      info = function() end,
      warn = function() end,
      error = function() end,
      debug = function() end,
    })
    replace_module("codetyper.state.state", {
      config = { max_concurrent = 1 },
      paused = false,
      running = false,
    })
    clear_module("codetyper.core.scheduler.scheduler")
    local scheduler = require("codetyper.core.scheduler.scheduler")
    assert.are.equal("claude", scheduler.resolve_event_provider(dequeued))

    clear_module("codetyper.core.scheduler.worker")
    local worker = require("codetyper.core.scheduler.worker")
    assert.are.equal("claude", worker.resolve_provider(dequeued))
  end)

  it("uses native dispatch for capable Copilot selection and marker fallback otherwise", function()
    local function load_smart_selector(selection, client)
      replace_module("codetyper.core.llm.selector.select", function()
        return selection
      end)
      replace_module("codetyper.core.llm.selector.ponder", {
        should_ponder = function() return false end,
        ponder = function() error("native tool routing must not ponder") end,
      })
      replace_module("codetyper.core.llm.selector.accuracy", {
        get_stats = function() return {} end,
        reset = function() end,
        record = function() end,
      })
      replace_module("codetyper.core.llm", {
        get_client = function(provider)
          assert.are.equal(selection.provider, provider)
          return client
        end,
      })
      replace_module("codetyper.support.flog", {
        info = function() end,
        warn = function() end,
        error = function() end,
        debug = function() end,
      })
      clear_module("codetyper.core.llm.selector")
      return require("codetyper.core.llm.selector")
    end

    local native_calls, marker_calls = 0, 0
    local native_selector = load_smart_selector({
      provider = "copilot",
      explicit = true,
      confidence = 1,
      memory_count = 0,
      reason = "native capability test",
    }, {
      generate_structured = function(_, context, callbacks)
        native_calls = native_calls + 1
        assert.is_true(context.tool_capabilities.native_tools)
        callbacks.on_complete({ text = "native response", tool_calls = {}, usage = {} })
      end,
      generate = function()
        marker_calls = marker_calls + 1
        error("capable Copilot must use structured dispatch")
      end,
    })

    local native_response, native_error, native_metadata
    native_selector.smart_generate("prompt", {
      provider = "copilot",
      is_project_task = true,
      tool_capabilities = { native_tools = true, marker_tools = true },
    }, function(response, err, metadata)
      native_response, native_error, native_metadata = response, err, metadata
    end)

    assert.are.equal("native response", native_response)
    assert.is_nil(native_error)
    assert.are.equal("native", native_metadata.tool_mode)
    assert.are.equal(1, native_calls)
    assert.are.equal(0, marker_calls)

    local marker_selector = load_smart_selector({
      provider = "copilot",
      explicit = true,
      confidence = 1,
      memory_count = 0,
      reason = "marker capability test",
    }, {
      generate_structured = function()
        error("marker fallback must not use structured dispatch")
      end,
      generate = function(_, context, callback)
        marker_calls = marker_calls + 1
        assert.is_false(context.tool_capabilities.native_tools)
        assert.is_true(context.tool_capabilities.marker_tools)
        callback("marker response", nil)
      end,
    })

    local marker_response, marker_error, marker_metadata
    marker_selector.smart_generate("prompt", {
      provider = "copilot",
      is_project_task = true,
      tool_capabilities = { native_tools = false, marker_tools = true },
    }, function(response, err, metadata)
      marker_response, marker_error, marker_metadata = response, err, metadata
    end)

    assert.are.equal("marker response", marker_response)
    assert.is_nil(marker_error)
    assert.are.equal("marker", marker_metadata.tool_mode)
    assert.are.equal(1, marker_calls)
  end)
end)
