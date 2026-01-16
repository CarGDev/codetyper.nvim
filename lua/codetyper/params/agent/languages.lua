---@mod codetyper.params.agent.languages Language-specific patterns and configurations
local M = {}

--- Language-specific import patterns
M.import_patterns = {
	-- JavaScript/TypeScript
	javascript = {
		{ pattern = "^%s*import%s+.+%s+from%s+['\"]", multi_line = true },
		{ pattern = "^%s*import%s+['\"]", multi_line = false },
		{ pattern = "^%s*import%s*{", multi_line = true },
		{ pattern = "^%s*import%s*%*", multi_line = true },
		{ pattern = "^%s*export%s+{.+}%s+from%s+['\"]", multi_line = true },
		{ pattern = "^%s*const%s+%w+%s*=%s*require%(['\"]", multi_line = false },
		{ pattern = "^%s*let%s+%w+%s*=%s*require%(['\"]", multi_line = false },
		{ pattern = "^%s*var%s+%w+%s*=%s*require%(['\"]", multi_line = false },
	},
	-- Python
	python = {
		{ pattern = "^%s*import%s+%w", multi_line = false },
		{ pattern = "^%s*from%s+[%w%.]+%s+import%s+", multi_line = true },
	},
	-- Lua
	lua = {
		{ pattern = "^%s*local%s+%w+%s*=%s*require%s*%(?['\"]", multi_line = false },
		{ pattern = "^%s*require%s*%(?['\"]", multi_line = false },
	},
	-- Go
	go = {
		{ pattern = "^%s*import%s+%(?", multi_line = true },
	},
	-- Rust
	rust = {
		{ pattern = "^%s*use%s+", multi_line = true },
		{ pattern = "^%s*extern%s+crate%s+", multi_line = false },
	},
	-- C/C++
	c = {
		{ pattern = "^%s*#include%s*[<\"]", multi_line = false },
	},
	-- Java/Kotlin
	java = {
		{ pattern = "^%s*import%s+", multi_line = false },
	},
	-- Ruby
	ruby = {
		{ pattern = "^%s*require%s+['\"]", multi_line = false },
		{ pattern = "^%s*require_relative%s+['\"]", multi_line = false },
	},
	-- PHP
	php = {
		{ pattern = "^%s*use%s+", multi_line = false },
		{ pattern = "^%s*require%s+['\"]", multi_line = false },
		{ pattern = "^%s*require_once%s+['\"]", multi_line = false },
		{ pattern = "^%s*include%s+['\"]", multi_line = false },
		{ pattern = "^%s*include_once%s+['\"]", multi_line = false },
	},
}

-- Alias common extensions to language configs
M.import_patterns.ts = M.import_patterns.javascript
M.import_patterns.tsx = M.import_patterns.javascript
M.import_patterns.jsx = M.import_patterns.javascript
M.import_patterns.mjs = M.import_patterns.javascript
M.import_patterns.cjs = M.import_patterns.javascript
M.import_patterns.py = M.import_patterns.python
M.import_patterns.cpp = M.import_patterns.c
M.import_patterns.hpp = M.import_patterns.c
M.import_patterns.h = M.import_patterns.c
M.import_patterns.kt = M.import_patterns.java
M.import_patterns.rs = M.import_patterns.rust
M.import_patterns.rb = M.import_patterns.ruby

--- Language-specific comment patterns
M.comment_patterns = {
	lua = { "^%-%-" },
	python = { "^#" },
	javascript = { "^//", "^/%*", "^%*" },
	typescript = { "^//", "^/%*", "^%*" },
	go = { "^//", "^/%*", "^%*" },
	rust = { "^//", "^/%*", "^%*" },
	c = { "^//", "^/%*", "^%*", "^#" },
	java = { "^//", "^/%*", "^%*" },
	ruby = { "^#" },
	php = { "^//", "^/%*", "^%*", "^#" },
}

return M
