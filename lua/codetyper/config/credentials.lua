---@mod codetyper.config.credentials Secure credential storage for Codetyper.nvim
---@brief [[
--- Manages API keys and model preferences stored outside of config files.
--- Credentials are stored in ~/.local/share/nvim/codetyper/configuration.json
---@brief ]]

local M = {}

local utils = require("codetyper.support.utils")

--- Get the credentials file path
---@return string Path to credentials file
local function get_credentials_path()
	local data_dir = vim.fn.stdpath("data")
	return data_dir .. "/codetyper/configuration.json"
end

--- Ensure the credentials directory exists
---@return boolean Success
local function ensure_dir()
	local data_dir = vim.fn.stdpath("data")
	local codetyper_dir = data_dir .. "/codetyper"
	return utils.ensure_dir(codetyper_dir)
end

--- Load credentials from file
---@return table Credentials data
function M.load()
	local path = get_credentials_path()
	local content = utils.read_file(path)

	if not content or content == "" then
		return {
			version = 1,
			providers = {},
		}
	end

	local ok, data = pcall(vim.json.decode, content)
	if not ok or not data then
		return {
			version = 1,
			providers = {},
		}
	end

	return data
end

--- Save credentials to file
---@param data table Credentials data
---@return boolean Success
function M.save(data)
	if not ensure_dir() then
		return false
	end

	local path = get_credentials_path()
	local ok, json = pcall(vim.json.encode, data)
	if not ok then
		return false
	end

	return utils.write_file(path, json)
end

--- Get API key for a provider
---@param provider string Provider name (claude, openai, gemini, copilot, ollama)
---@return string|nil API key or nil if not found
function M.get_api_key(provider)
	local data = M.load()
	local provider_data = data.providers and data.providers[provider]

	if provider_data and provider_data.api_key then
		return provider_data.api_key
	end

	return nil
end

--- Get model for a provider
---@param provider string Provider name
---@return string|nil Model name or nil if not found
function M.get_model(provider)
	local data = M.load()
	local provider_data = data.providers and data.providers[provider]

	if provider_data and provider_data.model then
		return provider_data.model
	end

	return nil
end

--- Get endpoint for a provider (for custom OpenAI-compatible endpoints)
---@param provider string Provider name
---@return string|nil Endpoint URL or nil if not found
function M.get_endpoint(provider)
	local data = M.load()
	local provider_data = data.providers and data.providers[provider]

	if provider_data and provider_data.endpoint then
		return provider_data.endpoint
	end

	return nil
end

--- Get host for Ollama
---@return string|nil Host URL or nil if not found
function M.get_ollama_host()
	local data = M.load()
	local provider_data = data.providers and data.providers.ollama

	if provider_data and provider_data.host then
		return provider_data.host
	end

	return nil
end

--- Set credentials for a provider
---@param provider string Provider name
---@param credentials table Credentials (api_key, model, endpoint, host)
---@return boolean Success
function M.set_credentials(provider, credentials)
	local data = M.load()

	if not data.providers then
		data.providers = {}
	end

	if not data.providers[provider] then
		data.providers[provider] = {}
	end

	-- Merge credentials
	for key, value in pairs(credentials) do
		if value and value ~= "" then
			data.providers[provider][key] = value
		end
	end

	data.updated = os.time()

	return M.save(data)
end

--- Remove credentials for a provider
---@param provider string Provider name
---@return boolean Success
function M.remove_credentials(provider)
	local data = M.load()

	if data.providers and data.providers[provider] then
		data.providers[provider] = nil
		data.updated = os.time()
		return M.save(data)
	end

	return true
end

--- List all configured providers (checks both stored credentials AND config)
---@return table List of provider names with their config status
function M.list_providers()
	local data = M.load()
	local result = {}

	local all_providers = { "claude", "openai", "gemini", "copilot", "ollama" }

	for _, provider in ipairs(all_providers) do
		local provider_data = data.providers and data.providers[provider]
		local has_stored_key = provider_data and provider_data.api_key and provider_data.api_key ~= ""
		local has_model = provider_data and provider_data.model and provider_data.model ~= ""

		-- Check if configured from config or environment
		local configured_from_config = false
		local config_model = nil
		local ok, codetyper = pcall(require, "codetyper")
		if ok then
			local config = codetyper.get_config()
			if config and config.llm and config.llm[provider] then
				local pc = config.llm[provider]
				config_model = pc.model

				if provider == "claude" then
					configured_from_config = pc.api_key ~= nil or vim.env.ANTHROPIC_API_KEY ~= nil
				elseif provider == "openai" then
					configured_from_config = pc.api_key ~= nil or vim.env.OPENAI_API_KEY ~= nil
				elseif provider == "gemini" then
					configured_from_config = pc.api_key ~= nil or vim.env.GEMINI_API_KEY ~= nil
				elseif provider == "copilot" then
					configured_from_config = true -- Just needs copilot.lua
				elseif provider == "ollama" then
					configured_from_config = pc.host ~= nil
				end
			end
		end

		local is_configured = has_stored_key
			or (provider == "ollama" and provider_data ~= nil)
			or (provider == "copilot" and (provider_data ~= nil or configured_from_config))
			or configured_from_config

		table.insert(result, {
			name = provider,
			configured = is_configured,
			has_api_key = has_stored_key,
			has_model = has_model or config_model ~= nil,
			model = (provider_data and provider_data.model) or config_model,
			source = has_stored_key and "stored" or (configured_from_config and "config" or nil),
		})
	end

	return result
end

--- Default models for each provider
M.default_models = {
	claude = "claude-sonnet-4-20250514",
	openai = "gpt-4o",
	gemini = "gemini-2.0-flash",
	copilot = "claude-sonnet-4",
	ollama = "deepseek-coder:6.7b",
}

--- Available models for Copilot (GitHub Copilot Chat API)
--- Models with cost multipliers: 0x = free, 0.33x = discount, 1x = standard, 3x = premium
M.copilot_models = {
	-- Free tier (0x)
	{ name = "gpt-4.1", cost = "0x" },
	{ name = "gpt-4o", cost = "0x" },
	{ name = "gpt-5-mini", cost = "0x" },
	{ name = "grok-code-fast-1", cost = "0x" },
	{ name = "raptor-mini", cost = "0x" },
	-- Discount tier (0.33x)
	{ name = "claude-haiku-4.5", cost = "0.33x" },
	{ name = "gemini-3-flash", cost = "0.33x" },
	{ name = "gpt-5.1-codex-mini", cost = "0.33x" },
	-- Standard tier (1x)
	{ name = "claude-sonnet-4", cost = "1x" },
	{ name = "claude-sonnet-4.5", cost = "1x" },
	{ name = "gemini-2.5-pro", cost = "1x" },
	{ name = "gemini-3-pro", cost = "1x" },
	{ name = "gpt-5", cost = "1x" },
	{ name = "gpt-5-codex", cost = "1x" },
	{ name = "gpt-5.1", cost = "1x" },
	{ name = "gpt-5.1-codex", cost = "1x" },
	{ name = "gpt-5.1-codex-max", cost = "1x" },
	{ name = "gpt-5.2", cost = "1x" },
	{ name = "gpt-5.2-codex", cost = "1x" },
	-- Premium tier (3x)
	{ name = "claude-opus-4.5", cost = "3x" },
}

--- Get list of copilot model names (for completion)
---@return string[]
function M.get_copilot_model_names()
	local names = {}
	for _, model in ipairs(M.copilot_models) do
		table.insert(names, model.name)
	end
	return names
end

--- Get cost for a copilot model
---@param model_name string
---@return string|nil
function M.get_copilot_model_cost(model_name)
	for _, model in ipairs(M.copilot_models) do
		if model.name == model_name then
			return model.cost
		end
	end
	return nil
end

--- Interactive command to add/update API key
function M.interactive_add()
	local providers = { "claude", "openai", "gemini", "copilot", "ollama" }

	-- Step 1: Select provider
	vim.ui.select(providers, {
		prompt = "Select LLM provider:",
		format_item = function(item)
			local display = item:sub(1, 1):upper() .. item:sub(2)
			local creds = M.load()
			local configured = creds.providers and creds.providers[item]
			if configured and (configured.api_key or item == "ollama") then
				return display .. " [configured]"
			end
			return display
		end,
	}, function(provider)
		if not provider then
			return
		end

		-- Step 2: Get API key (skip for Ollama)
		if provider == "ollama" then
			M.interactive_ollama_config()
		else
			M.interactive_api_key(provider)
		end
	end)
end

--- Interactive API key input
---@param provider string Provider name
function M.interactive_api_key(provider)
	-- Copilot uses OAuth from copilot.lua, no API key needed
	if provider == "copilot" then
		M.interactive_copilot_config()
		return
	end

	local prompt = string.format("Enter %s API key (leave empty to skip): ", provider:upper())

	vim.ui.input({ prompt = prompt }, function(api_key)
		if api_key == nil then
			return -- Cancelled
		end

		-- Step 3: Get model
		M.interactive_model(provider, api_key)
	end)
end

--- Interactive Copilot configuration (no API key, uses OAuth)
---@param silent? boolean If true, don't show the OAuth info message
function M.interactive_copilot_config(silent)
	if not silent then
		utils.notify("Copilot uses OAuth from copilot.lua/copilot.vim - no API key needed", vim.log.levels.INFO)
	end

	-- Get current model if configured
	local current_model = M.get_model("copilot") or M.default_models.copilot
	local current_cost = M.get_copilot_model_cost(current_model) or "?"

	-- Build model options with "Custom..." option
	local model_options = vim.deepcopy(M.copilot_models)
	table.insert(model_options, { name = "Custom...", cost = "" })

	vim.ui.select(model_options, {
		prompt = "Select Copilot model (current: " .. current_model .. " — " .. current_cost .. "):",
		format_item = function(item)
			local display = item.name
			if item.cost and item.cost ~= "" then
				display = display .. " — " .. item.cost
			end
			if item.name == current_model then
				display = display .. " [current]"
			end
			return display
		end,
	}, function(choice)
		if choice == nil then
			return -- Cancelled
		end

		if choice.name == "Custom..." then
			-- Allow custom model input
			vim.ui.input({
				prompt = "Enter custom model name: ",
				default = current_model,
			}, function(custom_model)
				if custom_model and custom_model ~= "" then
					M.save_and_notify("copilot", {
						model = custom_model,
						configured = true,
					})
				end
			end)
		else
			M.save_and_notify("copilot", {
				model = choice.name,
				configured = true,
			})
		end
	end)
end

--- Interactive model selection
---@param provider string Provider name
---@param api_key string|nil API key
function M.interactive_model(provider, api_key)
	local default_model = M.default_models[provider] or ""
	local prompt = string.format("Enter model (default: %s): ", default_model)

	vim.ui.input({ prompt = prompt, default = default_model }, function(model)
		if model == nil then
			return -- Cancelled
		end

		-- Use default if empty
		if model == "" then
			model = default_model
		end

		-- Save credentials
		local credentials = {
			model = model,
		}

		if api_key and api_key ~= "" then
			credentials.api_key = api_key
		end

		-- For OpenAI, also ask for custom endpoint
		if provider == "openai" then
			M.interactive_endpoint(provider, credentials)
		else
			M.save_and_notify(provider, credentials)
		end
	end)
end

--- Interactive endpoint input for OpenAI-compatible providers
---@param provider string Provider name
---@param credentials table Current credentials
function M.interactive_endpoint(provider, credentials)
	vim.ui.input({
		prompt = "Custom endpoint (leave empty for default OpenAI): ",
	}, function(endpoint)
		if endpoint == nil then
			return -- Cancelled
		end

		if endpoint ~= "" then
			credentials.endpoint = endpoint
		end

		M.save_and_notify(provider, credentials)
	end)
end

--- Interactive Ollama configuration
function M.interactive_ollama_config()
	vim.ui.input({
		prompt = "Ollama host (default: http://localhost:11434): ",
		default = "http://localhost:11434",
	}, function(host)
		if host == nil then
			return -- Cancelled
		end

		if host == "" then
			host = "http://localhost:11434"
		end

		-- Get model
		local default_model = M.default_models.ollama
		vim.ui.input({
			prompt = string.format("Ollama model (default: %s): ", default_model),
			default = default_model,
		}, function(model)
			if model == nil then
				return -- Cancelled
			end

			if model == "" then
				model = default_model
			end

			M.save_and_notify("ollama", {
				host = host,
				model = model,
			})
		end)
	end)
end

--- Save credentials and notify user
---@param provider string Provider name
---@param credentials table Credentials to save
function M.save_and_notify(provider, credentials)
	if M.set_credentials(provider, credentials) then
		local msg = string.format("Saved %s configuration", provider:upper())
		if credentials.model then
			msg = msg .. " (model: " .. credentials.model .. ")"
		end
		utils.notify(msg, vim.log.levels.INFO)
	else
		utils.notify("Failed to save credentials", vim.log.levels.ERROR)
	end
end

--- Show current credentials status
function M.show_status()
	local providers = M.list_providers()

	-- Get current active provider
	local codetyper = require("codetyper")
	local current = codetyper.get_config().llm.provider

	local lines = {
		"Codetyper Credentials Status",
		"============================",
		"",
		"Storage: " .. get_credentials_path(),
		"Active:  " .. current:upper(),
		"",
	}

	for _, p in ipairs(providers) do
		local status_icon = p.configured and "✓" or "✗"
		local active_marker = p.name == current and " [ACTIVE]" or ""
		local source_info = ""
		if p.configured then
			source_info = p.source == "stored" and " (stored)" or " (config)"
		end
		local model_info = p.model and (" - " .. p.model) or ""

		table.insert(
			lines,
			string.format("  %s %s%s%s%s", status_icon, p.name:upper(), active_marker, source_info, model_info)
		)
	end

	table.insert(lines, "")
	table.insert(lines, "Commands:")
	table.insert(lines, "  :CoderAddApiKey      - Add/update credentials")
	table.insert(lines, "  :CoderSwitchProvider - Switch active provider")
	table.insert(lines, "  :CoderRemoveApiKey   - Remove stored credentials")

	utils.notify(table.concat(lines, "\n"))
end

--- Interactive remove credentials
function M.interactive_remove()
	local data = M.load()
	local configured = {}

	for provider, _ in pairs(data.providers or {}) do
		table.insert(configured, provider)
	end

	if #configured == 0 then
		utils.notify("No credentials configured", vim.log.levels.INFO)
		return
	end

	vim.ui.select(configured, {
		prompt = "Select provider to remove:",
	}, function(provider)
		if not provider then
			return
		end

		vim.ui.select({ "Yes", "No" }, {
			prompt = "Remove " .. provider:upper() .. " credentials?",
		}, function(choice)
			if choice == "Yes" then
				if M.remove_credentials(provider) then
					utils.notify("Removed " .. provider:upper() .. " credentials", vim.log.levels.INFO)
				else
					utils.notify("Failed to remove credentials", vim.log.levels.ERROR)
				end
			end
		end)
	end)
end

--- Set the active provider
---@param provider string Provider name
function M.set_active_provider(provider)
	local data = M.load()
	data.active_provider = provider
	data.updated = os.time()
	M.save(data)

	-- Also update the runtime config
	local codetyper = require("codetyper")
	local config = codetyper.get_config()
	config.llm.provider = provider

	utils.notify("Active provider set to: " .. provider:upper(), vim.log.levels.INFO)
end

--- Get the active provider from stored config
---@return string|nil Active provider
function M.get_active_provider()
	local data = M.load()
	return data.active_provider
end

--- Check if a provider is configured (from stored credentials OR config)
---@param provider string Provider name
---@return boolean configured, string|nil source
local function is_provider_configured(provider)
	-- Check stored credentials first
	local data = M.load()
	local stored = data.providers and data.providers[provider]
	if stored then
		if stored.configured or stored.api_key or provider == "ollama" or provider == "copilot" then
			return true, "stored"
		end
	end

	-- Check codetyper config
	local ok, codetyper = pcall(require, "codetyper")
	if not ok then
		return false, nil
	end

	local config = codetyper.get_config()
	if not config or not config.llm then
		return false, nil
	end

	local provider_config = config.llm[provider]
	if not provider_config then
		return false, nil
	end

	-- Check for API key in config or environment
	if provider == "claude" then
		if provider_config.api_key or vim.env.ANTHROPIC_API_KEY then
			return true, "config"
		end
	elseif provider == "openai" then
		if provider_config.api_key or vim.env.OPENAI_API_KEY then
			return true, "config"
		end
	elseif provider == "gemini" then
		if provider_config.api_key or vim.env.GEMINI_API_KEY then
			return true, "config"
		end
	elseif provider == "copilot" then
		-- Copilot just needs copilot.lua installed
		return true, "config"
	elseif provider == "ollama" then
		-- Ollama just needs host configured
		if provider_config.host then
			return true, "config"
		end
	end

	return false, nil
end

--- Interactive switch provider
function M.interactive_switch_provider()
	local all_providers = { "claude", "openai", "gemini", "copilot", "ollama" }
	local available = {}
	local sources = {}

	for _, provider in ipairs(all_providers) do
		local configured, source = is_provider_configured(provider)
		if configured then
			table.insert(available, provider)
			sources[provider] = source
		end
	end

	if #available == 0 then
		utils.notify("No providers configured. Use :CoderAddApiKey or add to your config.", vim.log.levels.WARN)
		return
	end

	local codetyper = require("codetyper")
	local current = codetyper.get_config().llm.provider

	vim.ui.select(available, {
		prompt = "Select provider (current: " .. current .. "):",
		format_item = function(item)
			local marker = item == current and " [active]" or ""
			local source_marker = sources[item] == "stored" and " (stored)" or " (config)"
			return item:upper() .. marker .. source_marker
		end,
	}, function(provider)
		if provider then
			M.set_active_provider(provider)
		end
	end)
end

return M
