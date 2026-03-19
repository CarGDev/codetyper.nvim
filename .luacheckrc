std = "luajit"

globals = {
  "vim",
  "_",
}

read_globals = {
  "describe",
  "it",
  "before_each",
  "after_each",
  "assert",
}

max_line_length = false

ignore = {
  "211", -- unused function
  "212", -- unused argument
  "213", -- unused loop variable
  "311", -- value assigned is unused
  "312", -- value of argument is unused
  "314", -- value of field is overwritten before use
  "411", -- variable redefines
  "421", -- shadowing local variable
  "431", -- shadowing upvalue
  "432", -- shadowing upvalue argument
  "511", -- unreachable code
  "542", -- empty if branch
  "631", -- max_line_length
}

files["lua/codetyper/adapters/nvim/autocmds.lua"] = {
  ignore = { "111", "113", "131", "231", "241" }, -- TODO: fix undefined refs and dead stores
}

files["lua/codetyper/adapters/nvim/ui/context_modal.lua"] = {
  ignore = { "113" }, -- TODO: fix undefined run_project_inspect
}

files["lua/codetyper/core/scheduler/loop.lua"] = {
  ignore = { "241" }, -- mutated but never accessed
}

exclude_files = {
  ".luarocks",
  ".luacache",
}
