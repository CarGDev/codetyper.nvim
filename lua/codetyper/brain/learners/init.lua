--- Brain Learners Coordinator
--- Routes learning events to appropriate learners

local types = require("codetyper.brain.types")

local M = {}

-- Lazy load learners
local function get_pattern_learner()
  return require("codetyper.brain.learners.pattern")
end

local function get_correction_learner()
  return require("codetyper.brain.learners.correction")
end

local function get_convention_learner()
  return require("codetyper.brain.learners.convention")
end

--- All available learners
local LEARNERS = {
  { name = "pattern", loader = get_pattern_learner },
  { name = "correction", loader = get_correction_learner },
  { name = "convention", loader = get_convention_learner },
}

--- Process a learning event
---@param event LearnEvent Learning event
---@return string|nil Created node ID
function M.process(event)
  if not event or not event.type then
    return nil
  end

  -- Add timestamp if missing
  event.timestamp = event.timestamp or os.time()

  -- Find matching learner
  for _, learner_info in ipairs(LEARNERS) do
    local learner = learner_info.loader()

    if learner.detect(event) then
      return M.learn_with(learner, event)
    end
  end

  -- Handle generic feedback events
  if event.type == "user_feedback" then
    return M.process_feedback(event)
  end

  -- Handle session events
  if event.type == "session_start" or event.type == "session_end" then
    return M.process_session(event)
  end

  return nil
end

--- Learn using a specific learner
---@param learner table Learner module
---@param event LearnEvent Learning event
---@return string|nil Created node ID
function M.learn_with(learner, event)
  -- Extract data
  local extracted = learner.extract(event)
  if not extracted then
    return nil
  end

  -- Handle multiple extractions (e.g., from file indexing)
  if vim.islist(extracted) then
    local node_ids = {}
    for _, data in ipairs(extracted) do
      local node_id = M.create_learning(learner, data, event)
      if node_id then
        table.insert(node_ids, node_id)
      end
    end
    return node_ids[1] -- Return first for now
  end

  return M.create_learning(learner, extracted, event)
end

--- Create a learning from extracted data
---@param learner table Learner module
---@param data table Extracted data
---@param event LearnEvent Original event
---@return string|nil Created node ID
function M.create_learning(learner, data, event)
  -- Check if should learn
  if not learner.should_learn(data) then
    return nil
  end

  -- Get node params
  local params = learner.create_node_params(data)

  -- Get graph module
  local graph = require("codetyper.brain.graph")

  -- Find related nodes
  local related_ids = {}
  if learner.find_related then
    related_ids = learner.find_related(data, function(opts)
      return graph.query.execute(opts).nodes
    end)
  end

  -- Create the learning
  local node = graph.add_learning(params.node_type, params.content, params.context, related_ids)

  -- Update weight if specified
  if params.opts and params.opts.weight then
    graph.node.update(node.id, { sc = { w = params.opts.weight } })
  end

  return node.id
end

--- Process feedback event
---@param event LearnEvent Feedback event
---@return string|nil Created node ID
function M.process_feedback(event)
  local data = event.data or {}
  local graph = require("codetyper.brain.graph")

  local content = {
    s = "Feedback: " .. (data.feedback or "unknown"),
    d = data.description or ("User " .. (data.feedback or "gave feedback")),
  }

  local context = {
    f = event.file,
  }

  -- If feedback references a node, update it
  if data.node_id then
    local node = graph.node.get(data.node_id)
    if node then
      local weight_delta = data.feedback == "accepted" and 0.1 or -0.1
      local new_weight = math.max(0, math.min(1, node.sc.w + weight_delta))

      graph.node.update(data.node_id, {
        sc = { w = new_weight },
      })

      -- Record usage
      graph.node.record_usage(data.node_id, data.feedback == "accepted")

      -- Create feedback node linked to original
      local fb_node = graph.add_learning(types.NODE_TYPES.FEEDBACK, content, context, { data.node_id })

      return fb_node.id
    end
  end

  -- Create standalone feedback node
  local node = graph.add_learning(types.NODE_TYPES.FEEDBACK, content, context)
  return node.id
end

--- Process session event
---@param event LearnEvent Session event
---@return string|nil Created node ID
function M.process_session(event)
  local data = event.data or {}
  local graph = require("codetyper.brain.graph")

  local content = {
    s = event.type == "session_start" and "Session started" or "Session ended",
    d = data.description or event.type,
  }

  if event.type == "session_end" and data.stats then
    content.d = content.d .. "\n\nStats:"
    content.d = content.d .. "\n- Completions: " .. (data.stats.completions or 0)
    content.d = content.d .. "\n- Corrections: " .. (data.stats.corrections or 0)
    content.d = content.d .. "\n- Files: " .. (data.stats.files or 0)
  end

  local node = graph.add_learning(types.NODE_TYPES.SESSION, content, {})

  -- Link to recent session nodes
  if event.type == "session_end" then
    local recent = graph.query.by_time_range(os.time() - 3600, os.time(), 20) -- Last hour
    local session_nodes = {}

    for _, n in ipairs(recent) do
      if n.id ~= node.id then
        table.insert(session_nodes, n.id)
      end
    end

    -- Create temporal links
    if #session_nodes > 0 then
      graph.link_temporal(session_nodes)
    end
  end

  return node.id
end

--- Batch process multiple events
---@param events LearnEvent[] Events to process
---@return string[] Created node IDs
function M.batch_process(events)
  local node_ids = {}

  for _, event in ipairs(events) do
    local node_id = M.process(event)
    if node_id then
      table.insert(node_ids, node_id)
    end
  end

  return node_ids
end

--- Get learner names
---@return string[]
function M.get_learner_names()
  local names = {}
  for _, learner in ipairs(LEARNERS) do
    table.insert(names, learner.name)
  end
  return names
end

return M
