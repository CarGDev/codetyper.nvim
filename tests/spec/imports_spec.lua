--- Tests for deterministic, safe import planning and insertion.

local imports = require("codetyper.core.agent.tools.imports")
local add_import = require("codetyper.core.agent.tools.add_import")
local inject = require("codetyper.inject.inject")

local function make_root()
  local root = vim.fn.tempname()
  assert.are.equal(1, vim.fn.mkdir(root, "p"))
  return root
end

local function write_file(root, relative_path, content)
  local path = root .. "/" .. relative_path
  local parent = vim.fn.fnamemodify(path, ":h")
  vim.fn.mkdir(parent, "p")
  local file = assert(io.open(path, "wb"))
  file:write(content)
  file:close()
  return path
end

local function read_file(path)
  local file = assert(io.open(path, "rb"))
  local content = file:read("*all")
  file:close()
  return content
end

local function make_buffer(path, lines)
  local bufnr = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(bufnr, path)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  return bufnr
end

local function index_of(lines, value)
  for index, line in ipairs(lines) do
    if line == value then
      return index
    end
  end
  return nil
end

describe("import planner", function()
  it("places declarations after language headers and package metadata", function()
    local cases = {
      {
        path = "src/app.js",
        statement = 'import { value } from "pkg";',
        content = '#!/usr/bin/env node\n// vim: set ft=javascript:\n"use strict";\n\nconst run = () => true;\n',
        header = "#!/usr/bin/env node",
        body = "const run = () => true;",
      },
      {
        path = "src/app.py",
        statement = "from pathlib import Path",
        content = '#!/usr/bin/env python3\n# -*- coding: utf-8 -*-\n"""Module documentation."""\n\nvalue = 1\n',
        header = '"""Module documentation."""',
        body = "value = 1",
      },
      {
        path = "lua/app.lua",
        statement = 'local json = require("json")',
        content = "#!/usr/bin/env lua\n-- modeline\n\nlocal value = true\n",
        header = "-- modeline",
        body = "local value = true",
      },
      {
        path = "cmd/app.go",
        statement = 'import "fmt"',
        content = "// generated header\npackage main\n\nfunc main() {}\n",
        header = "package main",
        body = "func main() {}",
      },
      {
        path = "src/app.rs",
        statement = "use std::path::Path;",
        content = "#![allow(dead_code)]\n\nfn main() {}\n",
        header = "#![allow(dead_code)]",
        body = "fn main() {}",
      },
      {
        path = "src/app.c",
        statement = '#include "app.h"',
        content = "#pragma once\n\nint main(void) { return 0; }\n",
        header = "#pragma once",
        body = "int main(void) { return 0; }",
      },
      {
        path = "src/App.java",
        statement = "import java.util.List;",
        content = "// license header\npackage example;\n\nclass App {}\n",
        header = "package example;",
        body = "class App {}",
      },
      {
        path = "lib/app.rb",
        statement = 'require "json"',
        content = "# frozen_string_literal: true\n\nclass App\nend\n",
        header = "# frozen_string_literal: true",
        body = "class App",
      },
      {
        path = "src/App.php",
        statement = "use App\\Support\\Value;",
        content = "<?php\ndeclare(strict_types=1);\n\nnamespace App;\n\nfinal class App {}\n",
        header = "namespace App;",
        body = "final class App {}",
      },
    }

    local root = make_root()
    for _, case in ipairs(cases) do
      local plan, err = imports.plan({
        root = root,
        path = case.path,
        statement = case.statement,
        content = case.content,
      })

      assert.is_nil(err)
      assert.are.equal("planned", plan.status)
      assert.are.equal(1, plan.imports_added)
      assert.are.equal(case.statement, plan.statement)
      assert.is_truthy(index_of(plan.lines, case.header))
      assert.is_truthy(index_of(plan.lines, case.statement))
      assert.is_truthy(index_of(plan.lines, case.body))
      assert.is_true(index_of(plan.lines, case.statement) < index_of(plan.lines, case.body))
    end
    vim.fn.delete(root, "rf")
  end)

  it("plans a pure result without mutating supplied content", function()
    local original = "# header\nvalue = 1\n"
    local plan = assert(imports.plan({
      root = make_root(),
      path = "app.py",
      statement = "import os",
      content = original,
    }))

    assert.are.equal("# header\nvalue = 1\n", original)
    assert.are.equal("import os", plan.lines[2])
    assert.are.equal("value = 1", plan.lines[3])
  end)

  it("deduplicates semantically equivalent declarations as a no-op", function()
    local root = make_root()
    local path = write_file(root, "app.js", "import { value } from 'pkg';\nconsole.log(value);\n")
    local before = read_file(path)

    local result = add_import.run({
      root = root,
      path = "app.js",
      statement = 'import {value} from "pkg"',
    })

    assert.are.equal("available", result.status)
    assert.are.equal("noop", result.data.action)
    assert.are.equal(0, result.data.imports_added)
    assert.are.equal(before, read_file(path))
    vim.fn.delete(root, "rf")
  end)

  it("preserves CRLF files and deduplicates Python declaration formatting", function()
    local root = make_root()
    local path = write_file(root, "app.py", "from pathlib import Path;\r\nvalue = 1\r\n")

    local result = add_import.run({
      root = root,
      path = "app.py",
      statement = "from pathlib import Path",
    })

    assert.are.equal("noop", result.data.action)
    assert.are.equal("from pathlib import Path;\r\nvalue = 1\r\n", read_file(path))
    vim.fn.delete(root, "rf")
  end)

  it("adds to an existing Go import block without creating a second block", function()
    local root = make_root()
    local path = write_file(root, "main.go", 'package main\n\nimport (\n\t"fmt"\n)\n\nfunc main() {}\n')

    local result = add_import.run({
      root = root,
      path = "main.go",
      statement = 'import "os"',
    })

    assert.are.equal("available", result.status)
    assert.are.equal("inserted", result.data.action)
    local content = read_file(path)
    assert.is_truthy(content:find('\t"os"', 1, true))
    assert.are.equal(1, select(2, content:gsub("import%s*%(", "")))
    vim.fn.delete(root, "rf")
  end)

  it("deduplicates an existing C include instead of treating it as a comment", function()
    local root = make_root()
    local path = write_file(root, "app.c", '#include "app.h"\nint main(void) { return 0; }\n')

    local result = add_import.run({
      root = root,
      path = "app.c",
      statement = '#include "app.h"',
    })

    assert.are.equal("noop", result.data.action)
    assert.are.equal('#include "app.h"\nint main(void) { return 0; }\n', read_file(path))
    vim.fn.delete(root, "rf")
  end)

  it("mutates an open buffer but leaves its on-disk file unchanged", function()
    local root = make_root()
    local path = write_file(root, "app.py", "value = 1\n")
    local bufnr = make_buffer(path, { "# unsaved header", "value = 1" })

    local plan = assert(imports.plan({
      root = root,
      path = "app.py",
      bufnr = bufnr,
      statement = "import os",
    }))
    local applied = assert(imports.apply(plan))

    assert.are.equal("inserted", applied.action)
    assert.are.same({ "# unsaved header", "import os", "value = 1" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    assert.are.equal("value = 1\n", read_file(path))
    vim.api.nvim_buf_delete(bufnr, { force = true })
    vim.fn.delete(root, "rf")
  end)

  it("shares the planner with injection and keeps the body at its requested location", function()
    local root = make_root()
    local path = write_file(root, "app.py", "#!/usr/bin/env python3\n\nvalue = 1\n")
    local bufnr = make_buffer(path, { "#!/usr/bin/env python3", "", "value = 1" })

    local result = inject.inject(bufnr, "from pathlib import Path\nprint(Path.cwd())", {
      root = root,
      strategy = "append",
    })

    assert.are.equal(1, result.imports_added)
    assert.is_true(result.imports_merged)
    assert.are.same({
      "#!/usr/bin/env python3",
      "",
      "from pathlib import Path",
      "value = 1",
      "print(Path.cwd())",
    }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    vim.api.nvim_buf_delete(bufnr, { force = true })
    vim.fn.delete(root, "rf")
  end)

  it("adjusts a replacement range when imports are inserted before it", function()
    local root = make_root()
    local path = write_file(root, "app.py", "first = 1\nsecond = 2\nthird = 3\n")
    local bufnr = make_buffer(path, { "first = 1", "second = 2", "third = 3" })

    local result = inject.inject(bufnr, "import os\nreplacement = os.name", {
      root = root,
      strategy = "replace",
      range = { start_line = 2, end_line = 2 },
    })

    assert.are.equal(1, result.imports_added)
    assert.are.same(
      { "import os", "first = 1", "replacement = os.name", "third = 3" },
      vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    )
    vim.api.nvim_buf_delete(bufnr, { force = true })
    vim.fn.delete(root, "rf")
  end)

  it("does not extract an import-like body line from the injection path", function()
    local root = make_root()
    local path = write_file(root, "app.py", "value = 1\n")
    local bufnr = make_buffer(path, { "value = 1" })

    local result = inject.inject(bufnr, 'print("before")\nimport os', {
      root = root,
      strategy = "append",
    })

    assert.are.equal(0, result.imports_added)
    assert.are.same({ "value = 1", 'print("before")', "import os" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    vim.api.nvim_buf_delete(bufnr, { force = true })
    vim.fn.delete(root, "rf")
  end)

  it("prefers an open named buffer when the file target has unsaved changes", function()
    local root = make_root()
    local path = write_file(root, "app.lua", "local value = 1\n")
    local bufnr = make_buffer(path, { "-- unsaved", "local value = 2" })

    local result = add_import.run({
      root = root,
      path = "app.lua",
      statement = 'local json = require("json")',
    })

    assert.are.equal("inserted", result.data.action)
    assert.are.same(
      { "-- unsaved", 'local json = require("json")', "local value = 2" },
      vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    )
    assert.are.equal("local value = 1\n", read_file(path))
    vim.api.nvim_buf_delete(bufnr, { force = true })
    vim.fn.delete(root, "rf")
  end)

  it("rejects traversal, documentation, unsupported, malformed, and multiline inputs without mutation", function()
    local root = make_root()
    local path = write_file(root, "app.py", "value = 1\n")
    local before = read_file(path)
    local cases = {
      { path = "../outside.py", statement = "import os" },
      { path = "README.md", statement = "import os" },
      { path = "data.txt", statement = "import os" },
      { path = "app.py", statement = "import os\nimport sys" },
      { path = "app.py", statement = "from pathlib import" },
      { path = "/tmp/outside.py", statement = "import os" },
      { path = "C:/outside.py", statement = "import os" },
    }

    for _, case in ipairs(cases) do
      local result = add_import.run({ root = root, path = case.path, statement = case.statement })
      assert.are.equal("error", result.status)
      assert.is_string(result.error)
      assert.is_true(#result.error <= 256)
      assert.are.equal(before, read_file(path))
    end
    vim.fn.delete(root, "rf")
  end)

  it("rejects documentation-named files even when their extension is a code extension", function()
    local root = make_root()
    local path = write_file(root, "README.py", "This is documentation, not a Python module.\n")
    local before = read_file(path)

    local result = add_import.run({ root = root, path = "README.py", statement = "import os" })

    assert.are.equal("error", result.status)
    assert.are.equal(before, read_file(path))
    vim.fn.delete(root, "rf")
  end)

  it("rejects remote and escaping module references", function()
    local root = make_root()
    local path = write_file(root, "app.js", "console.log(1);\n")
    local before = read_file(path)
    local statements = {
      'import "https://example.invalid/module.js"',
      'import "../../outside.js"',
    }

    for _, statement in ipairs(statements) do
      local result = add_import.run({ root = root, path = "app.js", statement = statement })
      assert.are.equal("error", result.status)
      assert.are.equal(before, read_file(path))
    end
    vim.fn.delete(root, "rf")
  end)

  it("rejects malformed declaration content for each structured syntax", function()
    local root = make_root()
    local files = {
      { path = "app.go", statement = 'import bad; exec "fmt"' },
      { path = "app.php", statement = "use App\\Support\\Value();" },
      { path = "app.js", statement = 'import value; globalThis.x from "pkg"' },
      { path = "app.c", statement = "#include <../../secret.h>" },
    }

    for _, case in ipairs(files) do
      local path = write_file(root, case.path, "value = 1\n")
      local before = read_file(path)
      local result = add_import.run({ root = root, path = case.path, statement = case.statement })
      assert.are.equal("error", result.status)
      assert.are.equal(before, read_file(path))
    end
    vim.fn.delete(root, "rf")
  end)
end)
