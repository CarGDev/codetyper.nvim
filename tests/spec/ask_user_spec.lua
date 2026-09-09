--- Tests for the safe selectable ask-user popup and serialized requests.

local ask_user = require("codetyper.window.ask_user")
local tools = require("codetyper.core.agent.tools")

local function feed(keys)
  local termcodes = vim.api.nvim_replace_termcodes(keys, true, false, true)
  vim.api.nvim_feedkeys(termcodes, "xt", false)
  vim.wait(50)
end

local function wait_for(predicate)
  vim.wait(200, predicate, 10)
  assert.is_true(predicate())
end

describe("ask-user popup", function()
  before_each(function()
    ask_user.reset()
  end)

  after_each(function()
    ask_user.reset()
  end)

  it("reports a clean availability result when floating windows are supported", function()
    local availability = ask_user.availability()

    assert.is_true(availability.available)
    assert.is_false(availability.stale)
    assert.is_nil(availability.error)
  end)

  it("reports an explicit error when floating windows are unavailable", function()
    local original_open_win = vim.api.nvim_open_win
    vim.api.nvim_open_win = nil
    local availability = ask_user.availability()
    vim.api.nvim_open_win = original_open_win

    assert.is_false(availability.available)
    assert.is_true(availability.stale)
    assert.are.equal("Neovim floating windows are unavailable", availability.error)
  end)

  it("opens a bounded selectable float and confirms the highlighted option", function()
    local calls = 0
    local result

    tools.dispatch("ask_user", {
      question = "Which transport should be used?",
      options = { "Local adapter", "Context7 fallback" },
    }, function(value)
      calls = calls + 1
      result = value
    end)

    local current = ask_user.state()
    assert.are.equal(1, current.queue_length)
    assert.is_true(vim.api.nvim_win_is_valid(current.win))
    assert.is_true(vim.api.nvim_buf_is_valid(current.buf))

    local config = vim.api.nvim_win_get_config(current.win)
    assert.are.equal("editor", config.relative)
    assert.is_true(config.width <= 80)
    assert.is_true(config.height <= 20)

    local lines = vim.api.nvim_buf_get_lines(current.buf, 0, -1, false)
    local rendered = table.concat(lines, "\n")
    assert.is_truthy(rendered:find("Which transport should be used?", 1, true))
    assert.is_truthy(rendered:find("1. Local adapter", 1, true))
    assert.is_truthy(rendered:find("2. Context7 fallback", 1, true))

    feed("<Down>")
    feed("<CR>")
    wait_for(function()
      return result ~= nil
    end)

    assert.are.equal(1, calls)
    assert.are.equal("selected", result.status)
    assert.are.equal(2, result.index)
    assert.are.equal("Context7 fallback", result.option)
    assert.are.same({ index = 2, option = "Context7 fallback" }, result.data)
    assert.is_false(result.stale)
    assert.is_nil(ask_user.state().active)
    assert.is_false(vim.api.nvim_win_is_valid(current.win))
  end)

  it("cancels with Escape and invokes the callback exactly once", function()
    local calls = 0
    local result

    tools.dispatch("ask_user", {
      question = "Continue with the safe operation?",
      options = { "Continue", "Stop" },
    }, function(value)
      calls = calls + 1
      result = value
    end)

    local current = ask_user.state()
    feed("<Esc>")
    wait_for(function()
      return result ~= nil
    end)

    assert.are.equal(1, calls)
    assert.are.equal("cancelled", result.status)
    assert.is_nil(result.data)
    assert.is_false(result.stale)
    assert.is_string(result.error)
    assert.are.equal(0, ask_user.state().queue_length)
    assert.is_false(vim.api.nvim_win_is_valid(current.win))

    feed("<Esc>")
    assert.are.equal(1, calls)
  end)

  it("serializes concurrent requests in FIFO order without overlapping floats", function()
    local results = {}

    local function collect(value)
      results[#results + 1] = value
    end

    tools.dispatch("ask_user", { question = "First question", options = { "first" } }, collect)
    tools.dispatch("ask_user", { question = "Second question", options = { "second" } }, collect)

    local first = ask_user.state()
    assert.are.equal(2, first.queue_length)
    assert.are.equal("First question", first.question)
    assert.is_true(vim.api.nvim_win_is_valid(first.win))

    feed("<CR>")
    wait_for(function()
      return #results == 1
    end)

    assert.are.equal("selected", results[1].status)
    assert.are.equal("first", results[1].option)
    local second = ask_user.state()
    assert.are.equal("Second question", second.question)
    assert.are.equal(1, second.queue_length)
    assert.is_true(vim.api.nvim_win_is_valid(second.win))
    assert.are_not.equal(first.win, second.win)

    feed("<CR>")
    wait_for(function()
      return #results == 2
    end)

    assert.are.equal("selected", results[2].status)
    assert.are.equal("second", results[2].option)
    assert.is_nil(ask_user.state().active)
    assert.are.equal(0, ask_user.state().queue_length)
  end)

  it("completes a request when its window is closed externally", function()
    local calls = 0
    local result

    tools.dispatch("ask_user", { question = "Close me", options = { "Only option" } }, function(value)
      calls = calls + 1
      result = value
    end)

    local current = ask_user.state()
    pcall(vim.api.nvim_win_close, current.win, true)
    wait_for(function()
      return result ~= nil
    end)

    assert.are.equal(1, calls)
    assert.are.equal("cancelled", result.status)
    assert.is_truthy(result.error:find("closed", 1, true))
    assert.is_nil(ask_user.state().active)

    pcall(vim.api.nvim_win_close, current.win, true)
    vim.wait(50)
    assert.are.equal(1, calls)
  end)

  it("cancels queued and active handles without duplicate callbacks", function()
    local first_result
    local second_result
    local first_handle = tools.dispatch("ask_user", { question = "Active", options = { "yes" } }, function(value)
      first_result = value
    end)
    local second_handle = tools.dispatch("ask_user", { question = "Queued", options = { "no" } }, function(value)
      second_result = value
    end)

    second_handle.cancel()
    assert.are.equal("cancelled", second_result.status)
    assert.are.equal(1, ask_user.state().queue_length)
    second_handle.cancel()
    assert.are.equal("cancelled", second_result.status)

    first_handle.cancel()
    assert.are.equal("cancelled", first_result.status)
    assert.are.equal(0, ask_user.state().queue_length)
    first_handle.cancel()
    assert.are.equal("cancelled", first_result.status)
  end)

  it("does not open a popup for invalid or empty input", function()
    local cases = {
      { question = "", options = { "one" } },
      { question = "valid", options = {} },
      { question = "valid", options = { "" } },
      { question = "valid", options = { "one", "two", "three", "four", "five", "six", "seven", "eight", "nine" } },
      { question = "valid", options = { "one\nunsafe" } },
    }

    for _, args in ipairs(cases) do
      local calls = 0
      local result
      tools.dispatch("ask_user", args, function(value)
        calls = calls + 1
        result = value
      end)

      assert.are.equal(1, calls)
      assert.are.equal("error", result.status)
      assert.is_nil(result.data)
      assert.is_false(result.stale)
      assert.is_string(result.error)
      assert.is_nil(ask_user.state().active)
      assert.are.equal(0, ask_user.state().queue_length)
    end
  end)

  it("supports an injectable UI without evaluating callback code", function()
    local request
    local result
    local calls = 0

    tools.dispatch("ask_user", { question = "Injected question", options = { "Safe" } }, function(value)
      calls = calls + 1
      result = value
    end, {
      ui = {
        open = function(value)
          request = value
          return {
            close = function() end,
          }
        end,
      },
    })

    assert.are.equal("Injected question", request.question)
    assert.are.same({ "Safe" }, request.options)
    request.on_select(1)
    request.on_select(1)

    assert.are.equal(1, calls)
    assert.are.equal("selected", result.status)
    assert.are.equal(1, result.index)
    assert.are.equal("Safe", result.option)
  end)
end)
