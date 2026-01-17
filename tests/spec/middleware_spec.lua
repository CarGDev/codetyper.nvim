---@diagnostic disable: undefined-field
local session = require("codetyper.features.agents.middleware.session")
local permissions = require("codetyper.features.agents.middleware.permissions")
local hooks = require("codetyper.features.agents.middleware.hooks")
local retry = require("codetyper.features.agents.middleware.retry")

describe("middleware.session", function()
  before_each(function()
    session.clear()
  end)

  after_each(function()
    session.clear()
  end)

  it("creates a new session", function()
    local sess = session.create()
    assert.is_not_nil(sess)
    assert.is_not_nil(sess.id)
    assert.is_table(sess.permissions)
    assert.is_number(sess.created_at)
  end)

  it("returns the current session", function()
    local sess1 = session.create()
    local sess2 = session.get_current()
    assert.are.equal(sess1.id, sess2.id)
  end)

  it("clears the session", function()
    session.create()
    assert.is_true(session.is_active())
    session.clear()
    assert.is_false(session.is_active())
  end)

  it("stores and retrieves context", function()
    session.create()
    session.set_context("test_key", "test_value")
    assert.are.equal("test_value", session.get_context("test_key"))
  end)

  it("calculates session age", function()
    session.create()
    vim.loop.sleep(100) -- Wait 100ms
    local age = session.get_age()
    assert.is_not_nil(age)
    assert.is_true(age >= 0)
  end)

  it("returns nil age when no session", function()
    session.clear()
    assert.is_nil(session.get_age())
  end)
end)

describe("middleware.permissions", function()
  before_each(function()
    session.clear()
    session.create()
  end)

  after_each(function()
    session.clear()
  end)

  describe("check", function()
    it("auto-approves read-only tools", function()
      local result = permissions.check("view", {}, {})
      assert.is_true(result.allowed)
      assert.is_true(result.auto)
      assert.are.equal("Read-only operation", result.reason)
    end)

    it("auto-approves grep tool", function()
      local result = permissions.check("grep", { pattern = "test" }, {})
      assert.is_true(result.allowed)
      assert.is_true(result.auto)
    end)

    it("requires approval for bash commands", function()
      local result = permissions.check("bash", { command = "echo hello" }, {})
      assert.is_false(result.allowed)
      assert.is_false(result.auto)
    end)

    it("detects dangerous bash commands", function()
      local result = permissions.check("bash", { command = "rm -rf /" }, {})
      assert.is_false(result.allowed)
      assert.is_false(result.auto)
      assert.matches("Dangerous command pattern", result.reason)
    end)

    it("detects sudo commands", function()
      local result = permissions.check("bash", { command = "sudo apt-get install" }, {})
      assert.is_false(result.allowed)
      assert.matches("Dangerous command pattern", result.reason)
    end)

    it("requires approval for write operations", function()
      local result = permissions.check("write_file", { path = "test.txt" }, {})
      assert.is_false(result.allowed)
      assert.is_false(result.auto)
    end)
  end)

  describe("grant and caching", function()
    it("caches approved permissions in session", function()
      local tool_name = "bash"
      local input = { command = "echo hello" }

      -- First check - should require approval
      local result1 = permissions.check(tool_name, input, {})
      assert.is_false(result1.allowed)

      -- Grant permission
      permissions.grant(tool_name, input, "session")

      -- Second check - should be auto-approved from cache
      local result2 = permissions.check(tool_name, input, {})
      assert.is_true(result2.allowed)
      assert.is_true(result2.auto)
      assert.matches("Previously approved", result2.reason)
    end)

    it("different commands are not cached together", function()
      permissions.grant("bash", { command = "echo hello" }, "session")

      -- Different command should not be auto-approved
      local result = permissions.check("bash", { command = "echo world" }, {})
      assert.is_false(result.allowed)
    end)
  end)

  describe("revoke", function()
    it("removes cached permission", function()
      local tool_name = "bash"
      local input = { command = "echo test" }

      -- Grant and verify cached
      permissions.grant(tool_name, input, "session")
      local result1 = permissions.check(tool_name, input, {})
      assert.is_true(result1.allowed)

      -- Revoke and verify not cached
      permissions.revoke(tool_name, input)
      local result2 = permissions.check(tool_name, input, {})
      assert.is_false(result2.allowed)
    end)
  end)

  describe("clear_session", function()
    it("clears all cached permissions", function()
      permissions.grant("bash", { command = "echo 1" }, "session")
      permissions.grant("bash", { command = "echo 2" }, "session")

      permissions.clear_session()

      -- Both should require approval again
      local result1 = permissions.check("bash", { command = "echo 1" }, {})
      local result2 = permissions.check("bash", { command = "echo 2" }, {})
      assert.is_false(result1.allowed)
      assert.is_false(result2.allowed)
    end)
  end)

  describe("custom tools and patterns", function()
    it("registers custom safe tools", function()
      permissions.register_safe_tool("my_custom_tool")
      local result = permissions.check("my_custom_tool", {}, {})
      assert.is_true(result.allowed)
      assert.is_true(result.auto)
    end)

    it("registers custom dangerous patterns", function()
      permissions.register_dangerous_pattern("dangerous_command")
      local result = permissions.check("bash", { command = "dangerous_command" }, {})
      assert.is_false(result.allowed)
      assert.matches("Dangerous command pattern", result.reason)
    end)
  end)
end)

describe("middleware.hooks", function()
  before_each(function()
    hooks.clear()
  end)

  after_each(function()
    hooks.clear()
  end)

  describe("register and invoke", function()
    it("registers and invokes hooks", function()
      local called = false
      hooks.register("pre_tool", function(ctx)
        called = true
        return true
      end)

      local result = hooks.invoke("pre_tool", { tool_name = "test" })
      assert.is_true(called)
      assert.is_true(result)
    end)

    it("passes context to hook callback", function()
      local received_ctx = nil
      hooks.register("pre_tool", function(ctx)
        received_ctx = ctx
        return true
      end)

      local test_ctx = { tool_name = "test", input = { foo = "bar" } }
      hooks.invoke("pre_tool", test_ctx)

      assert.is_not_nil(received_ctx)
      assert.are.equal("test", received_ctx.tool_name)
      assert.are.equal("bar", received_ctx.input.foo)
    end)

    it("rejects execution when hook returns false", function()
      hooks.register("pre_tool", function(ctx)
        return false
      end)

      local result = hooks.invoke("pre_tool", {})
      assert.is_false(result)
    end)

    it("continues when hook returns nil", function()
      hooks.register("pre_tool", function(ctx)
        -- Return nil (implicit)
      end)

      local result = hooks.invoke("pre_tool", {})
      assert.is_true(result)
    end)

    it("handles hook errors gracefully", function()
      hooks.register("pre_tool", function(ctx)
        error("Hook error")
      end)

      -- Should not crash, but continue
      local result = hooks.invoke("pre_tool", {})
      -- Result should still be true (hook crashed but didn't reject)
      assert.is_true(result)
    end)
  end)

  describe("multiple hooks", function()
    it("invokes all registered hooks in order", function()
      local call_order = {}
      hooks.register("pre_tool", function()
        table.insert(call_order, 1)
        return true
      end)
      hooks.register("pre_tool", function()
        table.insert(call_order, 2)
        return true
      end)
      hooks.register("pre_tool", function()
        table.insert(call_order, 3)
        return true
      end)

      hooks.invoke("pre_tool", {})

      assert.are.equal(3, #call_order)
      assert.are.equal(1, call_order[1])
      assert.are.equal(2, call_order[2])
      assert.are.equal(3, call_order[3])
    end)

    it("stops invoking when a hook rejects", function()
      local call_order = {}
      hooks.register("pre_tool", function()
        table.insert(call_order, 1)
        return true
      end)
      hooks.register("pre_tool", function()
        table.insert(call_order, 2)
        return false -- Reject
      end)
      hooks.register("pre_tool", function()
        table.insert(call_order, 3)
        return true
      end)

      local result = hooks.invoke("pre_tool", {})

      assert.is_false(result)
      assert.are.equal(2, #call_order) -- Third hook should not be called
    end)
  end)

  describe("unregister", function()
    it("returns unregister function", function()
      local unregister = hooks.register("pre_tool", function() end)
      assert.is_function(unregister)
    end)

    it("unregisters hook when unregister is called", function()
      local called = false
      local unregister = hooks.register("pre_tool", function()
        called = true
      end)

      unregister()
      hooks.invoke("pre_tool", {})

      assert.is_false(called)
    end)
  end)

  describe("timing", function()
    it("starts timing a context", function()
      local ctx = { tool_name = "test" }
      hooks.start_timing(ctx)
      assert.is_not_nil(ctx.start_time)
    end)

    it("ends timing and calculates duration", function()
      local ctx = { tool_name = "test" }
      hooks.start_timing(ctx)
      vim.loop.sleep(10) -- Wait 10ms
      hooks.end_timing(ctx)

      assert.is_not_nil(ctx.end_time)
      assert.is_not_nil(ctx.duration_ms)
      assert.is_true(ctx.duration_ms >= 0)
    end)
  end)

  describe("count", function()
    it("counts hooks for specific type", function()
      assert.are.equal(0, hooks.count("pre_tool"))
      hooks.register("pre_tool", function() end)
      assert.are.equal(1, hooks.count("pre_tool"))
      hooks.register("pre_tool", function() end)
      assert.are.equal(2, hooks.count("pre_tool"))
    end)

    it("counts all hooks when no type specified", function()
      hooks.register("pre_tool", function() end)
      hooks.register("post_tool", function() end)
      -- Note: There are built-in hooks registered by default
      local total = hooks.count()
      assert.is_true(total >= 2)
    end)
  end)
end)

describe("middleware.retry", function()
  describe("with_retry_sync", function()
    it("succeeds on first attempt", function()
      local attempt_count = 0
      local result = retry.with_retry_sync(function()
        attempt_count = attempt_count + 1
        return "success"
      end)

      assert.is_true(result.success)
      assert.are.equal("success", result.result)
      assert.are.equal(1, attempt_count)
      assert.are.equal(1, result.attempts)
    end)

    it("retries on retryable errors", function()
      local attempt_count = 0
      local result = retry.with_retry_sync(function()
        attempt_count = attempt_count + 1
        if attempt_count < 3 then
          error("timeout error")
        end
        return "success"
      end, retry.policies.network)

      assert.is_true(result.success)
      assert.are.equal("success", result.result)
      assert.are.equal(3, attempt_count)
      assert.are.equal(3, result.attempts)
    end)

    it("exhausts retries on persistent errors", function()
      local attempt_count = 0
      local result = retry.with_retry_sync(function()
        attempt_count = attempt_count + 1
        error("timeout error")
      end, retry.policies.network)

      assert.is_false(result.success)
      assert.is_not_nil(result.error)
      assert.matches("timeout error", result.error)
      assert.are.equal(3, attempt_count) -- Default max_attempts
    end)

    it("does not retry non-retryable errors", function()
      local attempt_count = 0
      local result = retry.with_retry_sync(function()
        attempt_count = attempt_count + 1
        error("syntax error")
      end, retry.policies.network)

      assert.is_false(result.success)
      assert.are.equal(1, attempt_count) -- Should not retry
    end)

    it("respects custom max_attempts", function()
      local attempt_count = 0
      local result = retry.with_retry_sync(function()
        attempt_count = attempt_count + 1
        error("timeout")
      end, { max_attempts = 5, retryable_errors = { "timeout" } })

      assert.is_false(result.success)
      assert.are.equal(5, attempt_count)
    end)
  end)

  describe("create_policy", function()
    it("creates custom retry policy", function()
      local policy = retry.create_policy({ "custom_error" }, 2)
      assert.are.equal(2, policy.max_attempts)
      assert.is_table(policy.retryable_errors)
    end)
  end)

  describe("builtin policies", function()
    it("has network policy", function()
      assert.is_table(retry.policies.network)
      assert.is_number(retry.policies.network.max_attempts)
    end)

    it("has filesystem policy", function()
      assert.is_table(retry.policies.filesystem)
    end)

    it("has never retry policy", function()
      assert.is_table(retry.policies.never)
      assert.are.equal(1, retry.policies.never.max_attempts)
    end)
  end)
end)
