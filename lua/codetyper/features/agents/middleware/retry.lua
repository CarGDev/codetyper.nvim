---@class RetryConfig
---@field max_attempts number Maximum number of retry attempts (default: 3)
---@field initial_delay_ms number Initial delay in milliseconds (default: 100)
---@field max_delay_ms number Maximum delay in milliseconds (default: 5000)
---@field backoff_factor number Multiplier for exponential backoff (default: 2)
---@field retryable_errors string[]? Patterns of errors that should trigger retry

---@class RetryResult
---@field success boolean
---@field result any
---@field error? string
---@field attempts number Number of attempts made

local M = {}

---Default retry configuration
local DEFAULT_CONFIG = {
  max_attempts = 3,
  initial_delay_ms = 100,
  max_delay_ms = 5000,
  backoff_factor = 2,
}

---Check if an error is retryable
---@param error string
---@param retryable_patterns? string[]
---@return boolean
local function is_retryable_error(error, retryable_patterns)
  if not retryable_patterns or #retryable_patterns == 0 then
    -- Default retryable patterns
    local defaults = {
      "timeout",
      "connection",
      "network",
      "ECONNREFUSED",
      "ENOTFOUND",
      "ETIMEDOUT",
      "temporary",
    }
    retryable_patterns = defaults
  end

  local error_lower = error:lower()
  for _, pattern in ipairs(retryable_patterns) do
    if error_lower:match(pattern:lower()) then
      return true
    end
  end

  return false
end

---Calculate delay for next retry attempt
---@param attempt number Current attempt number (1-indexed)
---@param config RetryConfig
---@return number delay_ms
local function calculate_delay(attempt, config)
  local delay = config.initial_delay_ms * (config.backoff_factor ^ (attempt - 1))
  return math.min(delay, config.max_delay_ms)
end

---Execute a function with retry logic
---@param func function The function to execute
---@param config? RetryConfig Retry configuration
---@param callback? function(result: RetryResult) Called when all attempts complete
function M.with_retry(func, config, callback)
  config = vim.tbl_extend("force", DEFAULT_CONFIG, config or {})

  local attempt = 0
  local last_error = nil

  local function try_execute()
    attempt = attempt + 1

    -- Execute the function
    local ok, result = pcall(func)

    if ok then
      -- Success
      if callback then
        callback({
          success = true,
          result = result,
          attempts = attempt,
        })
      end
      return result
    end

    -- Failed
    last_error = tostring(result)

    -- Check if we should retry
    local should_retry = attempt < config.max_attempts and is_retryable_error(last_error, config.retryable_errors)

    if not should_retry then
      -- No more retries, return failure
      if callback then
        callback({
          success = false,
          error = last_error,
          attempts = attempt,
        })
      end
      return nil, last_error
    end

    -- Schedule retry with backoff
    local delay = calculate_delay(attempt, config)
    vim.defer_fn(try_execute, delay)
  end

  -- Start execution
  try_execute()
end

---Synchronous version of with_retry (blocks until complete or all retries exhausted)
---@param func function The function to execute
---@param config? RetryConfig Retry configuration
---@return RetryResult
function M.with_retry_sync(func, config)
  config = vim.tbl_extend("force", DEFAULT_CONFIG, config or {})

  local attempt = 0
  local last_error = nil

  while attempt < config.max_attempts do
    attempt = attempt + 1

    local ok, result = pcall(func)

    if ok then
      return {
        success = true,
        result = result,
        attempts = attempt,
      }
    end

    last_error = tostring(result)

    -- Check if error is retryable
    if not is_retryable_error(last_error, config.retryable_errors) then
      break
    end

    -- Sleep before retry (except on last attempt)
    if attempt < config.max_attempts then
      local delay = calculate_delay(attempt, config)
      vim.loop.sleep(delay)
    end
  end

  return {
    success = false,
    error = last_error,
    attempts = attempt,
  }
end

---Wrap a callback-based function with retry logic
---@param func function Function that takes (args..., callback)
---@param config? RetryConfig Retry configuration
---@return function wrapped_function
function M.wrap_callback(func, config)
  config = vim.tbl_extend("force", DEFAULT_CONFIG, config or {})

  return function(...)
    local args = { ... }
    local user_callback = table.remove(args)

    if type(user_callback) ~= "function" then
      error("Last argument must be a callback function")
    end

    local attempt = 0
    local last_error = nil

    local function try_execute()
      attempt = attempt + 1

      -- Call original function with our wrapped callback
      func(unpack(args), function(err, result)
        if not err then
          -- Success
          user_callback(nil, result, attempt)
          return
        end

        -- Failed
        last_error = tostring(err)

        -- Check if we should retry
        local should_retry = attempt < config.max_attempts
          and is_retryable_error(last_error, config.retryable_errors)

        if not should_retry then
          -- No more retries
          user_callback(last_error, nil, attempt)
          return
        end

        -- Schedule retry
        local delay = calculate_delay(attempt, config)
        vim.defer_fn(try_execute, delay)
      end)
    end

    try_execute()
  end
end

---Create a retry policy for specific error types
---@param patterns string[] Error patterns to retry on
---@param max_attempts? number
---@return RetryConfig
function M.create_policy(patterns, max_attempts)
  return {
    max_attempts = max_attempts or DEFAULT_CONFIG.max_attempts,
    initial_delay_ms = DEFAULT_CONFIG.initial_delay_ms,
    max_delay_ms = DEFAULT_CONFIG.max_delay_ms,
    backoff_factor = DEFAULT_CONFIG.backoff_factor,
    retryable_errors = patterns,
  }
end

---Common retry policies
M.policies = {
  -- Retry network-related errors
  network = M.create_policy({ "timeout", "connection", "network", "ECONNREFUSED", "ETIMEDOUT" }),

  -- Retry file system errors (busy, locked)
  filesystem = M.create_policy({ "EBUSY", "EAGAIN", "locked", "busy" }),

  -- Retry all errors
  always = M.create_policy({ ".*" }),

  -- Never retry
  never = {
    max_attempts = 1,
    initial_delay_ms = 0,
    max_delay_ms = 0,
    backoff_factor = 1,
  },
}

return M
