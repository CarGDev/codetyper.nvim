---@mod codetyper.cmp_source Completion source for nvim-cmp
---@brief [[
--- Provides intelligent code completions using the brain, indexer, and LLM.
--- Integrates with nvim-cmp as a custom source.
---@brief ]]

local M = {}

local source = {}

--- Check if cmp is available
---@return boolean
local function has_cmp()
	return pcall(require, "cmp")
end

--- Get completion items from brain context
---@param prefix string Current word prefix
---@return table[] items
local function get_brain_completions(prefix)
	local items = {}

	local ok_brain, brain = pcall(require, "codetyper.brain")
	if not ok_brain then
		return items
	end

	-- Check if brain is initialized safely
	local is_init = false
	if brain.is_initialized then
		local ok, result = pcall(brain.is_initialized)
		is_init = ok and result
	end

	if not is_init then
		return items
	end

	-- Query brain for relevant patterns
	local ok_query, result = pcall(brain.query, {
		query = prefix,
		max_results = 10,
		types = { "pattern" },
	})

	if ok_query and result and result.nodes then
		for _, node in ipairs(result.nodes) do
			if node.c and node.c.s then
				-- Extract function/class names from summary
				local summary = node.c.s
				for name in summary:gmatch("functions:%s*([^;]+)") do
					for func in name:gmatch("([%w_]+)") do
						if func:lower():find(prefix:lower(), 1, true) then
							table.insert(items, {
								label = func,
								kind = 3, -- Function
								detail = "[brain]",
								documentation = summary,
							})
						end
					end
				end
				for name in summary:gmatch("classes:%s*([^;]+)") do
					for class in name:gmatch("([%w_]+)") do
						if class:lower():find(prefix:lower(), 1, true) then
							table.insert(items, {
								label = class,
								kind = 7, -- Class
								detail = "[brain]",
								documentation = summary,
							})
						end
					end
				end
			end
		end
	end

	return items
end

--- Get completion items from indexer symbols
---@param prefix string Current word prefix
---@return table[] items
local function get_indexer_completions(prefix)
	local items = {}

	local ok_indexer, indexer = pcall(require, "codetyper.indexer")
	if not ok_indexer then
		return items
	end

	local ok_load, index = pcall(indexer.load_index)
	if not ok_load or not index then
		return items
	end

	-- Search symbols
	if index.symbols then
		for symbol, files in pairs(index.symbols) do
			if symbol:lower():find(prefix:lower(), 1, true) then
				local files_str = type(files) == "table" and table.concat(files, ", ") or tostring(files)
				table.insert(items, {
					label = symbol,
					kind = 6, -- Variable (generic)
					detail = "[index] " .. files_str:sub(1, 30),
					documentation = "Symbol found in: " .. files_str,
				})
			end
		end
	end

	-- Search functions in files
	if index.files then
		for filepath, file_index in pairs(index.files) do
			if file_index and file_index.functions then
				for _, func in ipairs(file_index.functions) do
					if func.name and func.name:lower():find(prefix:lower(), 1, true) then
						table.insert(items, {
							label = func.name,
							kind = 3, -- Function
							detail = "[index] " .. vim.fn.fnamemodify(filepath, ":t"),
							documentation = func.docstring or ("Function at line " .. (func.line or "?")),
						})
					end
				end
			end
			if file_index and file_index.classes then
				for _, class in ipairs(file_index.classes) do
					if class.name and class.name:lower():find(prefix:lower(), 1, true) then
						table.insert(items, {
							label = class.name,
							kind = 7, -- Class
							detail = "[index] " .. vim.fn.fnamemodify(filepath, ":t"),
							documentation = class.docstring or ("Class at line " .. (class.line or "?")),
						})
					end
				end
			end
		end
	end

	return items
end

--- Get completion items from current buffer (fallback)
---@param prefix string Current word prefix
---@param bufnr number Buffer number
---@return table[] items
local function get_buffer_completions(prefix, bufnr)
	local items = {}
	local seen = {}

	-- Get all lines in buffer
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local prefix_lower = prefix:lower()

	for _, line in ipairs(lines) do
		-- Extract words that could be identifiers
		for word in line:gmatch("[%a_][%w_]*") do
			if #word >= 3 and word:lower():find(prefix_lower, 1, true) and not seen[word] and word ~= prefix then
				seen[word] = true
				table.insert(items, {
					label = word,
					kind = 1, -- Text
					detail = "[buffer]",
				})
			end
		end
	end

	return items
end

--- Create new cmp source instance
function source.new()
	return setmetatable({}, { __index = source })
end

--- Get source name
function source:get_keyword_pattern()
	return [[\k\+]]
end

--- Check if source is available
function source:is_available()
	return true
end

--- Get debug name
function source:get_debug_name()
	return "codetyper"
end

--- Get trigger characters
function source:get_trigger_characters()
	return { ".", ":", "_" }
end

--- Complete
---@param params table
---@param callback fun(response: table|nil)
function source:complete(params, callback)
	local prefix = params.context.cursor_before_line:match("[%w_]+$") or ""

	if #prefix < 2 then
		callback({ items = {}, isIncomplete = true })
		return
	end

	-- Collect completions from brain, indexer, and buffer
	local items = {}
	local seen = {}

	-- Get brain completions (highest priority)
	local ok1, brain_items = pcall(get_brain_completions, prefix)
	if ok1 and brain_items then
		for _, item in ipairs(brain_items) do
			if not seen[item.label] then
				seen[item.label] = true
				item.sortText = "1" .. item.label
				table.insert(items, item)
			end
		end
	end

	-- Get indexer completions
	local ok2, indexer_items = pcall(get_indexer_completions, prefix)
	if ok2 and indexer_items then
		for _, item in ipairs(indexer_items) do
			if not seen[item.label] then
				seen[item.label] = true
				item.sortText = "2" .. item.label
				table.insert(items, item)
			end
		end
	end

	-- Get buffer completions as fallback (lower priority)
	local bufnr = params.context.bufnr
	if bufnr then
		local ok3, buffer_items = pcall(get_buffer_completions, prefix, bufnr)
		if ok3 and buffer_items then
			for _, item in ipairs(buffer_items) do
				if not seen[item.label] then
					seen[item.label] = true
					item.sortText = "3" .. item.label
					table.insert(items, item)
				end
			end
		end
	end

	callback({
		items = items,
		isIncomplete = #items >= 50,
	})
end

--- Setup the completion source
function M.setup()
	if not has_cmp() then
		return false
	end

	local cmp = require("cmp")
	local new_source = source.new()

	-- Register the source
	cmp.register_source("codetyper", new_source)

	return true
end

--- Check if source is registered
---@return boolean
function M.is_registered()
	local ok, cmp = pcall(require, "cmp")
	if not ok then
		return false
	end

	-- Try to get registered sources
	local config = cmp.get_config()
	if config and config.sources then
		for _, src in ipairs(config.sources) do
			if src.name == "codetyper" then
				return true
			end
		end
	end

	return false
end

--- Get source for manual registration
function M.get_source()
	return source
end

return M
