---@diagnostic disable: undefined-global
-- Tests for lua/codetyper/config.lua

describe("config", function()
	local config = require("codetyper.config")

	describe("defaults", function()
		local defaults = config.defaults

		it("should have llm configuration", function()
			assert.is_table(defaults.llm)
			assert.equals("claude", defaults.llm.provider)
		end)

		it("should have window configuration", function()
			assert.is_table(defaults.window)
			assert.equals(25, defaults.window.width)
			assert.equals("left", defaults.window.position)
		end)

		it("should have pattern configuration", function()
			assert.is_table(defaults.patterns)
			assert.equals("/@", defaults.patterns.open_tag)
			assert.equals("@/", defaults.patterns.close_tag)
		end)

		it("should have scheduler configuration", function()
			assert.is_table(defaults.scheduler)
			assert.is_boolean(defaults.scheduler.enabled)
			assert.is_boolean(defaults.scheduler.ollama_scout)
			assert.is_number(defaults.scheduler.escalation_threshold)
		end)

		it("should have claude configuration", function()
			assert.is_table(defaults.llm.claude)
			assert.is_truthy(defaults.llm.claude.model)
		end)

		it("should have openai configuration", function()
			assert.is_table(defaults.llm.openai)
			assert.is_truthy(defaults.llm.openai.model)
		end)

		it("should have gemini configuration", function()
			assert.is_table(defaults.llm.gemini)
			assert.is_truthy(defaults.llm.gemini.model)
		end)

		it("should have ollama configuration", function()
			assert.is_table(defaults.llm.ollama)
			assert.is_truthy(defaults.llm.ollama.host)
			assert.is_truthy(defaults.llm.ollama.model)
		end)
	end)

	describe("merge", function()
		it("should merge user config with defaults", function()
			local user_config = {
				llm = {
					provider = "openai",
				},
			}

			local merged = config.merge(user_config)

			-- User value should override
			assert.equals("openai", merged.llm.provider)
			-- Other defaults should be preserved
			assert.equals(25, merged.window.width)
		end)

		it("should deep merge nested tables", function()
			local user_config = {
				llm = {
					claude = {
						model = "claude-opus-4",
					},
				},
			}

			local merged = config.merge(user_config)

			-- User value should override
			assert.equals("claude-opus-4", merged.llm.claude.model)
			-- Provider default should be preserved
			assert.equals("claude", merged.llm.provider)
		end)

		it("should handle empty user config", function()
			local merged = config.merge({})

			assert.equals("claude", merged.llm.provider)
			assert.equals(25, merged.window.width)
		end)

		it("should handle nil user config", function()
			local merged = config.merge(nil)

			assert.equals("claude", merged.llm.provider)
		end)
	end)

	describe("validate", function()
		it("should return true for valid config", function()
			local valid_config = config.defaults
			local is_valid, err = config.validate(valid_config)

			assert.is_true(is_valid)
			assert.is_nil(err)
		end)

		it("should validate provider value", function()
			local invalid_config = vim.tbl_deep_extend("force", {}, config.defaults)
			invalid_config.llm.provider = "invalid_provider"

			local is_valid, err = config.validate(invalid_config)

			assert.is_false(is_valid)
			assert.is_truthy(err)
		end)

		it("should validate window width range", function()
			local invalid_config = vim.tbl_deep_extend("force", {}, config.defaults)
			invalid_config.window.width = 101 -- Over 100%

			local is_valid, err = config.validate(invalid_config)

			assert.is_false(is_valid)
		end)

		it("should validate window position", function()
			local invalid_config = vim.tbl_deep_extend("force", {}, config.defaults)
			invalid_config.window.position = "center" -- Invalid

			local is_valid, err = config.validate(invalid_config)

			assert.is_false(is_valid)
		end)

		it("should validate scheduler threshold range", function()
			local invalid_config = vim.tbl_deep_extend("force", {}, config.defaults)
			invalid_config.scheduler.escalation_threshold = 1.5 -- Over 1.0

			local is_valid, err = config.validate(invalid_config)

			assert.is_false(is_valid)
		end)
	end)
end)
