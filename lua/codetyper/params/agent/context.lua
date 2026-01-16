---@mod codetyper.params.agent.context Parameters for context building
local M = {}

--- Common ignore patterns
M.ignore_patterns = {
	"^%.", -- Hidden files/dirs
	"node_modules",
	"%.git$",
	"__pycache__",
	"%.pyc$",
	"target", -- Rust
	"build",
	"dist",
	"%.o$",
	"%.a$",
	"%.so$",
	"%.min%.",
	"%.map$",
}

--- Key files that are important for understanding the project
M.important_files = {
	["package.json"] = "Node.js project config",
	["Cargo.toml"] = "Rust project config",
	["go.mod"] = "Go module config",
	["pyproject.toml"] = "Python project config",
	["setup.py"] = "Python setup config",
	["Makefile"] = "Build configuration",
	["CMakeLists.txt"] = "CMake config",
	[".gitignore"] = "Git ignore patterns",
	["README.md"] = "Project documentation",
	["init.lua"] = "Neovim plugin entry",
	["plugin.lua"] = "Neovim plugin config",
}

--- Project type detection indicators
M.indicators = {
	["package.json"] = { type = "node", language = "javascript/typescript" },
	["Cargo.toml"] = { type = "rust", language = "rust" },
	["go.mod"] = { type = "go", language = "go" },
	["pyproject.toml"] = { type = "python", language = "python" },
	["setup.py"] = { type = "python", language = "python" },
	["Gemfile"] = { type = "ruby", language = "ruby" },
	["pom.xml"] = { type = "maven", language = "java" },
	["build.gradle"] = { type = "gradle", language = "java/kotlin" },
}

return M
