---@diagnostic disable: undefined-global
-- Tests for lua/codetyper/agent/logs.lua

describe("logs", function()
	local logs

	before_each(function()
		-- Reset module state before each test
		package.loaded["codetyper.agent.logs"] = nil
		logs = require("codetyper.agent.logs")
	end)

	describe("log", function()
		it("should add entry to log", function()
			logs.log("info", "test message")

			local entries = logs.get_entries()
			assert.equals(1, #entries)
			assert.equals("info", entries[1].level)
			assert.equals("test message", entries[1].message)
		end)

		it("should include timestamp", function()
			logs.log("info", "test")

			local entries = logs.get_entries()
			assert.is_truthy(entries[1].timestamp)
			assert.is_true(entries[1].timestamp:match("%d+:%d+:%d+"))
		end)

		it("should include optional data", function()
			logs.log("info", "test", { key = "value" })

			local entries = logs.get_entries()
			assert.equals("value", entries[1].data.key)
		end)
	end)

	describe("info", function()
		it("should log with info level", function()
			logs.info("info message")

			local entries = logs.get_entries()
			assert.equals("info", entries[1].level)
		end)
	end)

	describe("debug", function()
		it("should log with debug level", function()
			logs.debug("debug message")

			local entries = logs.get_entries()
			assert.equals("debug", entries[1].level)
		end)
	end)

	describe("error", function()
		it("should log with error level", function()
			logs.error("error message")

			local entries = logs.get_entries()
			assert.equals("error", entries[1].level)
			assert.is_true(entries[1].message:match("ERROR"))
		end)
	end)

	describe("warning", function()
		it("should log with warning level", function()
			logs.warning("warning message")

			local entries = logs.get_entries()
			assert.equals("warning", entries[1].level)
			assert.is_true(entries[1].message:match("WARN"))
		end)
	end)

	describe("request", function()
		it("should log API request", function()
			logs.request("claude", "claude-sonnet-4", 1000)

			local entries = logs.get_entries()
			assert.equals("request", entries[1].level)
			assert.is_true(entries[1].message:match("CLAUDE"))
			assert.is_true(entries[1].message:match("claude%-sonnet%-4"))
		end)

		it("should store provider info", function()
			logs.request("openai", "gpt-4")

			local provider, model = logs.get_provider_info()
			assert.equals("openai", provider)
			assert.equals("gpt-4", model)
		end)
	end)

	describe("response", function()
		it("should log API response with token counts", function()
			logs.response(500, 200, "end_turn")

			local entries = logs.get_entries()
			assert.equals("response", entries[1].level)
			assert.is_true(entries[1].message:match("500"))
			assert.is_true(entries[1].message:match("200"))
		end)

		it("should accumulate token totals", function()
			logs.response(100, 50)
			logs.response(200, 100)

			local prompt_tokens, response_tokens = logs.get_token_totals()
			assert.equals(300, prompt_tokens)
			assert.equals(150, response_tokens)
		end)
	end)

	describe("tool", function()
		it("should log tool execution", function()
			logs.tool("read_file", "start", "/path/to/file.lua")

			local entries = logs.get_entries()
			assert.equals("tool", entries[1].level)
			assert.is_true(entries[1].message:match("read_file"))
		end)

		it("should show correct status icons", function()
			logs.tool("write_file", "success", "file created")
			local entries = logs.get_entries()
			assert.is_true(entries[1].message:match("OK"))

			logs.tool("bash", "error", "command failed")
			entries = logs.get_entries()
			assert.is_true(entries[2].message:match("ERR"))
		end)
	end)

	describe("thinking", function()
		it("should log thinking step", function()
			logs.thinking("Analyzing code structure")

			local entries = logs.get_entries()
			assert.equals("debug", entries[1].level)
			assert.is_true(entries[1].message:match("> Analyzing"))
		end)
	end)

	describe("add", function()
		it("should add entry using type field", function()
			logs.add({ type = "info", message = "test message" })

			local entries = logs.get_entries()
			assert.equals(1, #entries)
			assert.equals("info", entries[1].level)
		end)

		it("should handle clear type", function()
			logs.info("test")
			logs.add({ type = "clear" })

			local entries = logs.get_entries()
			assert.equals(0, #entries)
		end)
	end)

	describe("listeners", function()
		it("should notify listeners on new entries", function()
			local received = {}
			logs.add_listener(function(entry)
				table.insert(received, entry)
			end)

			logs.info("test message")

			assert.equals(1, #received)
			assert.equals("info", received[1].level)
		end)

		it("should support multiple listeners", function()
			local count = 0
			logs.add_listener(function() count = count + 1 end)
			logs.add_listener(function() count = count + 1 end)

			logs.info("test")

			assert.equals(2, count)
		end)

		it("should remove listener by ID", function()
			local count = 0
			local id = logs.add_listener(function() count = count + 1 end)

			logs.info("test1")
			logs.remove_listener(id)
			logs.info("test2")

			assert.equals(1, count)
		end)
	end)

	describe("clear", function()
		it("should clear all entries", function()
			logs.info("test1")
			logs.info("test2")
			logs.clear()

			assert.equals(0, #logs.get_entries())
		end)

		it("should reset token totals", function()
			logs.response(100, 50)
			logs.clear()

			local prompt, response = logs.get_token_totals()
			assert.equals(0, prompt)
			assert.equals(0, response)
		end)

		it("should notify listeners of clear", function()
			local cleared = false
			logs.add_listener(function(entry)
				if entry.level == "clear" then
					cleared = true
				end
			end)

			logs.clear()

			assert.is_true(cleared)
		end)
	end)

	describe("format_entry", function()
		it("should format entry for display", function()
			logs.info("test message")
			local entry = logs.get_entries()[1]

			local formatted = logs.format_entry(entry)

			assert.is_true(formatted:match("%[%d+:%d+:%d+%]"))
			assert.is_true(formatted:match("i")) -- info prefix
			assert.is_true(formatted:match("test message"))
		end)

		it("should use correct level prefixes", function()
			local prefixes = {
				{ level = "info", prefix = "i" },
				{ level = "debug", prefix = "%." },
				{ level = "request", prefix = ">" },
				{ level = "response", prefix = "<" },
				{ level = "tool", prefix = "T" },
				{ level = "error", prefix = "!" },
			}

			for _, test in ipairs(prefixes) do
				local entry = {
					timestamp = "12:00:00",
					level = test.level,
					message = "test",
				}
				local formatted = logs.format_entry(entry)
				assert.is_true(formatted:match(test.prefix), "Missing prefix for " .. test.level)
			end
		end)
	end)

	describe("estimate_tokens", function()
		it("should estimate tokens from text", function()
			local text = "This is a test string for token estimation."
			local tokens = logs.estimate_tokens(text)

			-- Rough estimate: ~4 chars per token
			assert.is_true(tokens > 0)
			assert.is_true(tokens < #text) -- Should be less than character count
		end)

		it("should handle empty string", function()
			local tokens = logs.estimate_tokens("")
			assert.equals(0, tokens)
		end)
	end)
end)
