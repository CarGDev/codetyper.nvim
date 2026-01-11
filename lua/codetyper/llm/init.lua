---@mod codetyper.llm LLM interface for Codetyper.nvim

local M = {}

local utils = require("codetyper.utils")

--- Get the appropriate LLM client based on configuration
---@return table LLM client module
function M.get_client()
  local codetyper = require("codetyper")
  local config = codetyper.get_config()

  if config.llm.provider == "claude" then
    return require("codetyper.llm.claude")
  elseif config.llm.provider == "ollama" then
    return require("codetyper.llm.ollama")
  else
    error("Unknown LLM provider: " .. config.llm.provider)
  end
end

--- Generate code from a prompt
---@param prompt string The user's prompt
---@param context table Context information (file content, language, etc.)
---@param callback fun(response: string|nil, error: string|nil) Callback function
function M.generate(prompt, context, callback)
  local client = M.get_client()
  client.generate(prompt, context, callback)
end

--- Build the system prompt for code generation
---@param context table Context information
---@return string System prompt
function M.build_system_prompt(context)
  local prompts = require("codetyper.prompts")
  
  -- Select appropriate system prompt based on context
  local prompt_type = context.prompt_type or "code_generation"
  local system_prompts = prompts.system
  
  local system = system_prompts[prompt_type] or system_prompts.code_generation
  
  -- Substitute variables
  system = system:gsub("{{language}}", context.language or "unknown")
  system = system:gsub("{{filepath}}", context.file_path or "unknown")

  -- Add file content with analysis hints
  if context.file_content and context.file_content ~= "" then
    system = system .. "\n\n===== EXISTING FILE CONTENT (analyze and match this style) =====\n"
    system = system .. context.file_content
    system = system .. "\n===== END OF EXISTING FILE =====\n"
    system = system .. "\nYour generated code MUST follow the exact patterns shown above."
  else
    system = system .. "\n\nThis is a new/empty file. Generate clean, idiomatic " .. (context.language or "code") .. " following best practices."
  end

  return system
end

--- Build context for LLM request
---@param target_path string Path to target file
---@param prompt_type string Type of prompt
---@return table Context object
function M.build_context(target_path, prompt_type)
  local content = utils.read_file(target_path)
  local ext = vim.fn.fnamemodify(target_path, ":e")

  -- Map extension to language
  local lang_map = {
    -- JavaScript/TypeScript
    ts = "TypeScript",
    tsx = "TypeScript React (TSX)",
    js = "JavaScript",
    jsx = "JavaScript React (JSX)",
    mjs = "JavaScript (ESM)",
    cjs = "JavaScript (CommonJS)",
    -- Python
    py = "Python",
    pyw = "Python",
    pyx = "Cython",
    -- Systems languages
    c = "C",
    h = "C Header",
    cpp = "C++",
    hpp = "C++ Header",
    cc = "C++",
    cxx = "C++",
    rs = "Rust",
    go = "Go",
    -- JVM languages
    java = "Java",
    kt = "Kotlin",
    kts = "Kotlin Script",
    scala = "Scala",
    clj = "Clojure",
    -- Web
    html = "HTML",
    css = "CSS",
    scss = "SCSS",
    sass = "Sass",
    less = "Less",
    vue = "Vue",
    svelte = "Svelte",
    -- Scripting
    lua = "Lua",
    rb = "Ruby",
    php = "PHP",
    pl = "Perl",
    sh = "Shell (Bash)",
    bash = "Bash",
    zsh = "Zsh",
    fish = "Fish",
    ps1 = "PowerShell",
    -- .NET
    cs = "C#",
    fs = "F#",
    vb = "Visual Basic",
    -- Data/Config
    json = "JSON",
    yaml = "YAML",
    yml = "YAML",
    toml = "TOML",
    xml = "XML",
    sql = "SQL",
    graphql = "GraphQL",
    -- Other
    swift = "Swift",
    dart = "Dart",
    ex = "Elixir",
    exs = "Elixir Script",
    erl = "Erlang",
    hs = "Haskell",
    ml = "OCaml",
    r = "R",
    jl = "Julia",
    nim = "Nim",
    zig = "Zig",
    v = "V",
    md = "Markdown",
    mdx = "MDX",
  }

  return {
    file_content = content,
    language = lang_map[ext] or ext,
    extension = ext,
    prompt_type = prompt_type,
    file_path = target_path,
  }
end

--- Parse LLM response and extract code
---@param response string Raw LLM response
---@return string Extracted code
function M.extract_code(response)
  local code = response
  
  -- Remove markdown code blocks with language tags (```typescript, ```javascript, etc.)
  code = code:gsub("```%w+%s*\n", "")
  code = code:gsub("```%w+%s*$", "")
  code = code:gsub("^```%w*\n?", "")
  code = code:gsub("\n?```%s*$", "")
  code = code:gsub("\n```\n", "\n")
  code = code:gsub("```", "")
  
  -- Remove common explanation prefixes that LLMs sometimes add
  code = code:gsub("^Here.-:\n", "")
  code = code:gsub("^Here's.-:\n", "")
  code = code:gsub("^This.-:\n", "")
  code = code:gsub("^The following.-:\n", "")
  code = code:gsub("^Below.-:\n", "")
  
  -- Remove common explanation suffixes
  code = code:gsub("\n\nThis code.-$", "")
  code = code:gsub("\n\nThe above.-$", "")
  code = code:gsub("\n\nNote:.-$", "")
  code = code:gsub("\n\nExplanation:.-$", "")
  
  -- Trim leading/trailing whitespace but preserve internal formatting
  code = code:match("^%s*(.-)%s*$") or code

  return code
end

return M
