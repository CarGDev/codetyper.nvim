--- Tests for coder file ignore logic
describe("coder file ignore logic", function()
	-- Directories to ignore
	local ignored_directories = {
		".git",
		".coder",
		".claude",
		".vscode",
		".idea",
		"node_modules",
		"vendor",
		"dist",
		"build",
		"target",
		"__pycache__",
		".cache",
		".npm",
		".yarn",
		"coverage",
		".next",
		".nuxt",
		".svelte-kit",
		"out",
		"bin",
		"obj",
	}

	-- Files to ignore
	local ignored_files = {
		".gitignore",
		".gitattributes",
		"package-lock.json",
		"yarn.lock",
		".env",
		".eslintrc",
		"tsconfig.json",
		"README.md",
		"LICENSE",
		"Makefile",
	}

	local function is_in_ignored_directory(filepath)
		for _, dir in ipairs(ignored_directories) do
			if filepath:match("/" .. dir .. "/") or filepath:match("/" .. dir .. "$") then
				return true
			end
			if filepath:match("^" .. dir .. "/") then
				return true
			end
		end
		return false
	end

	local function should_ignore_for_coder(filepath)
		local filename = vim.fn.fnamemodify(filepath, ":t")

		for _, ignored in ipairs(ignored_files) do
			if filename == ignored then
				return true
			end
		end

		if filename:match("^%.") then
			return true
		end

		if is_in_ignored_directory(filepath) then
			return true
		end

		return false
	end

	describe("ignored directories", function()
		it("should ignore files in node_modules", function()
			assert.is_true(should_ignore_for_coder("/project/node_modules/lodash/index.js"))
			assert.is_true(should_ignore_for_coder("/project/node_modules/react/index.js"))
		end)

		it("should ignore files in .git", function()
			assert.is_true(should_ignore_for_coder("/project/.git/config"))
			assert.is_true(should_ignore_for_coder("/project/.git/hooks/pre-commit"))
		end)

		it("should ignore files in .coder", function()
			assert.is_true(should_ignore_for_coder("/project/.coder/brain/meta.json"))
		end)

		it("should ignore files in vendor", function()
			assert.is_true(should_ignore_for_coder("/project/vendor/autoload.php"))
		end)

		it("should ignore files in dist/build", function()
			assert.is_true(should_ignore_for_coder("/project/dist/bundle.js"))
			assert.is_true(should_ignore_for_coder("/project/build/output.js"))
		end)

		it("should ignore files in __pycache__", function()
			assert.is_true(should_ignore_for_coder("/project/__pycache__/module.cpython-39.pyc"))
		end)

		it("should NOT ignore regular source files", function()
			assert.is_false(should_ignore_for_coder("/project/src/index.ts"))
			assert.is_false(should_ignore_for_coder("/project/lib/utils.lua"))
			assert.is_false(should_ignore_for_coder("/project/app/main.py"))
		end)
	end)

	describe("ignored files", function()
		it("should ignore .gitignore", function()
			assert.is_true(should_ignore_for_coder("/project/.gitignore"))
		end)

		it("should ignore lock files", function()
			assert.is_true(should_ignore_for_coder("/project/package-lock.json"))
			assert.is_true(should_ignore_for_coder("/project/yarn.lock"))
		end)

		it("should ignore config files", function()
			assert.is_true(should_ignore_for_coder("/project/tsconfig.json"))
			assert.is_true(should_ignore_for_coder("/project/.eslintrc"))
		end)

		it("should ignore .env files", function()
			assert.is_true(should_ignore_for_coder("/project/.env"))
		end)

		it("should ignore README and LICENSE", function()
			assert.is_true(should_ignore_for_coder("/project/README.md"))
			assert.is_true(should_ignore_for_coder("/project/LICENSE"))
		end)

		it("should ignore hidden/dot files", function()
			assert.is_true(should_ignore_for_coder("/project/.hidden"))
			assert.is_true(should_ignore_for_coder("/project/.secret"))
		end)

		it("should NOT ignore regular source files", function()
			assert.is_false(should_ignore_for_coder("/project/src/app.ts"))
			assert.is_false(should_ignore_for_coder("/project/components/Button.tsx"))
			assert.is_false(should_ignore_for_coder("/project/utils/helpers.js"))
		end)
	end)

	describe("edge cases", function()
		it("should handle nested node_modules", function()
			assert.is_true(should_ignore_for_coder("/project/packages/core/node_modules/dep/index.js"))
		end)

		it("should handle files named like directories but not in them", function()
			-- A file named "node_modules.md" in root should be ignored (starts with .)
			-- But a file in a folder that contains "node" should NOT be ignored
			assert.is_false(should_ignore_for_coder("/project/src/node_utils.ts"))
		end)

		it("should handle relative paths", function()
			assert.is_true(should_ignore_for_coder("node_modules/lodash/index.js"))
			assert.is_false(should_ignore_for_coder("src/index.ts"))
		end)
	end)
end)
