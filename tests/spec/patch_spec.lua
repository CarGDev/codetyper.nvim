---@diagnostic disable: undefined-global
-- Tests for lua/codetyper/agent/patch.lua

describe("patch", function()
	local patch

	before_each(function()
		-- Reset module state before each test
		package.loaded["codetyper.agent.patch"] = nil
		patch = require("codetyper.agent.patch")
	end)

	describe("generate_id", function()
		it("should generate unique IDs", function()
			local id1 = patch.generate_id()
			local id2 = patch.generate_id()

			assert.is_not.equals(id1, id2)
			assert.is_true(id1:match("^patch_"))
		end)
	end)

	describe("snapshot_buffer", function()
		local test_buf

		before_each(function()
			test_buf = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, {
				"line 1",
				"line 2",
				"line 3",
				"line 4",
				"line 5",
			})
		end)

		after_each(function()
			if vim.api.nvim_buf_is_valid(test_buf) then
				vim.api.nvim_buf_delete(test_buf, { force = true })
			end
		end)

		it("should capture changedtick", function()
			local snapshot = patch.snapshot_buffer(test_buf)

			assert.is_number(snapshot.changedtick)
		end)

		it("should capture content hash", function()
			local snapshot = patch.snapshot_buffer(test_buf)

			assert.is_string(snapshot.content_hash)
			assert.is_true(#snapshot.content_hash > 0)
		end)

		it("should snapshot specific range", function()
			local snapshot = patch.snapshot_buffer(test_buf, { start_line = 2, end_line = 4 })

			assert.equals(test_buf, snapshot.bufnr)
			assert.is_truthy(snapshot.range)
			assert.equals(2, snapshot.range.start_line)
			assert.equals(4, snapshot.range.end_line)
		end)
	end)

	describe("is_snapshot_stale", function()
		local test_buf

		before_each(function()
			test_buf = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, {
				"original content",
				"line 2",
			})
		end)

		after_each(function()
			if vim.api.nvim_buf_is_valid(test_buf) then
				vim.api.nvim_buf_delete(test_buf, { force = true })
			end
		end)

		it("should return false for unchanged buffer", function()
			local snapshot = patch.snapshot_buffer(test_buf)

			local is_stale, reason = patch.is_snapshot_stale(snapshot)

			assert.is_false(is_stale)
			assert.is_nil(reason)
		end)

		it("should return true when content changes", function()
			local snapshot = patch.snapshot_buffer(test_buf)

			-- Modify buffer
			vim.api.nvim_buf_set_lines(test_buf, 0, 1, false, { "modified content" })

			local is_stale, reason = patch.is_snapshot_stale(snapshot)

			assert.is_true(is_stale)
			assert.equals("content_changed", reason)
		end)

		it("should return true for invalid buffer", function()
			local snapshot = patch.snapshot_buffer(test_buf)

			-- Delete buffer
			vim.api.nvim_buf_delete(test_buf, { force = true })

			local is_stale, reason = patch.is_snapshot_stale(snapshot)

			assert.is_true(is_stale)
			assert.equals("buffer_invalid", reason)
		end)
	end)

	describe("queue_patch", function()
		it("should add patch to queue", function()
			local p = {
				event_id = "test_event",
				target_bufnr = 1,
				target_path = "/test/file.lua",
				original_snapshot = {
					bufnr = 1,
					changedtick = 0,
					content_hash = "abc123",
				},
				generated_code = "function test() end",
				confidence = 0.9,
			}

			local queued = patch.queue_patch(p)

			assert.is_truthy(queued.id)
			assert.equals("pending", queued.status)

			local pending = patch.get_pending()
			assert.equals(1, #pending)
		end)

		it("should set default status", function()
			local p = {
				event_id = "test",
				generated_code = "code",
				confidence = 0.8,
				original_snapshot = { bufnr = 1, changedtick = 0, content_hash = "x" },
			}

			local queued = patch.queue_patch(p)

			assert.equals("pending", queued.status)
		end)
	end)

	describe("get", function()
		it("should return patch by ID", function()
			local p = patch.queue_patch({
				event_id = "test",
				generated_code = "code",
				confidence = 0.8,
				original_snapshot = { bufnr = 1, changedtick = 0, content_hash = "x" },
			})

			local found = patch.get(p.id)

			assert.is_not.nil(found)
			assert.equals(p.id, found.id)
		end)

		it("should return nil for unknown ID", function()
			local found = patch.get("unknown_id")
			assert.is_nil(found)
		end)
	end)

	describe("mark_applied", function()
		it("should mark patch as applied", function()
			local p = patch.queue_patch({
				event_id = "test",
				generated_code = "code",
				confidence = 0.8,
				original_snapshot = { bufnr = 1, changedtick = 0, content_hash = "x" },
			})

			local success = patch.mark_applied(p.id)

			assert.is_true(success)
			assert.equals("applied", patch.get(p.id).status)
			assert.is_truthy(patch.get(p.id).applied_at)
		end)
	end)

	describe("mark_stale", function()
		it("should mark patch as stale with reason", function()
			local p = patch.queue_patch({
				event_id = "test",
				generated_code = "code",
				confidence = 0.8,
				original_snapshot = { bufnr = 1, changedtick = 0, content_hash = "x" },
			})

			local success = patch.mark_stale(p.id, "content_changed")

			assert.is_true(success)
			assert.equals("stale", patch.get(p.id).status)
			assert.equals("content_changed", patch.get(p.id).stale_reason)
		end)
	end)

	describe("stats", function()
		it("should return correct statistics", function()
			local p1 = patch.queue_patch({
				event_id = "test1",
				generated_code = "code1",
				confidence = 0.8,
				original_snapshot = { bufnr = 1, changedtick = 0, content_hash = "x" },
			})

			patch.queue_patch({
				event_id = "test2",
				generated_code = "code2",
				confidence = 0.9,
				original_snapshot = { bufnr = 1, changedtick = 0, content_hash = "y" },
			})

			patch.mark_applied(p1.id)

			local stats = patch.stats()

			assert.equals(2, stats.total)
			assert.equals(1, stats.pending)
			assert.equals(1, stats.applied)
		end)
	end)

	describe("get_for_event", function()
		it("should return patches for specific event", function()
			patch.queue_patch({
				event_id = "event_a",
				generated_code = "code1",
				confidence = 0.8,
				original_snapshot = { bufnr = 1, changedtick = 0, content_hash = "x" },
			})

			patch.queue_patch({
				event_id = "event_b",
				generated_code = "code2",
				confidence = 0.9,
				original_snapshot = { bufnr = 1, changedtick = 0, content_hash = "y" },
			})

			patch.queue_patch({
				event_id = "event_a",
				generated_code = "code3",
				confidence = 0.7,
				original_snapshot = { bufnr = 1, changedtick = 0, content_hash = "z" },
			})

			local event_a_patches = patch.get_for_event("event_a")

			assert.equals(2, #event_a_patches)
		end)
	end)

	describe("clear", function()
		it("should clear all patches", function()
			patch.queue_patch({
				event_id = "test",
				generated_code = "code",
				confidence = 0.8,
				original_snapshot = { bufnr = 1, changedtick = 0, content_hash = "x" },
			})

			patch.clear()

			assert.equals(0, #patch.get_pending())
			assert.equals(0, patch.stats().total)
		end)
	end)

	describe("cancel_for_buffer", function()
		it("should cancel patches for specific buffer", function()
			patch.queue_patch({
				event_id = "test1",
				target_bufnr = 1,
				generated_code = "code1",
				confidence = 0.8,
				original_snapshot = { bufnr = 1, changedtick = 0, content_hash = "x" },
			})

			patch.queue_patch({
				event_id = "test2",
				target_bufnr = 2,
				generated_code = "code2",
				confidence = 0.9,
				original_snapshot = { bufnr = 2, changedtick = 0, content_hash = "y" },
			})

			local cancelled = patch.cancel_for_buffer(1)

			assert.equals(1, cancelled)
			assert.equals(1, #patch.get_pending())
		end)
	end)
end)
