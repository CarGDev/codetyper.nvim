--- Async provider catalog with revision, cancellation, and metadata-only cache seams.
local M = {}

local function normalize(provider, items)
  local result = {}
  for _, item in ipairs(type(items) == "table" and items or {}) do
    local id = type(item) == "table" and item.id
    if type(id) == "string" and id ~= "" then
      local descriptor = {
        id = id,
        name = type(item.name) == "string" and item.name ~= "" and item.name or id,
        provider = provider,
        capabilities = type(item.capabilities) == "table" and vim.deepcopy(item.capabilities) or {},
      }
      -- Preserve only safe provider metadata needed for filtering and UI.
      for _, key in ipairs({ "subscription", "catalog_version", "cost", "version" }) do
        if item[key] ~= nil then
          descriptor[key] = vim.deepcopy(item[key])
        end
      end
      result[#result + 1] = descriptor
    end
  end
  table.sort(result, function(left, right)
    return left.id < right.id
  end)
  return result
end

--- Normalize Ollama's /api/tags response without selecting or guessing a model.
function M.normalize_ollama(payload)
  local result = {}
  for _, item in ipairs(payload and payload.models or payload or {}) do
    local id = item.id or item.name or item.model
    if type(id) == "string" and id ~= "" then
      result[#result + 1] = {
        id = id,
        name = item.name or item.model or id,
        capabilities = vim.deepcopy(item.capabilities or item.details or {}),
      }
    end
  end
  return normalize("ollama", result)
end

function M.new(options)
  options = options or {}
  local providers, cache = options.providers or {}, {}
  local now, ttl = options.now or os.time, options.ttl or 300
  local state = { status = "empty", revision = 0, models = {}, providers = {} }
  local active, catalog = nil, {}

  function catalog.snapshot()
    return vim.deepcopy(state)
  end
  local function publish(next_state, callback)
    state = next_state
    if callback then
      callback(catalog.snapshot())
    end
  end

  function catalog.refresh(callback)
    if active and not active.done then
      active.cancelled = true
    end
    local names, revision = {}, state.revision + 1
    for provider in pairs(providers) do
      names[#names + 1] = provider
    end
    table.sort(names)
    local run = { pending = #names, results = {}, handles = {}, cancelled = false, done = false }
    active = run
    publish({ status = "loading", revision = revision, models = {}, providers = {} }, callback)

    local finish
    local function complete(provider, payload, err, metadata)
      if run.cancelled or active ~= run or run.results[provider] then
        return
      end
      metadata = metadata or {}
      local result = {
        models = {},
        error = err,
        fallback = metadata.fallback == true,
        state = metadata.state,
        catalog_version = metadata.catalog_version,
      }
      if err and cache[provider] then
        result.models, result.stale, result.fallback = vim.deepcopy(cache[provider].models), true, true
      elseif not err then
        local items = provider == "ollama" and M.normalize_ollama(payload) or payload
        result.models = normalize(provider, items)
        if not result.fallback then
          cache[provider] = { models = vim.deepcopy(result.models), at = now() }
        end
      end
      run.results[provider], run.pending = result, run.pending - 1
      if run.pending == 0 then
        finish()
      end
    end
    finish = function()
      if run.done or run.cancelled or active ~= run then
        return
      end
      run.done = true
      local models, providers_state = {}, {}
      local data, empty, failures, stale, fallback = 0, 0, 0, 0, 0
      local unstable, unavailable = 0, 0
      for _, provider in ipairs(names) do
        local result = run.results[provider] or { models = {}, error = "provider did not respond" }
        for _, item in ipairs(result.models) do
          models[#models + 1] = vim.deepcopy(item)
        end
        local has_data = #result.models > 0
        if has_data then
          data = data + 1
        else
          empty = empty + 1
        end
        if result.error then
          failures = failures + 1
        end
        if result.stale then
          stale = stale + 1
        end
        if result.fallback then
          fallback = fallback + 1
        end
        if result.state == "unstable" then
          unstable = unstable + 1
        elseif result.state == "unavailable" then
          unavailable = unavailable + 1
        end
        local provider_status = result.error and (has_data and "stale" or "error")
          or (result.fallback and "fallback" or (has_data and "ready" or "empty"))
        if result.state == "unstable" or result.state == "unavailable" then
          provider_status = result.state
        end
        providers_state[provider] = {
          status = provider_status,
          models = vim.deepcopy(result.models),
          error = result.error,
          state = result.state,
          catalog_version = result.catalog_version,
        }
      end
      table.sort(models, function(left, right)
        return left.provider .. "\0" .. left.id < right.provider .. "\0" .. right.id
      end)
      local status = #names == 0 and "empty"
        or unstable == #names and "unstable"
        or unavailable == #names and "unavailable"
        or data == 0 and (failures == 0 and "empty" or "error")
        or stale == #names and failures > 0 and "stale"
        or fallback == #names and "fallback"
        or (empty > 0 or failures > 0 or stale > 0 or fallback > 0) and "partial"
        or "ready"
      publish({
        status = status,
        revision = revision,
        models = models,
        providers = providers_state,
        fallback = fallback > 0 or stale > 0,
      }, callback)
    end

    for _, provider in ipairs(names) do
      local entry = cache[provider]
      if entry and now() - entry.at < ttl then
        complete(provider, entry.models)
      else
        local fetch, called = providers[provider], false
        local function done(payload, request_error, metadata)
          if called then
            return
          end
          called = true
          complete(provider, payload, request_error, metadata)
        end
        local ok, handle = pcall(fetch, done)
        if ok then
          run.handles[provider] = handle
        else
          done(nil, tostring(handle))
        end
      end
    end
    if #names == 0 then
      finish()
    end

    local handle = {}
    function handle.cancel()
      if run.done or run.cancelled or active ~= run then
        return
      end
      run.cancelled, run.done = true, true
      for _, source_handle in pairs(run.handles) do
        if source_handle and source_handle.cancel then
          source_handle.cancel()
        end
      end
      publish({ status = "cancelled", revision = revision, models = {}, providers = {} }, callback)
    end
    return handle
  end
  return catalog
end

local default_catalog = M.new()
M.refresh = function(callback)
  return default_catalog.refresh(callback)
end
M.snapshot = function()
  return default_catalog.snapshot()
end

return M
