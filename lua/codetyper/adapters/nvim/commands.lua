---@mod codetyper.commands Command definitions for Codetyper.nvim

local M = {}

local transform = require("codetyper.core.transform")
local utils = require("codetyper.support.utils")

--- Refresh tree.log manually
local function cmd_tree()
	local tree = require("codetyper.support.tree")
	if tree.update_tree_log() then
		utils.notify("Tree log updated: " .. tree.get_tree_log_path())
	else
		utils.notify("Failed to update tree log", vim.log.levels.ERROR)
	end
end

--- Open tree.log file
local function cmd_tree_view()
	local tree = require("codetyper.support.tree")
	local tree_log_path = tree.get_tree_log_path()

	if not tree_log_path then
		utils.notify("Could not find tree.log", vim.log.levels.WARN)
		return
	end

	-- Ensure tree is up to date
	tree.update_tree_log()

	-- Open in a new split
	vim.cmd("vsplit " .. vim.fn.fnameescape(tree_log_path))
	vim.bo.readonly = true
	vim.bo.modifiable = false
end

--- Reset processed prompts to allow re-processing
local function cmd_reset()
	local autocmds = require("codetyper.adapters.nvim.autocmds")
	autocmds.reset_processed()
end

--- Force update gitignore
local function cmd_gitignore()
	local gitignore = require("codetyper.support.gitignore")
	gitignore.force_update()
end

--- Index the entire project
local function cmd_index_project()
	local indexer = require("codetyper.features.indexer")

	utils.notify("Indexing project...", vim.log.levels.INFO)

	indexer.index_project(function(index)
		if index then
			local msg = string.format(
				"Indexed: %d files, %d functions, %d classes, %d exports",
				index.stats.files,
				index.stats.functions,
				index.stats.classes,
				index.stats.exports
			)
			utils.notify(msg, vim.log.levels.INFO)
		else
			utils.notify("Failed to index project", vim.log.levels.ERROR)
		end
	end)
end

--- Show index status
local function cmd_index_status()
	local indexer = require("codetyper.features.indexer")
	local memory = require("codetyper.features.indexer.memory")

	local status = indexer.get_status()
	local mem_stats = memory.get_stats()

	local lines = {
		"Project Index Status",
		"====================",
		"",
	}

	if status.indexed then
		table.insert(lines, "Status: Indexed")
		table.insert(lines, "Project Type: " .. (status.project_type or "unknown"))
		table.insert(lines, "Last Indexed: " .. os.date("%Y-%m-%d %H:%M:%S", status.last_indexed))
		table.insert(lines, "")
		table.insert(lines, "Stats:")
		table.insert(lines, "  Files: " .. (status.stats.files or 0))
		table.insert(lines, "  Functions: " .. (status.stats.functions or 0))
		table.insert(lines, "  Classes: " .. (status.stats.classes or 0))
		table.insert(lines, "  Exports: " .. (status.stats.exports or 0))
	else
		table.insert(lines, "Status: Not indexed")
		table.insert(lines, "Run :CoderIndexProject to index")
	end

	table.insert(lines, "")
	table.insert(lines, "Memories:")
	table.insert(lines, "  Patterns: " .. mem_stats.patterns)
	table.insert(lines, "  Conventions: " .. mem_stats.conventions)
	table.insert(lines, "  Symbols: " .. mem_stats.symbols)

	utils.notify(table.concat(lines, "\n"))
end

--- Show learned memories
local function cmd_memories()
	local memory = require("codetyper.features.indexer.memory")

	local all = memory.get_all()
	local lines = {
		"Learned Memories",
		"================",
		"",
		"Patterns:",
	}

	local pattern_count = 0
	for _, mem in pairs(all.patterns) do
		pattern_count = pattern_count + 1
		if pattern_count <= 10 then
			table.insert(lines, "  - " .. (mem.content or ""):sub(1, 60))
		end
	end
	if pattern_count > 10 then
		table.insert(lines, "  ... and " .. (pattern_count - 10) .. " more")
	elseif pattern_count == 0 then
		table.insert(lines, "  (none)")
	end

	table.insert(lines, "")
	table.insert(lines, "Conventions:")

	local conv_count = 0
	for _, mem in pairs(all.conventions) do
		conv_count = conv_count + 1
		if conv_count <= 10 then
			table.insert(lines, "  - " .. (mem.content or ""):sub(1, 60))
		end
	end
	if conv_count > 10 then
		table.insert(lines, "  ... and " .. (conv_count - 10) .. " more")
	elseif conv_count == 0 then
		table.insert(lines, "  (none)")
	end

	utils.notify(table.concat(lines, "\n"))
end

--- Clear memories
---@param pattern string|nil Optional pattern to match
local function cmd_forget(pattern)
	local memory = require("codetyper.features.indexer.memory")

	if not pattern or pattern == "" then
		-- Confirm before clearing all
		vim.ui.select({ "Yes", "No" }, {
			prompt = "Clear all memories?",
		}, function(choice)
			if choice == "Yes" then
				memory.clear()
				utils.notify("All memories cleared", vim.log.levels.INFO)
			end
		end)
	else
		memory.clear(pattern)
		utils.notify("Cleared memories matching: " .. pattern, vim.log.levels.INFO)
	end
end

--- Main command dispatcher
---@param args table Command arguments
--- Show LLM accuracy statistics
local function cmd_llm_stats()
	local llm = require("codetyper.core.llm")
	local stats = llm.get_accuracy_stats()

	local lines = {
		"LLM Provider Accuracy Statistics",
		"================================",
		"",
		string.format("Ollama:"),
		string.format("  Total requests: %d", stats.ollama.total),
		string.format("  Correct: %d", stats.ollama.correct),
		string.format("  Accuracy: %.1f%%", stats.ollama.accuracy * 100),
		"",
		string.format("Copilot:"),
		string.format("  Total requests: %d", stats.copilot.total),
		string.format("  Correct: %d", stats.copilot.correct),
		string.format("  Accuracy: %.1f%%", stats.copilot.accuracy * 100),
		"",
		"Note: Smart selection prefers Ollama when brain memories",
		"provide enough context. Accuracy improves over time via",
		"pondering (verification with other LLMs).",
	}

	vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

--- Report feedback on last LLM response
---@param was_good boolean Whether the response was good
local function cmd_llm_feedback(was_good)
	local llm = require("codetyper.core.llm")
	-- Default to ollama for feedback
	local provider = "ollama"

	llm.report_feedback(provider, was_good)
	local feedback_type = was_good and "positive" or "negative"
	utils.notify(string.format("Reported %s feedback for %s", feedback_type, provider), vim.log.levels.INFO)
end

--- Reset LLM accuracy statistics
local function cmd_llm_reset_stats()
	local selector = require("codetyper.core.llm.selector")
	selector.reset_accuracy_stats()
	utils.notify("LLM accuracy statistics reset", vim.log.levels.INFO)
end

local function coder_cmd(args)
	local subcommand = args.fargs[1] or "toggle"

	local commands = {
		tree = cmd_tree,
		["tree-view"] = cmd_tree_view,
		reset = cmd_reset,
		gitignore = cmd_gitignore,
		["transform-selection"] = transform.cmd_transform_selection,
		["index-project"] = cmd_index_project,
		["index-status"] = cmd_index_status,
		memories = cmd_memories,
		forget = function(args)
			cmd_forget(args.fargs[2])
		end,
		-- LLM smart selection commands
		["llm-stats"] = cmd_llm_stats,
		["llm-feedback-good"] = function()
			cmd_llm_feedback(true)
		end,
		["llm-feedback-bad"] = function()
			cmd_llm_feedback(false)
		end,
		["llm-reset-stats"] = cmd_llm_reset_stats,
		-- Cost tracking commands
		["cost"] = function()
			local cost = require("codetyper.core.cost")
			cost.toggle()
		end,
		["cost-clear"] = function()
			local cost = require("codetyper.core.cost")
			cost.clear()
		end,
		-- Credentials management commands
		["add-api-key"] = function()
			local credentials = require("codetyper.config.credentials")
			credentials.interactive_add()
		end,
		["remove-api-key"] = function()
			local credentials = require("codetyper.config.credentials")
			credentials.interactive_remove()
		end,
		["credentials"] = function()
			local credentials = require("codetyper.config.credentials")
			credentials.show_status()
		end,
		["switch-provider"] = function()
			local credentials = require("codetyper.config.credentials")
			credentials.interactive_switch_provider()
		end,
		["model"] = function(args)
			local credentials = require("codetyper.config.credentials")
			local codetyper = require("codetyper")
			local config = codetyper.get_config()
			local provider = config.llm.provider

			-- Only available for Copilot provider
			if provider ~= "copilot" then
				utils.notify(
					"CoderModel is only available when using Copilot provider. Current: " .. provider:upper(),
					vim.log.levels.WARN
				)
				return
			end

			local model_arg = args.fargs[2]
			if model_arg and model_arg ~= "" then
				local cost = credentials.get_copilot_model_cost(model_arg) or "custom"
				credentials.set_credentials("copilot", { model = model_arg, configured = true })
				utils.notify("Copilot model set to: " .. model_arg .. " — " .. cost, vim.log.levels.INFO)
			else
				credentials.interactive_copilot_config(true)
			end
		end,
	}

	local cmd_fn = commands[subcommand]
	if cmd_fn then
		cmd_fn(args)
	else
		utils.notify("Unknown subcommand: " .. subcommand, vim.log.levels.ERROR)
	end
end

--- Setup all commands
function M.setup()
	vim.api.nvim_create_user_command("Coder", coder_cmd, {
		nargs = "?",
		complete = function()
			return {
				"process",
				"status",
				"tree",
				"tree-view",
				"reset",
				"gitignore",
				"transform-selection",
				"index-project",
				"index-status",
				"memories",
				"forget",
				"llm-stats",
				"llm-feedback-good",
				"llm-feedback-bad",
				"llm-reset-stats",
				"cost",
				"cost-clear",
				"add-api-key",
				"remove-api-key",
				"credentials",
				"switch-provider",
				"model",
			}
		end,
		desc = "Codetyper.nvim commands",
	})

	vim.api.nvim_create_user_command("CoderTree", function()
		cmd_tree()
	end, { desc = "Refresh tree.log" })

	vim.api.nvim_create_user_command("CoderTreeView", function()
		cmd_tree_view()
	end, { desc = "View tree.log" })

	vim.api.nvim_create_user_command("CoderTransformSelection", function()
		transform.cmd_transform_selection()
	end, { desc = "Transform visual selection with custom prompt input" })

	-- Project indexer commands
	vim.api.nvim_create_user_command("CoderIndexProject", function()
		cmd_index_project()
	end, { desc = "Index the entire project" })

	vim.api.nvim_create_user_command("CoderIndexStatus", function()
		cmd_index_status()
	end, { desc = "Show project index status" })

	vim.api.nvim_create_user_command("CoderMemories", function()
		cmd_memories()
	end, { desc = "Show learned memories" })

	vim.api.nvim_create_user_command("CoderForget", function(opts)
		cmd_forget(opts.args ~= "" and opts.args or nil)
	end, {
		desc = "Clear memories (optionally matching pattern)",
		nargs = "?",
	})

	-- Brain feedback command - teach the brain from your experience
	vim.api.nvim_create_user_command("CoderFeedback", function(opts)
		local brain = require("codetyper.core.memory")
		if not brain.is_initialized() then
			vim.notify("Brain not initialized", vim.log.levels.WARN)
			return
		end

		local feedback_type = opts.args:lower()
		local current_file = vim.fn.expand("%:p")

		if feedback_type == "good" or feedback_type == "accept" or feedback_type == "+" then
			-- Learn positive feedback
			brain.learn({
				type = "user_feedback",
				file = current_file,
				timestamp = os.time(),
				data = {
					feedback = "accepted",
					description = "User marked code as good/accepted",
				},
			})
			vim.notify("Brain: Learned positive feedback ✓", vim.log.levels.INFO)
		elseif feedback_type == "bad" or feedback_type == "reject" or feedback_type == "-" then
			-- Learn negative feedback
			brain.learn({
				type = "user_feedback",
				file = current_file,
				timestamp = os.time(),
				data = {
					feedback = "rejected",
					description = "User marked code as bad/rejected",
				},
			})
			vim.notify("Brain: Learned negative feedback ✗", vim.log.levels.INFO)
		elseif feedback_type == "stats" or feedback_type == "status" then
			-- Show brain stats
			local stats = brain.stats()
			local msg = string.format(
				"Brain Stats:\n• Nodes: %d\n• Edges: %d\n• Pending: %d\n• Deltas: %d",
				stats.node_count or 0,
				stats.edge_count or 0,
				stats.pending_changes or 0,
				stats.delta_count or 0
			)
			vim.notify(msg, vim.log.levels.INFO)
		else
			vim.notify("Usage: CoderFeedback <good|bad|stats>", vim.log.levels.INFO)
		end
	end, {
		desc = "Give feedback to the brain (good/bad/stats)",
		nargs = "?",
		complete = function()
			return { "good", "bad", "stats" }
		end,
	})

	-- Brain stats command
	vim.api.nvim_create_user_command("CoderBrain", function(opts)
		local brain = require("codetyper.core.memory")
		if not brain.is_initialized() then
			vim.notify("Brain not initialized", vim.log.levels.WARN)
			return
		end

		local action = opts.args:lower()

		if action == "stats" or action == "" then
			local stats = brain.stats()
			local lines = {
				"╭─────────────────────────────────╮",
				"│       CODETYPER BRAIN           │",
				"╰─────────────────────────────────╯",
				"",
				string.format("  Nodes: %d", stats.node_count or 0),
				string.format("  Edges: %d", stats.edge_count or 0),
				string.format("  Deltas: %d", stats.delta_count or 0),
				string.format("  Pending: %d", stats.pending_changes or 0),
				"",
				"  The more you use Codetyper,",
				"  the smarter it becomes!",
			}
			vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
		elseif action == "commit" then
			local hash = brain.commit("Manual commit")
			if hash then
				vim.notify("Brain: Committed changes (hash: " .. hash:sub(1, 8) .. ")", vim.log.levels.INFO)
			else
				vim.notify("Brain: Nothing to commit", vim.log.levels.INFO)
			end
		elseif action == "flush" then
			brain.flush()
			vim.notify("Brain: Flushed to disk", vim.log.levels.INFO)
		elseif action == "prune" then
			local pruned = brain.prune()
			vim.notify("Brain: Pruned " .. pruned .. " low-value nodes", vim.log.levels.INFO)
		else
			vim.notify("Usage: CoderBrain <stats|commit|flush|prune>", vim.log.levels.INFO)
		end
	end, {
		desc = "Brain management commands",
		nargs = "?",
		complete = function()
			return { "stats", "commit", "flush", "prune" }
		end,
	})

	-- Cost estimation command
	vim.api.nvim_create_user_command("CoderCost", function()
		local cost = require("codetyper.core.cost")
		cost.toggle()
	end, { desc = "Show LLM cost estimation window" })

	-- Credentials management commands
	vim.api.nvim_create_user_command("CoderAddApiKey", function()
		local credentials = require("codetyper.config.credentials")
		credentials.interactive_add()
	end, { desc = "Add or update LLM provider API key" })

	vim.api.nvim_create_user_command("CoderRemoveApiKey", function()
		local credentials = require("codetyper.config.credentials")
		credentials.interactive_remove()
	end, { desc = "Remove LLM provider credentials" })

	vim.api.nvim_create_user_command("CoderCredentials", function()
		local credentials = require("codetyper.config.credentials")
		credentials.show_status()
	end, { desc = "Show credentials status" })

	vim.api.nvim_create_user_command("CoderSwitchProvider", function()
		local credentials = require("codetyper.config.credentials")
		credentials.interactive_switch_provider()
	end, { desc = "Switch active LLM provider" })

	-- Quick model switcher command (Copilot only)
	vim.api.nvim_create_user_command("CoderModel", function(opts)
		local credentials = require("codetyper.adapters.config.credentials")
		local codetyper = require("codetyper")
		local config = codetyper.get_config()
		local provider = config.llm.provider

		-- Only available for Copilot provider
		if provider ~= "copilot" then
			utils.notify(
				"CoderModel is only available when using Copilot provider. Current: " .. provider:upper(),
				vim.log.levels.WARN
			)
			return
		end

		-- If an argument is provided, set the model directly
		if opts.args and opts.args ~= "" then
			local cost = credentials.get_copilot_model_cost(opts.args) or "custom"
			credentials.set_credentials("copilot", { model = opts.args, configured = true })
			utils.notify("Copilot model set to: " .. opts.args .. " — " .. cost, vim.log.levels.INFO)
			return
		end

		-- Show interactive selector with costs (silent mode - no OAuth message)
		credentials.interactive_copilot_config(true)
	end, {
		nargs = "?",
		desc = "Quick switch Copilot model (only available with Copilot provider)",
		complete = function()
			local codetyper = require("codetyper")
			local credentials = require("codetyper.config.credentials")
			local config = codetyper.get_config()
			if config.llm.provider == "copilot" then
				return credentials.get_copilot_model_names()
			end
			return {}
		end,
	})

	-- Setup default keymaps
	M.setup_keymaps()
end

--- Setup default keymaps for transform commands
function M.setup_keymaps()
	-- Visual mode: transform selection with custom prompt input
	vim.keymap.set("v", "<leader>ctt", function()
		transform.cmd_transform_selection()
	end, {
		silent = true,
		desc = "Coder: Transform selection with prompt",
	})
	-- Normal mode: prompt only (no selection); request is entered in the prompt
	vim.keymap.set("n", "<leader>ctt", function()
		transform.cmd_transform_selection()
	end, {
		silent = true,
		desc = "Coder: Open prompt window",
	})
end

return M
