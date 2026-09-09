local MODULES = {
  "codetyper.core.llm.providers.copilot",
  "codetyper.core.llm.providers.copilot.auth",
  "codetyper.core.llm.providers.copilot.request",
  "codetyper.core.llm.providers.copilot.response",
  "codetyper.core.llm.providers.copilot.stream",
  "codetyper.constants.model_caps",
  "codetyper.core.agent.tools",
  "codetyper.core.agent.mcp",
  "codetyper.config.credentials",
  "codetyper.support.flog",
  "codetyper.support.utils",
  "codetyper",
}

local saved_modules = {}

local function install(name, value)
  if saved_modules[name] == nil then
    saved_modules[name] = package.loaded[name]
  end
  package.loaded[name] = value
end

local function restore()
  for name, value in pairs(saved_modules) do
    package.loaded[name] = value
  end
  saved_modules = {}
end

local function load_copilot(registry, model_supports_tools)
  install("codetyper.core.llm.providers.copilot.auth", {
    get_valid_token = function(callback)
      callback({ token = "test-token", endpoints = { api = "https://copilot.test" } }, nil)
    end,
    validate_exchange = function()
      return true
    end,
    safe_error = function(value)
      return tostring(value)
    end,
  })
  local captured = {}
  install("codetyper.core.llm.providers.copilot.request", {
    terminal_tool = {
      type = "function",
      ["function"] = { name = "terminal" },
    },
    build_body = function(model, system_prompt, prompt, options)
      captured.model = model
      captured.system_prompt = system_prompt
      captured.prompt = prompt
      captured.options = options
      return options
    end,
    send_stream = function()
      return 1
    end,
  })
  install("codetyper.core.llm.providers.copilot.response", function()
    return { code = "", usage = {} }
  end)
  install("codetyper.core.llm.providers.copilot.stream", {
    new = function()
      return {}
    end,
    process_chunk = function()
      return {}
    end,
    get_result = function()
      return { text = "", tool_calls = {} }
    end,
  })
  install("codetyper.constants.model_caps", {
    get = function()
      return { tools = model_supports_tools }
    end,
  })
  install("codetyper.core.agent.tools", registry)
  install("codetyper.core.agent.mcp", {
    get_tools_for_api = function()
      return {
        { type = "function", ["function"] = { name = "remote__lookup" } },
      }
    end,
  })
  install("codetyper.config.credentials", {
    get_model = function()
      return "test-model"
    end,
  })
  install("codetyper.support.flog", {
    info = function() end,
    warn = function() end,
    error = function() end,
    debug = function() end,
  })
  install("codetyper.support.utils", {
    notify = function() end,
  })
  install("codetyper", {
    get_config = function()
      return { llm = { copilot = { model = "test-model" } } }
    end,
  })
  package.loaded["codetyper.core.llm.providers.copilot"] = nil
  local client = require("codetyper.core.llm.providers.copilot")
  return client, captured
end

describe("provider tool capabilities", function()
  before_each(function()
    saved_modules = {}
  end)

  after_each(function()
    for _, name in ipairs(MODULES) do
      package.loaded[name] = nil
    end
    restore()
  end)

  it("sends only available registry schemas to eligible Copilot project tasks", function()
    local client, captured = load_copilot({
      list = function()
        return {
          {
            name = "codegraph_context",
            type = "function",
            available = true,
            stale = false,
            parameters = { type = "object", properties = { query = { type = "string" } } },
          },
          {
            name = "add_import",
            type = "function",
            available = false,
            stale = true,
            parameters = { type = "object", properties = {} },
          },
        }
      end,
    }, true)

    client.generate_structured("request", {
      system_prompt = "system",
      is_project_task = true,
    }, {
      on_text_delta = function() end,
      on_complete = function() end,
      on_error = function(error)
        error(error)
      end,
    })

    local names = {}
    for _, tool in ipairs(captured.options.tools or {}) do
      names[#names + 1] = tool["function"] and tool["function"].name
    end
    assert.is_true(vim.tbl_contains(names, "codegraph_context"))
    assert.is_true(vim.tbl_contains(names, "terminal"))
    assert.is_true(vim.tbl_contains(names, "remote__lookup"))
    assert.is_false(vim.tbl_contains(names, "add_import"))
  end)

  it("omits native schemas for non-project or unsupported Copilot model contexts", function()
    local registry = {
      list = function()
        return {
          { name = "codegraph_context", type = "function", available = true, parameters = {} },
        }
      end,
    }

    local client, project_captured = load_copilot(registry, false)
    client.generate_structured("request", {
      system_prompt = "system",
      is_project_task = true,
    }, {
      on_text_delta = function() end,
      on_complete = function() end,
      on_error = function() end,
    })
    assert.is_nil(project_captured.options.tools)

    restore()
    local non_project_client, non_project_captured = load_copilot(registry, true)
    non_project_client.generate_structured("request", {
      system_prompt = "system",
      is_project_task = false,
    }, {
      on_text_delta = function() end,
      on_complete = function() end,
      on_error = function() end,
    })
    assert.is_nil(non_project_captured.options.tools)
  end)

  it("marks native schemas unavailable when a non-Copilot provider is selected", function()
    local client = load_copilot({
      list = function()
        return {
          { name = "codegraph_context", type = "function", available = true, parameters = {} },
        }
      end,
    }, true)

    for _, provider in ipairs({ "claude", "openai", "ollama" }) do
      local capabilities = client.get_tool_capabilities({
        provider = provider,
        is_project_task = true,
      })
      assert.is_false(capabilities.native_tools)
      assert.are.same({}, capabilities.tools)
      assert.is_true(capabilities.marker_tools)
    end
  end)

  it("does not probe or expose native tools for unsupported providers", function()
    local list_calls, mcp_calls = 0, 0
    local client = load_copilot({
      list = function()
        list_calls = list_calls + 1
        error("unsupported providers must not list native tools")
      end,
    }, true)

    package.loaded["codetyper.core.agent.mcp"] = {
      get_tools_for_api = function()
        mcp_calls = mcp_calls + 1
        error("unsupported providers must not list MCP tools")
      end,
    }

    for _, provider in ipairs({ "claude", "openai", "ollama" }) do
      local capabilities = client.get_tool_capabilities({
        provider = provider,
        is_project_task = true,
      })

      assert.are.same({}, capabilities.tools)
      assert.is_false(capabilities.native_tools)
      assert.is_true(capabilities.marker_tools)
    end

    assert.are.equal(0, list_calls)
    assert.are.equal(0, mcp_calls)
  end)
end)
