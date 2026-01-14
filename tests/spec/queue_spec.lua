---@diagnostic disable: undefined-global
-- Tests for lua/codetyper/agent/queue.lua

describe("queue", function()
	local queue

	before_each(function()
		-- Reset module state before each test
		package.loaded["codetyper.agent.queue"] = nil
		queue = require("codetyper.agent.queue")
	end)

	describe("generate_id", function()
		it("should generate unique IDs", function()
			local id1 = queue.generate_id()
			local id2 = queue.generate_id()

			assert.is_not.equals(id1, id2)
			assert.is_true(id1:match("^evt_"))
			assert.is_true(id2:match("^evt_"))
		end)
	end)

	describe("hash_content", function()
		it("should generate consistent hashes", function()
			local content = "test content"
			local hash1 = queue.hash_content(content)
			local hash2 = queue.hash_content(content)

			assert.equals(hash1, hash2)
		end)

		it("should generate different hashes for different content", function()
			local hash1 = queue.hash_content("content A")
			local hash2 = queue.hash_content("content B")

			assert.is_not.equals(hash1, hash2)
		end)
	end)

	describe("enqueue", function()
		it("should add event to queue", function()
			local event = {
				bufnr = 1,
				prompt_content = "test prompt",
				target_path = "/test/file.lua",
				range = { start_line = 1, end_line = 1 },
			}

			local enqueued = queue.enqueue(event)

			assert.is_not_nil(enqueued.id)
			assert.equals("pending", enqueued.status)
			assert.equals(1, queue.size())
		end)

		it("should set default priority to 2", function()
			local event = {
				bufnr = 1,
				prompt_content = "test prompt",
				target_path = "/test/file.lua",
				range = { start_line = 1, end_line = 1 },
			}

			local enqueued = queue.enqueue(event)

			assert.equals(2, enqueued.priority)
		end)

		it("should maintain priority order", function()
			queue.enqueue({
				bufnr = 1,
				prompt_content = "low priority",
				target_path = "/test/file.lua",
				priority = 3,
				range = { start_line = 1, end_line = 1 },
			})

			queue.enqueue({
				bufnr = 1,
				prompt_content = "high priority",
				target_path = "/test/file.lua",
				priority = 1,
				range = { start_line = 1, end_line = 1 },
			})

			local first = queue.dequeue()
			assert.equals("high priority", first.prompt_content)
		end)

		it("should generate content hash automatically", function()
			local event = {
				bufnr = 1,
				prompt_content = "test prompt",
				target_path = "/test/file.lua",
				range = { start_line = 1, end_line = 1 },
			}

			local enqueued = queue.enqueue(event)

			assert.is_not_nil(enqueued.content_hash)
		end)
	end)

	describe("dequeue", function()
		it("should return nil when queue is empty", function()
			local event = queue.dequeue()
			assert.is_nil(event)
		end)

		it("should return and mark event as processing", function()
			queue.enqueue({
				bufnr = 1,
				prompt_content = "test",
				target_path = "/test/file.lua",
				range = { start_line = 1, end_line = 1 },
			})

			local event = queue.dequeue()

			assert.is_not_nil(event)
			assert.equals("processing", event.status)
		end)

		it("should skip non-pending events", function()
			local evt1 = queue.enqueue({
				bufnr = 1,
				prompt_content = "first",
				target_path = "/test/file.lua",
				range = { start_line = 1, end_line = 1 },
			})

			queue.enqueue({
				bufnr = 1,
				prompt_content = "second",
				target_path = "/test/file.lua",
				range = { start_line = 1, end_line = 1 },
			})

			-- Mark first as completed
			queue.complete(evt1.id)

			local event = queue.dequeue()
			assert.equals("second", event.prompt_content)
		end)
	end)

	describe("peek", function()
		it("should return next pending without removing", function()
			queue.enqueue({
				bufnr = 1,
				prompt_content = "test",
				target_path = "/test/file.lua",
				range = { start_line = 1, end_line = 1 },
			})

			local event1 = queue.peek()
			local event2 = queue.peek()

			assert.is_not_nil(event1)
			assert.equals(event1.id, event2.id)
			assert.equals("pending", event1.status)
		end)
	end)

	describe("get", function()
		it("should return event by ID", function()
			local enqueued = queue.enqueue({
				bufnr = 1,
				prompt_content = "test",
				target_path = "/test/file.lua",
				range = { start_line = 1, end_line = 1 },
			})

			local event = queue.get(enqueued.id)

			assert.is_not_nil(event)
			assert.equals(enqueued.id, event.id)
		end)

		it("should return nil for unknown ID", function()
			local event = queue.get("unknown_id")
			assert.is_nil(event)
		end)
	end)

	describe("update_status", function()
		it("should update event status", function()
			local enqueued = queue.enqueue({
				bufnr = 1,
				prompt_content = "test",
				target_path = "/test/file.lua",
				range = { start_line = 1, end_line = 1 },
			})

			local success = queue.update_status(enqueued.id, "completed")

			assert.is_true(success)
			assert.equals("completed", queue.get(enqueued.id).status)
		end)

		it("should return false for unknown ID", function()
			local success = queue.update_status("unknown_id", "completed")
			assert.is_false(success)
		end)

		it("should merge extra fields", function()
			local enqueued = queue.enqueue({
				bufnr = 1,
				prompt_content = "test",
				target_path = "/test/file.lua",
				range = { start_line = 1, end_line = 1 },
			})

			queue.update_status(enqueued.id, "completed", { error = "test error" })

			local event = queue.get(enqueued.id)
			assert.equals("test error", event.error)
		end)
	end)

	describe("cancel_for_buffer", function()
		it("should cancel all pending events for buffer", function()
			queue.enqueue({
				bufnr = 1,
				prompt_content = "buffer 1 - first",
				target_path = "/test/file.lua",
				range = { start_line = 1, end_line = 1 },
			})

			queue.enqueue({
				bufnr = 1,
				prompt_content = "buffer 1 - second",
				target_path = "/test/file.lua",
				range = { start_line = 1, end_line = 1 },
			})

			queue.enqueue({
				bufnr = 2,
				prompt_content = "buffer 2",
				target_path = "/test/file2.lua",
				range = { start_line = 1, end_line = 1 },
			})

			local cancelled = queue.cancel_for_buffer(1)

			assert.equals(2, cancelled)
			assert.equals(1, queue.pending_count())
		end)
	end)

	describe("stats", function()
		it("should return correct statistics", function()
			queue.enqueue({
				bufnr = 1,
				prompt_content = "pending",
				target_path = "/test/file.lua",
				range = { start_line = 1, end_line = 1 },
			})

			local evt = queue.enqueue({
				bufnr = 1,
				prompt_content = "to complete",
				target_path = "/test/file.lua",
				range = { start_line = 1, end_line = 1 },
			})
			queue.complete(evt.id)

			local stats = queue.stats()

			assert.equals(2, stats.total)
			assert.equals(1, stats.pending)
			assert.equals(1, stats.completed)
		end)
	end)

	describe("clear", function()
		it("should clear all events", function()
			queue.enqueue({
				bufnr = 1,
				prompt_content = "test",
				target_path = "/test/file.lua",
				range = { start_line = 1, end_line = 1 },
			})

			queue.clear()

			assert.equals(0, queue.size())
		end)

		it("should clear only specified status", function()
			local evt = queue.enqueue({
				bufnr = 1,
				prompt_content = "to complete",
				target_path = "/test/file.lua",
				range = { start_line = 1, end_line = 1 },
			})
			queue.complete(evt.id)

			queue.enqueue({
				bufnr = 1,
				prompt_content = "pending",
				target_path = "/test/file.lua",
				range = { start_line = 1, end_line = 1 },
			})

			queue.clear("completed")

			assert.equals(1, queue.size())
			assert.equals(1, queue.pending_count())
		end)
	end)

	describe("listeners", function()
		it("should notify listeners on enqueue", function()
			local notifications = {}
			queue.add_listener(function(event_type, event, size)
				table.insert(notifications, { type = event_type, event = event, size = size })
			end)

			queue.enqueue({
				bufnr = 1,
				prompt_content = "test",
				target_path = "/test/file.lua",
				range = { start_line = 1, end_line = 1 },
			})

			assert.equals(1, #notifications)
			assert.equals("enqueue", notifications[1].type)
		end)
	end)
end)
