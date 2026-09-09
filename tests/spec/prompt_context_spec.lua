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

describe("agent prompt capabilities", function()
  before_each(function()
    saved_modules = {}
    install("codetyper.support.flog", {
      info = function() end,
      warn = function() end,
      error = function() end,
      debug = function() end,
    })
  end)

  after_each(restore)

  it("describes only explicitly available tools without querying or exposing secrets", function()
    local mcp_prompt_calls = 0
    install("codetyper.core.agent.mcp", {
      get_tools_for_prompt = function()
        mcp_prompt_calls = mcp_prompt_calls + 1
        error("prompt construction must not query MCP tools")
      end,
    })

    local agent = require("codetyper.prompts.tiers.agent")
    local user_prompt, system_prompt = agent.build_prompt({
      target_path = "src/main.lua",
      prompt_content = "use the available project context",
    }, {
      target_content = "return 1",
      filetype = "lua",
      extra = "",
      tool_capabilities = {
        provider = "copilot",
        native_tools = true,
        marker_tools = true,
        limits = { max_result_chars = 4000 },
        available_tools = {
          {
            name = "codegraph_context",
            marker = "TOOL:CODEGRAPH",
            status = "available",
            description = "Read bounded local project context.",
          },
        },
        redacted_note = "token-secret-must-not-appear",
      },
    })

    assert.matches("use the available project context", user_prompt)
    assert.matches("codegraph_context", system_prompt)
    assert.matches("TOOL:CODEGRAPH", system_prompt)
    assert.matches("4000", system_prompt)
    assert.matches("native", system_prompt:lower())
    assert.is_nil(system_prompt:find("token%-secret"))
    assert.is_nil(system_prompt:find("tokensave_search", 1, true))
    assert.are.equal(0, mcp_prompt_calls)
  end)

  it("keeps the existing agent prompt unchanged when no new tools are available", function()
    local agent = require("codetyper.prompts.tiers.agent")
    local _, system_prompt = agent.build_prompt({
      target_path = "src/main.lua",
      prompt_content = "make the change",
    }, {
      target_content = "return 1",
      filetype = "lua",
      extra = "",
      tool_capabilities = {
        provider = "ollama",
        native_tools = false,
        marker_tools = false,
        available_tools = {},
      },
    })

    assert.is_nil(system_prompt:find("CAPABILITY%-BOUND TOOLS"))
    assert.matches("TOOL:TERMINAL", system_prompt)
  end)
end)
