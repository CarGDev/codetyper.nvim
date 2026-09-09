local http = require("codetyper.core.llm.shared.http")

describe("shared HTTP boundary", function()
  local original_jobstart, original_jobstop, jobs, stopped

  before_each(function()
    original_jobstart, original_jobstop = vim.fn.jobstart, vim.fn.jobstop
    jobs, stopped = {}, nil
    vim.fn.jobstart = function(argv, opts)
      jobs[#jobs + 1] = { argv = argv, opts = opts }
      return #jobs
    end
    vim.fn.jobstop = function(job_id)
      stopped = job_id
    end
  end)

  after_each(function()
    vim.fn.jobstart, vim.fn.jobstop = original_jobstart, original_jobstop
  end)
  local function respond(index, body, status)
    jobs[index].opts.on_stdout(index, { body .. "\n__CODETYPER_STATUS__" .. status })
    jobs[index].opts.on_exit(index, 0)
  end

  it("uses argv-only curl, parses status and redacts diagnostics", function()
    local result, err, meta
    http.get(
      "https://example.test/models",
      { "Authorization: Bearer fake-token" },
      function(data, request_err, response_meta)
        result, err, meta = data, request_err, response_meta
      end
    )
    assert.are.equal("curl", jobs[1].argv[1])
    assert.is_false(vim.tbl_contains(jobs[1].argv, "-c"))
    assert.is_true(vim.tbl_contains(jobs[1].argv, "--write-out"))
    respond(1, '{"models":[]}', 200)
    assert.same({ models = {} }, result)
    assert.is_nil(err)
    assert.are.equal(200, meta.status)
    assert.are.equal("Authorization: Bearer [REDACTED]", http.redact("Authorization: Bearer fake-token"))
  end)

  it("reports status/JSON errors and never calls a network in the spec", function()
    local status_error, status_meta
    http.get("https://example.test/models", {}, function(_, request_err, response_meta)
      status_error, status_meta = request_err, response_meta
    end)
    respond(1, '{"message":"unavailable"}', 503)
    assert.are.equal("unavailable", status_error)
    assert.are.equal(503, status_meta.status)
    local json_error
    http.get("https://example.test/models", {}, function(_, request_err)
      json_error = request_err
    end)
    respond(2, "not-json", 200)
    assert.matches("Invalid JSON", json_error)
  end)

  it("cleans POST temp bodies and cancellation suppresses callbacks", function()
    local path, called = nil, false
    local handle = http.post("https://example.test/generate", {}, '{"prompt":"safe"}', function()
      called = true
    end)
    for index, value in ipairs(jobs[1].argv) do
      if value == "--data-binary" then
        path = jobs[1].argv[index + 1]:sub(2)
      end
    end
    assert.are.equal(1, vim.fn.filereadable(path))
    respond(1, "{}", 200)
    assert.are.equal(0, vim.fn.filereadable(path))
    assert.is_true(called)
    called = false
    local cancelled = http.get("https://example.test/slow", {}, function()
      called = true
    end)
    cancelled.cancel()
    respond(2, "{}", 200)
    assert.are.equal(2, stopped)
    assert.is_false(called)
  end)

  it("removes a secret-bearing POST body when cancelled before completion", function()
    local secret = "http-boundary-secret"
    local path, called = nil, false
    local handle = http.post(
      "https://example.test/slow",
      { "Authorization: Bearer " .. secret },
      '{"token":"' .. secret .. '"}',
      function()
        called = true
      end
    )

    for index, value in ipairs(jobs[1].argv) do
      if value == "--data-binary" then
        path = jobs[1].argv[index + 1]:sub(2)
      end
    end

    assert.are.equal(1, vim.fn.filereadable(path))
    assert.is_truthy(table.concat(vim.fn.readfile(path), "\n"):find(secret, 1, true))

    handle.cancel()
    assert.are.equal(1, stopped)
    assert.are.equal(0, vim.fn.filereadable(path))

    respond(1, "{}", 200)
    assert.is_false(called)
  end)
end)
