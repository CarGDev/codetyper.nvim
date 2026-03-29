local flog = require("codetyper.support.flog") -- TODO: remove after debugging

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
      target_lines = lines
      target_content = table.concat(lines, "\n")
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

  -- Brain memories
  local brain_content = ""
  pcall(function()
    local brain = require("codetyper.core.memory")
    if brain.is_initialized() then
      local query_text = event.prompt_content or ""
      if event.scope and event.scope.name then
        query_text = event.scope.name .. " " .. query_text
      end

      local result = brain.query({
        query = query_text,
        file = event.target_path,
        max_results = 5,
        types = { "pattern", "correction", "convention" },
      })

      if result and result.nodes and #result.nodes > 0 then
        local memories = { "\n\n--- Learned Patterns & Conventions ---" }
        for _, node in ipairs(result.nodes) do
          if node.c then
            local summary = node.c.s or ""
            local detail = node.c.d or ""
            if summary ~= "" then
              table.insert(memories, "• " .. summary)
              if detail ~= "" and #detail < 200 then
                table.insert(memories, "  " .. detail)
              end
            end
          end
        end
        if #memories > 1 then
          brain_content = table.concat(memories, "\n")
        end
      end
    end
  end)

  -- Project tree context (for whole-file selections)
  local project_content = ""
  if event.is_whole_file and event.project_context then
    project_content = "\n\n--- Project Structure ---\n" .. event.project_context
  end

  -- Combined extra context string
  local extra = brain_content .. coder_content .. attached_content .. indexed_content .. project_content

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
