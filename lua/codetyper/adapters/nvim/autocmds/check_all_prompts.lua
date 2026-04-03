local flog = require("codetyper.support.flog") -- TODO: remove after debugging

--- Process all closed prompts in the buffer sequentially (bottom-to-top)
--- Waits for each to complete before starting the next to avoid line shifts.
local function check_all_prompts()
  local find_prompts_in_buffer = require("codetyper.parser.find_prompts_in_buffer")
  local process_single_prompt = require("codetyper.adapters.nvim.autocmds.process_single_prompt")
  local constants = require("codetyper.constants.constants")
  local get_prompt_key = require("codetyper.adapters.nvim.autocmds.get_prompt_key")

  local bufnr = vim.api.nvim_get_current_buf()
  local current_file = vim.fn.expand("%:p")

  if current_file == "" then
    return
  end

  local codetyper = require("codetyper")
  local ct_config = codetyper.get_config()
  local scheduler_enabled = ct_config and ct_config.scheduler and ct_config.scheduler.enabled

  if not scheduler_enabled then
    return
  end

  -- Find all unprocessed prompts
  local prompts = find_prompts_in_buffer(bufnr)
  local unprocessed = {}
  for _, prompt in ipairs(prompts) do
    local key = get_prompt_key(bufnr, prompt)
    if not constants.processed_prompts[key] then
      table.insert(unprocessed, prompt)
    end
  end

  if #unprocessed == 0 then
    return
  end

  -- Sort bottom-to-top so earlier injections don't shift later tag positions
  table.sort(unprocessed, function(a, b)
    return (a.start_line or 0) > (b.start_line or 0)
  end)

  flog.info("check_all", string.format("processing %d tags sequentially (bottom-to-top)", #unprocessed)) -- TODO: remove after debugging

  -- Process one at a time: enqueue first, poll for completion, then next
  local idx = 1

  local function process_next()
    if idx > #unprocessed then
      flog.info("check_all", "all tags processed") -- TODO: remove after debugging
      vim.notify(string.format("All %d tag(s) processed", #unprocessed), vim.log.levels.INFO)
      return
    end

    -- Re-read prompts from buffer (lines may have shifted from previous injection)
    local current_prompts = find_prompts_in_buffer(bufnr)
    local current_unprocessed = {}
    for _, p in ipairs(current_prompts) do
      local key = get_prompt_key(bufnr, p)
      if not constants.processed_prompts[key] then
        table.insert(current_unprocessed, p)
      end
    end

    if #current_unprocessed == 0 then
      flog.info("check_all", "no more unprocessed tags found") -- TODO: remove after debugging
      return
    end

    -- Sort bottom-to-top again (lines may have shifted)
    table.sort(current_unprocessed, function(a, b)
      return (a.start_line or 0) > (b.start_line or 0)
    end)

    -- Process the last one (bottom-most) — it won't shift any other tags above it
    local prompt = current_unprocessed[1]
    flog.info("check_all", string.format( -- TODO: remove after debugging
      "processing tag %d: lines %d-%d content=%s",
      idx, prompt.start_line or 0, prompt.end_line or 0,
      (prompt.content or ""):sub(1, 40):gsub("\n", " ")
    ))

    process_single_prompt(bufnr, prompt, current_file, false)
    idx = idx + 1

    -- Wait for the scheduler to finish this tag before processing next
    -- Poll every 1s — check if the queue is empty, with 30s max timeout
    local poll_timer = vim.loop.new_timer()
    local poll_start = os.clock()
    local MAX_POLL_SECONDS = 30

    poll_timer:start(1000, 1000, vim.schedule_wrap(function()
      local elapsed = os.clock() - poll_start

      -- Force stop if polling too long
      if elapsed > MAX_POLL_SECONDS then
        poll_timer:stop()
        poll_timer:close()
        flog.warn("check_all", "poll timer timed out after " .. MAX_POLL_SECONDS .. "s")
        return
      end

      local queue = require("codetyper.core.events.queue")
      local pending = queue.pending_count()
      local processing = queue.processing_count()

      if pending == 0 and processing == 0 then
        poll_timer:stop()
        poll_timer:close()
        -- Small delay for buffer to stabilize after injection
        vim.defer_fn(function()
          process_next()
        end, 300)
      end
    end))
  end

  process_next()
end

return check_all_prompts
