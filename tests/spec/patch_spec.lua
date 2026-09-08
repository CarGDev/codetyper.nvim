--- Tests for patch creation + application against real scratch buffers.
--- Covers: "insert code at the correct line" and "delete/replace via a specific range".
--- No LLM/network — generated_code is a canned string, events are hand-built.

local patch = require("codetyper.core.diff.patch")

--- Helper: create a scratch buffer with given lines, set as a named file path
--- so patch.create_from_event can resolve target_bufnr via vim.fn.bufnr(path).
local function make_buffer(lines, path)
  local bufnr = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  if path then
    vim.api.nvim_buf_set_name(bufnr, path)
  end
  return bufnr
end

describe("patch.create_from_event + patch.apply — insert", function()
  it("inserts new code at the correct line without disturbing surrounding lines", function()
    local path = "/tmp/codetyper_test_insert_" .. os.time() .. ".lua"
    local bufnr = make_buffer({
      "local a = 1",
      "local b = 2",
      "local c = 3",
    }, path)

    local event = {
      id = "evt1",
      bufnr = bufnr,
      target_path = path,
      intent_override = { action = "insert" },
      range = { start_line = 2, end_line = 2 },
      injection_range = { start_line = 2, end_line = 2 },
    }

    local generated_code = "local injected = true"
    local p = patch.create_from_event(event, generated_code, 0.9)

    assert.are.equal("insert", p.injection_strategy)

    local ok = patch.apply(p)
    assert.is_true(ok)

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.are.same({
      "local a = 1",
      "local injected = true",
      "local b = 2",
      "local c = 3",
    }, lines)

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)

describe("patch.create_from_event + patch.apply — replace/delete via injection_range", function()
  it("deletes exactly one line when generated_code is empty and range targets that line", function()
    local path = "/tmp/codetyper_test_delete_" .. os.time() .. ".lua"
    local bufnr = make_buffer({
      "keep line 1",
      "delete this line",
      "keep line 2",
    }, path)

    local event = {
      id = "evt2",
      bufnr = bufnr,
      target_path = path,
      intent_override = { action = "replace" },
      range = { start_line = 2, end_line = 2 },
      injection_range = { start_line = 2, end_line = 2 },
    }

    local p = patch.create_from_event(event, "", 0.9)
    assert.are.equal("replace", p.injection_strategy)

    local ok = patch.apply(p)
    assert.is_true(ok)

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.are.same({ "keep line 1", "keep line 2" }, lines)

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("replaces a range of lines with newly generated code (mid-file injection)", function()
    local path = "/tmp/codetyper_test_replace_" .. os.time() .. ".lua"
    local bufnr = make_buffer({
      "-- header",
      "local old = 1",
      "local old2 = 2",
      "-- footer",
    }, path)

    local event = {
      id = "evt3",
      bufnr = bufnr,
      target_path = path,
      intent_override = { action = "replace" },
      range = { start_line = 2, end_line = 3 },
      injection_range = { start_line = 2, end_line = 3 },
    }

    local generated_code = "local newv = 42\nlocal another = 43"
    local p = patch.create_from_event(event, generated_code, 0.9)

    local ok = patch.apply(p)
    assert.is_true(ok)

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.are.same({
      "-- header",
      "local newv = 42",
      "local another = 43",
      "-- footer",
    }, lines)

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)

describe("patch.apply — SEARCH/REPLACE fallback (SR fails)", function()
  --- Helper: build a minimal patch table with a search_replace_blocks entry
  --- that will NOT match the buffer content, forcing search_replace.apply_to_buffer
  --- to fail and exercise the fallback path directly (bypassing create_from_event's
  --- block-parsing so the test controls exactly what fails and why).
  local function make_failing_sr_patch(bufnr, path, injection_range, replace_text)
    return {
      id = patch.generate_id(),
      event_id = nil,
      source_bufnr = bufnr,
      target_bufnr = bufnr,
      target_path = path,
      original_snapshot = patch.snapshot_buffer(bufnr),
      generated_code = "placeholder",
      injection_range = injection_range,
      injection_strategy = "search_replace",
      confidence = 0.9,
      status = "pending",
      created_at = os.time(),
      use_search_replace = true,
      search_replace_blocks = {
        { search = "THIS TEXT DOES NOT EXIST IN THE BUFFER", replace = replace_text },
      },
      is_inline_prompt = false,
    }
  end

  it("replaces only the lines within injection_range when SR fails and a range is present", function()
    local path = "/tmp/codetyper_test_sr_range_" .. os.time() .. ".lua"
    local bufnr = make_buffer({
      "-- header, must stay",
      "local old = 1",
      "local old2 = 2",
      "-- footer, must stay",
    }, path)

    local p = make_failing_sr_patch(bufnr, path, { start_line = 2, end_line = 3 }, "local fixed = 42")

    local ok, err = patch.apply(p)
    assert.is_true(ok)
    assert.is_nil(err)

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.are.same({
      "-- header, must stay",
      "local fixed = 42",
      "-- footer, must stay",
    }, lines)

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("fails loudly with no buffer mutation when SR fails and injection_range is nil", function()
    local path = "/tmp/codetyper_test_sr_norange_" .. os.time() .. ".lua"
    local original = {
      "-- header, must stay",
      "local old = 1",
      "local old2 = 2",
      "-- footer, must stay",
    }
    local bufnr = make_buffer(original, path)

    local p = make_failing_sr_patch(bufnr, path, nil, "local fixed = 42")

    local ok, err = patch.apply(p)
    assert.is_false(ok)
    assert.is_string(err)
    assert.is_truthy(err:match("injection range"))

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.are.same(original, lines)

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("returns 'nothing to inject' with no mutation when all REPLACE blocks are empty", function()
    local path = "/tmp/codetyper_test_sr_allempty_" .. os.time() .. ".lua"
    local original = {
      "-- header, must stay",
      "local old = 1",
      "local old2 = 2",
      "-- footer, must stay",
    }
    local bufnr = make_buffer(original, path)

    local p = make_failing_sr_patch(bufnr, path, { start_line = 2, end_line = 3 }, "")

    local ok, err = patch.apply(p)
    assert.is_false(ok)
    assert.is_string(err)
    assert.is_truthy(err:match("nothing to inject"))

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.are.same(original, lines)

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("uses only non-empty REPLACE content when blocks are a mix of empty and non-empty", function()
    local path = "/tmp/codetyper_test_sr_mixed_" .. os.time() .. ".lua"
    local bufnr = make_buffer({
      "-- header, must stay",
      "local old = 1",
      "local old2 = 2",
      "-- footer, must stay",
    }, path)

    local p = {
      id = patch.generate_id(),
      event_id = nil,
      source_bufnr = bufnr,
      target_bufnr = bufnr,
      target_path = path,
      original_snapshot = patch.snapshot_buffer(bufnr),
      generated_code = "placeholder",
      injection_range = { start_line = 2, end_line = 3 },
      injection_strategy = "search_replace",
      confidence = 0.9,
      status = "pending",
      created_at = os.time(),
      use_search_replace = true,
      search_replace_blocks = {
        { search = "NOT FOUND A", replace = "" },
        { search = "NOT FOUND B", replace = "local fixed = 42" },
      },
      is_inline_prompt = false,
    }

    local ok, err = patch.apply(p)
    assert.is_true(ok)
    assert.is_nil(err)

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.are.same({
      "-- header, must stay",
      "local fixed = 42",
      "-- footer, must stay",
    }, lines)

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)

describe("patch.queue_patch / get_pending", function()
  it("queues a patch and lists it as pending", function()
    local path = "/tmp/codetyper_test_queue_" .. os.time() .. ".lua"
    local bufnr = make_buffer({ "line 1" }, path)

    local event = {
      id = "evt4",
      bufnr = bufnr,
      target_path = path,
      intent = { action = "append" },
    }

    local p = patch.create_from_event(event, "-- appended", 0.8)
    patch.queue_patch(p)

    local pending = patch.get_pending()
    local found = false
    for _, item in ipairs(pending) do
      if item.id == p.id then
        found = true
      end
    end
    assert.is_true(found)

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)
