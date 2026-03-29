local flog = require("codetyper.support.flog") -- TODO: remove after debugging

--- Strip /@ @/ tag blocks from file lines, except the one at current_range
---@param lines string[] File lines
---@param current_range table|nil { start_line, end_line } Range to keep (1-based)
---@return string[] cleaned lines with other tags replaced by a placeholder comment
local function strip_other_tags(lines, current_range)
  local result = {}
  local in_tag = false
  local tag_start = 0

  for i, line in ipairs(lines) do
    if line:match("^/?@") or line:match("^%s*/?@") then
      -- Opening /@ tag
      if not in_tag then
        in_tag = true
        tag_start = i
      end
    end

    if in_tag then
      -- Check if this is the current tag we're processing — keep it
      local is_current = current_range
        and i >= current_range.start_line
        and i <= current_range.end_line
      if is_current then
        table.insert(result, line)
      end
      -- Skip other tag lines (don't add to result)

      -- Check for closing @/ tag
      if line:match("@/$") or line:match("@/%s*$") then
        if not is_current and tag_start > 0 then
          table.insert(result, "-- [other prompt tag removed]")
        end
        in_tag = false
        tag_start = 0
      end
    else
      table.insert(result, line)
    end
  end

  return result
end

--- Gather all context sources for a prompt event
---@param event table PromptEvent
---@return table context { target_content, target_lines, filetype, brain, coder, indexed, attached, project, extra }
local function gather(event)
  flog.info("build_context", ">>> gather ENTERED") -- TODO: remove after debugging

  -- Read target file
  local target_content = ""
  local target_lines = {}
  if event.target_path then
    local ok, lines = pcall(function()
      return vim.fn.readfile(event.target_path)
    end)
    if ok and lines then
      -- Strip other /@ @/ tags so the LLM only sees the current one
      local cleaned = strip_other_tags(lines, event.range)
      target_lines = cleaned
      target_content = table.concat(cleaned, "\n")
    end
  end

  local filetype = vim.fn.fnamemodify(event.target_path or "", ":e")

  -- Search index
  local indexed_content = ""
  pcall(function()
    local indexer = require("codetyper.features.indexer")
    local indexed_context = indexer.get_context_for({
      file = event.target_path,
      intent = event.intent,
      prompt = event.prompt_content,
      scope = event.scope_text,
    })
    if indexed_context then
      local parts = {}
      if indexed_context.relevant_functions then
        for _, func in ipairs(indexed_context.relevant_functions) do
          if func.text then
            table.insert(parts, func.text)
          end
        end
      end
      if #parts > 0 then
        indexed_content = "\n\n--- Indexed Context ---\n" .. table.concat(parts, "\n\n")
      end
    end
  end)

  -- Attached files
  local attached_content = ""
  if event.attached_files and #event.attached_files > 0 then
    local parts = { "\n\n--- Attached Files ---" }
    for _, file in ipairs(event.attached_files) do
      local path_display = file.path or file.full_path or "unknown"
      table.insert(parts, string.format("File: %s\n```\n%s\n```", path_display, file.content or ""))
    end
    attached_content = table.concat(parts, "\n")
  end

  -- Coder companion context
  local coder_content = ""
  pcall(function()
    if not event.target_path then
      return
    end
    local coder_path = event.target_path:gsub("([^/]+)$", ".codetyper.%1")
    if vim.fn.filereadable(coder_path) == 1 then
      local lines_read = vim.fn.readfile(coder_path)
      if lines_read and #lines_read > 0 then
        coder_content = "\n\n--- Coder Context ---\n" .. table.concat(lines_read, "\n"):sub(1, 3000)
      end
    end
  end)

  -- Brain memories — targeted queries based on what the LLM needs to know
  local brain_content = ""
  pcall(function()
    local brain = require("codetyper.core.memory")
    if not brain.is_initialized() then
      return
    end

    local memories = {}
    local intent_type = event.intent and event.intent.type or ""
    local filename = vim.fn.fnamemodify(event.target_path or "", ":t")

    -- Query 1: File-specific conventions (how code is written in THIS file)
    local file_result = brain.query({
      query = filename,
      file = event.target_path,
      max_results = 2,
      types = { "file_indexed", "pattern" },
    })
    if file_result and file_result.nodes then
      for _, node in ipairs(file_result.nodes) do
        if node.c then
          local detail = node.c.d or ""
          -- Only include style/convention info, not raw code
          if detail:match("Style:") or detail:match("conventions:") or detail:match("functions:") then
            table.insert(memories, "• " .. (node.c.s or filename) .. ": " .. detail:sub(1, 200))
          end
        end
      end
    end

    -- Query 2: Intent-specific patterns (how this type of edit was done before)
    if intent_type ~= "" then
      local intent_result = brain.query({
        query = intent_type .. " " .. (event.scope and event.scope.name or ""),
        file = event.target_path,
        max_results = 2,
        types = { "code_completion", "correction" },
      })
      if intent_result and intent_result.nodes then
        for _, node in ipairs(intent_result.nodes) do
          if node.c then
            local summary = node.c.s or ""
            local detail = node.c.d or ""
            -- Skip old generic patterns
            if summary:match("^Code pattern:") then
              goto skip
            end
            -- Only include if detail has useful info (conventions, strategy)
            if detail:match("Conventions:") or detail:match("Strategy:") or detail:match("Prompt:") then
              table.insert(memories, "• Previous " .. intent_type .. ": " .. detail:sub(1, 200))
            elseif summary ~= "" and #summary < 100 then
              table.insert(memories, "• " .. summary)
            end
          end
          ::skip::
        end
      end
    end

    -- Query 3: Scope-specific (if inside a function, what patterns exist for it)
    if event.scope and event.scope.name and event.scope.name ~= "" then
      local scope_result = brain.query({
        query = event.scope.name,
        max_results = 1,
        types = { "file_indexed" },
      })
      if scope_result and scope_result.nodes and #scope_result.nodes > 0 then
        local node = scope_result.nodes[1]
        if node.c and node.c.d and node.c.d:match("Style:") then
          table.insert(memories, "• Scope context: " .. (node.c.d or ""):sub(1, 150))
        end
      end
    end

    if #memories > 0 then
      -- Deduplicate
      local seen = {}
      local unique = {}
      for _, m in ipairs(memories) do
        if not seen[m] then
          seen[m] = true
          table.insert(unique, m)
        end
      end

      brain_content = "\n\n--- Project Conventions (from memory) ---\n" .. table.concat(unique, "\n")
      flog.info("build_context", string.format("brain: %d targeted memories", #unique)) -- TODO: remove after debugging
    end
  end)

  -- Project tree context (for whole-file selections)
  local project_content = ""
  if event.is_whole_file and event.project_context then
    project_content = "\n\n--- Project Structure ---\n" .. event.project_context
  end

  -- Architecture conventions (always include — helps LLM know where code goes)
  local arch_content = ""
  pcall(function()
    local architecture = require("codetyper.core.agent.architecture")
    arch_content = architecture.get_architecture_context()
  end)

  -- Combined extra context string
  local extra = brain_content .. arch_content .. coder_content .. attached_content .. indexed_content .. project_content

  flog.info("build_context", string.format( -- TODO: remove after debugging
    "brain=%d coder=%d indexed=%d attached=%d project=%d total_extra=%d",
    #brain_content, #coder_content, #indexed_content, #attached_content, #project_content, #extra
  ))

  return {
    target_content = target_content,
    target_lines = target_lines,
    filetype = filetype,
    brain = brain_content,
    coder = coder_content,
    indexed = indexed_content,
    attached = attached_content,
    project = project_content,
    extra = extra,
  }
end

return gather
