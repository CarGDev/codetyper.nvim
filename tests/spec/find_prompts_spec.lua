--- Tests for /@ ... @/ inline prompt tag parsing (pure function, no LLM/network).

local find_prompts = require("codetyper.parser.find_prompts")

describe("find_prompts", function()
  it("parses a single-line tag", function()
    local content = table.concat({
      "local x = 1",
      "/@ add a comment here @/",
      "local y = 2",
    }, "\n")

    local prompts = find_prompts(content, "/@", "@/")

    assert.are.equal(1, #prompts)
    assert.are.equal(2, prompts[1].start_line)
    assert.are.equal(2, prompts[1].end_line)
    assert.are.equal(" add a comment here ", prompts[1].content)
  end)

  it("parses a multi-line tag", function()
    local content = table.concat({
      "local x = 1",
      "/@",
      "implement a function that",
      "adds error handling",
      "@/",
      "local y = 2",
    }, "\n")

    local prompts = find_prompts(content, "/@", "@/")

    assert.are.equal(1, #prompts)
    assert.are.equal(2, prompts[1].start_line)
    assert.are.equal(5, prompts[1].end_line)
    assert.are.equal(
      "\nimplement a function that\nadds error handling\n",
      prompts[1].content
    )
  end)

  it("parses multiple tags in the same buffer", function()
    local content = table.concat({
      "/@ first prompt @/",
      "local a = 1",
      "/@ second prompt @/",
    }, "\n")

    local prompts = find_prompts(content, "/@", "@/")

    assert.are.equal(2, #prompts)
    assert.are.equal(" first prompt ", prompts[1].content)
    assert.are.equal(" second prompt ", prompts[2].content)
  end)

  it("returns no prompts when tags are absent", function()
    local content = "local x = 1\nlocal y = 2"
    local prompts = find_prompts(content, "/@", "@/")
    assert.are.equal(0, #prompts)
  end)

  it("does not close a prompt on an unclosed opening tag", function()
    local content = "/@ never closed"
    local prompts = find_prompts(content, "/@", "@/")
    assert.are.equal(0, #prompts)
  end)
end)
