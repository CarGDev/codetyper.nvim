--- Tests for the explain ("/@ ... @/" question intent) prompt/context building.
--- Mocks the LLM layer entirely (no network) and tests the pure
--- transform.build_explain_request extracted function directly, covering:
--- "explain all the file" and "explain a piece of code" (snippet / cursor scope).

describe("transform.is_explain_intent", function()
  local transform = require("codetyper.core.transform")

  it("detects question-mark input as explain intent", function()
    assert.is_true(transform.is_explain_intent("what does this do?"))
  end)

  it("detects question-word input as explain intent", function()
    assert.is_true(transform.is_explain_intent("explain this function"))
    assert.is_true(transform.is_explain_intent("how does this work"))
  end)

  it("treats imperative instructions as non-explain (transform) intent", function()
    assert.is_false(transform.is_explain_intent("add error handling"))
    assert.is_false(transform.is_explain_intent("refactor this to use pcall"))
  end)

  it("returns false for empty input", function()
    assert.is_false(transform.is_explain_intent("   "))
  end)
end)

describe("transform.build_explain_request", function()
  local transform = require("codetyper.core.transform")

  local function make_buffer(lines)
    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].filetype = "lua"
    return bufnr
  end

  it("explains the whole file when there is no selection and no cursor scope", function()
    local bufnr = make_buffer({
      "local function a() end",
      "local function b() end",
    })

    local built = transform.build_explain_request(bufnr, "/tmp/whole_file_test.lua", {
      input = "explain this file",
      has_selection = false,
      cursor_scope = nil,
    })

    assert.is_not_nil(built.context.source_code:find("local function a"))
    assert.is_not_nil(built.context.source_code:find("local function b"))
    assert.are.equal("ask", built.context.prompt_type)
    assert.is_nil(built.context.source_lines)
    assert.is_not_nil(built.prompt:find("explain this file"))

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("explains only the selected snippet when a selection is present", function()
    local bufnr = make_buffer({
      "local unrelated = 1",
      "local target_snippet = 2",
      "local also_unrelated = 3",
    })

    local built = transform.build_explain_request(bufnr, "/tmp/snippet_test.lua", {
      input = "what does this do?",
      has_selection = true,
      selection_text = "local target_snippet = 2",
      start_line = 2,
      end_line = 2,
    })

    assert.are.equal("local target_snippet = 2", built.context.source_code)
    assert.are.same({ 2, 2 }, built.context.source_lines)
    -- Whole-buffer content should NOT leak into the explained snippet
    assert.is_nil(built.context.source_code:find("unrelated"))

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("explains the enclosing function when cursor is inside a scope (no selection)", function()
    local bufnr = make_buffer({ "local function target() return 1 end" })

    local cursor_scope = {
      type = "function",
      name = "target",
      text = "local function target() return 1 end",
      range = { start_row = 1, end_row = 1 },
    }

    local built = transform.build_explain_request(bufnr, "/tmp/cursor_scope_test.lua", {
      input = "how does this work",
      has_selection = false,
      cursor_scope = cursor_scope,
    })

    assert.are.equal(cursor_scope.text, built.context.source_code)
    assert.are.equal("target", built.title)

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)

describe("explain flow — mocked LLM call (no network)", function()
  it("calls the mocked llm.generate with the built prompt/context and surfaces the response", function()
    -- Stub the LLM module before it's required by transform.lua's caller.
    local captured = {}
    package.loaded["codetyper.core.llm"] = {
      generate = function(prompt, context, callback)
        captured.prompt = prompt
        captured.context = context
        callback("This is a canned explanation.", nil)
      end,
    }

    local shown = {}
    package.loaded["codetyper.window.explain"] = {
      show = function(title, content, filetype, context)
        shown.show_title = title
      end,
      update = function(content)
        shown.update_content = content
      end,
    }

    -- Re-require transform fresh so it's the same module (functions are
    -- looked up via require() at call-time inside cmd_transform_selection,
    -- so stubbing package.loaded above is sufficient without reloading).
    local transform = require("codetyper.core.transform")

    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "local function f() end" })
    vim.bo[bufnr].filetype = "lua"

    local built = transform.build_explain_request(bufnr, "/tmp/mocked_explain.lua", {
      input = "explain this",
      has_selection = false,
      cursor_scope = nil,
    })

    -- Simulate what cmd_transform_selection does after building the request
    local llm = require("codetyper.core.llm")
    local explain_window = require("codetyper.window.explain")
    explain_window.show("Thinking...", "Loading explanation...", "lua", built.context)
    llm.generate(built.prompt, built.context, function(response, err)
      explain_window.update("# " .. built.title .. "\n\n" .. response)
    end)

    assert.are.equal("Thinking...", shown.show_title)
    assert.is_not_nil(captured.prompt)
    assert.is_not_nil(shown.update_content:find("This is a canned explanation."))

    vim.api.nvim_buf_delete(bufnr, { force = true })

    -- Clean up stubs so other spec files get the real modules
    package.loaded["codetyper.core.llm"] = nil
    package.loaded["codetyper.window.explain"] = nil
  end)
end)
