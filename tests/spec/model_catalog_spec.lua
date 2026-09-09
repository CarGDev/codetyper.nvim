local catalog_module = require("codetyper.core.llm.model_catalog")

local function descriptor(id, provider)
  return { id = id, name = id, provider = provider, capabilities = { streaming = false }, secret = "do-not-cache" }
end

local function final(catalog)
  catalog.refresh()
  return catalog.snapshot()
end

local function status(payload, err, metadata)
  local source = function(done)
    done(payload, err, metadata)
  end
  return final(catalog_module.new({ providers = { ollama = source } })).status
end

describe("async model catalog", function()
  it("normalizes Ollama, strips secrets, and honors metadata TTL cache", function()
    local now, calls = 100, 0
    local source = function(done)
      calls = calls + 1
      done({ models = { { name = "llama3:8b", details = { family = "llama" } }, { name = "" } } })
    end
    local catalog = catalog_module.new({
      providers = { ollama = source },
      ttl = 10,
      now = function()
        return now
      end,
    })
    local first = final(catalog)
    assert.are.equal("ready", first.status)
    assert.are.equal("llama3:8b", first.models[1].id)
    assert.are.equal("ollama", first.models[1].provider)
    assert.same({ family = "llama" }, first.models[1].capabilities)
    assert.is_nil(first.models[1].secret)
    final(catalog)
    assert.are.equal(1, calls)
    now = 111
    final(catalog)
    assert.are.equal(2, calls)
  end)

  it("emits loading, partial, empty, fallback, error, and cancelled states", function()
    local pending_done, last = nil, nil
    local catalog = catalog_module.new({
      providers = {
        ollama = function(done)
          pending_done = done
        end,
        copilot = function(done)
          done({ descriptor("gpt-4o", "copilot") }, "unavailable")
        end,
      },
    })
    catalog.refresh(function(state)
      last = state
    end)
    assert.are.equal("loading", last.status)
    pending_done({ descriptor("llama3", "ollama") })
    assert.are.equal("partial", last.status)

    assert.are.equal("empty", status({}))
    assert.are.equal("fallback", status({ descriptor("llama3", "ollama") }, nil, { fallback = true }))
    assert.are.equal("error", status(nil, "offline"))

    local late
    local cancellable = catalog_module.new({
      providers = {
        ollama = function(done)
          late = done
        end,
      },
    })
    local handle = cancellable.refresh(function(state)
      last = state
    end)
    handle.cancel()
    late({ descriptor("late", "ollama") })
    assert.are.equal("cancelled", last.status)
  end)

  it("preserves revision order and stale fallback metadata", function()
    local completions = {}
    local catalog = catalog_module.new({
      providers = {
        ollama = function(done)
          completions[#completions + 1] = done
        end,
      },
    })
    catalog.refresh(function() end)
    catalog.refresh(function() end)
    completions[2]({ descriptor("new", "ollama") })
    completions[1]({ descriptor("old", "ollama") })
    local snapshot = catalog.snapshot()
    assert.are.equal(2, snapshot.revision)
    assert.are.equal("new", snapshot.models[1].id)

    local now = 1
    local stale = catalog_module.new({
      ttl = 1,
      now = function()
        return now
      end,
      providers = {
        ollama = function(done)
          if now == 1 then
            done({ descriptor("cached", "ollama") })
          else
            done(nil, "offline")
          end
        end,
      },
    })
    final(stale)
    now = 3
    assert.are.equal("stale", final(stale).status)
    assert.is_true(stale.snapshot().fallback)
  end)

  it("keeps verified OpenAI subscription metadata distinct from ordinary models", function()
    local openai = require("codetyper.core.llm.providers.openai.models")
    local catalog = catalog_module.new({
      providers = {
        openai = function(done)
          return openai.fetch(done, {
            records = {
              { id = "gpt-5.5", name = "GPT-5.5" },
              { id = "gpt-4o", name = "GPT-4o", subscription = false },
            },
          })
        end,
      },
    })

    catalog.refresh()
    local snapshot = catalog.snapshot()
    assert.are.equal("ready", snapshot.status)
    assert.are.equal(1, #snapshot.models)
    assert.are.equal("openai", snapshot.models[1].provider)
    assert.is_true(snapshot.models[1].subscription)
    assert.are.equal(0, snapshot.models[1].cost)
    assert.are.equal(openai.ALLOWLIST_VERSION, snapshot.models[1].catalog_version)
    assert.are.equal("ready", snapshot.providers.openai.status)
  end)

  it("surfaces an unstable OpenAI catalog without replacing it with fallback data", function()
    local catalog = catalog_module.new({
      providers = {
        openai = function(done)
          done(nil, "OpenAI subscription catalog is unstable", { state = "unstable" })
        end,
      },
    })

    catalog.refresh()
    local snapshot = catalog.snapshot()
    assert.are.equal("unstable", snapshot.status)
    assert.are.equal("unstable", snapshot.providers.openai.status)
    assert.are.equal(0, #snapshot.models)
    assert.is_false(snapshot.fallback)
  end)
end)
