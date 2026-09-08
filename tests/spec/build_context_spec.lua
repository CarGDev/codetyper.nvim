--- Tests for build_context.gather()'s dependency-context wiring.
--- Confirmed gap: the primary tag/scheduler flow (core/scheduler/worker.lua
--- -> build_context.gather()) never called resolve_deps, unlike the
--- explain-prompt flow (core/transform.lua:114-116), so scheduled edits
--- never saw import/importer context. This mirrors that exact wiring,
--- guarded so a resolve_deps failure never aborts the rest of gather().

local gather = require("codetyper.core.llm.shared.build_context")

local function make_tmp_file(content)
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local path = dir .. "/target.lua"
  local f = io.open(path, "w")
  f:write(content)
  f:close()
  return path
end

describe("build_context.gather — dependency context wiring", function()
  after_each(function()
    -- Ensure no stub leaks into other spec files sharing this module.
    package.loaded["codetyper.core.llm.shared.resolve_deps"] = nil
  end)

  it("includes a dependency-context block listing imports and importers when target_path is present", function()
    local path = make_tmp_file('local other = require("codetyper.core.other")\nreturn {}\n')

    package.loaded["codetyper.core.llm.shared.resolve_deps"] = {
      resolve = function(filepath, _content, _language)
        return { filepath = filepath, imports = { "codetyper.core.other" }, importers = { { file = "caller.lua", line = 3, match = 'require("target")' } } }
      end,
      format_context = function(deps)
        return "**File dependency context for `" .. deps.filepath .. "`:**\n"
          .. "**This file imports:**\n- `" .. deps.imports[1] .. "`\n"
          .. "**Files that import/require this file:**\n- `" .. deps.importers[1].file .. "`\n"
      end,
    }

    local ctx = gather({ target_path = path })

    assert.is_not_nil(ctx.extra:find("File dependency context"))
    assert.is_not_nil(ctx.extra:find("codetyper.core.other"))
    assert.is_not_nil(ctx.extra:find("caller.lua"))
  end)

  it("returns successfully with no dependency block and no error when target_path is nil", function()
    local called = false
    package.loaded["codetyper.core.llm.shared.resolve_deps"] = {
      resolve = function()
        called = true
        return { filepath = "", imports = {}, importers = {} }
      end,
      format_context = function()
        return "should not appear"
      end,
    }

    local ok, ctx = pcall(gather, { target_path = nil })

    assert.is_true(ok)
    assert.is_false(called)
    assert.is_nil(ctx.extra:find("should not appear"))
  end)

  it("does not abort context assembly when resolve_deps.resolve raises", function()
    local path = make_tmp_file("return {}\n")

    package.loaded["codetyper.core.llm.shared.resolve_deps"] = {
      resolve = function()
        error("simulated grep subprocess failure")
      end,
      format_context = function()
        return "should not appear"
      end,
    }

    local ok, ctx = pcall(gather, { target_path = path })

    assert.is_true(ok)
    -- readfile() + table.concat drop the trailing newline (see executor_spec.lua).
    assert.are.equal("return {}", ctx.target_content)
    assert.is_nil(ctx.extra:find("should not appear"))
  end)

  it("includes the dependency block stating no importers when the file has none (regression: block present, not omitted)", function()
    local path = make_tmp_file("return {}\n")

    package.loaded["codetyper.core.llm.shared.resolve_deps"] = {
      resolve = function(filepath)
        return { filepath = filepath, imports = {}, importers = {} }
      end,
      format_context = function(deps)
        return "**File dependency context for `" .. deps.filepath .. "`:**\n"
          .. "**No files found that import this file in the project.**\n"
      end,
    }

    local ctx = gather({ target_path = path })

    assert.is_not_nil(ctx.extra:find("File dependency context"))
    assert.is_not_nil(ctx.extra:find("No files found that import this file"))
  end)
end)
