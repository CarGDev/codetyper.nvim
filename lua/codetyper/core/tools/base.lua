---@mod codetyper.agent.tools.base Base tool definition
---@brief [[
--- Base metatable for all LLM tools.
--- Tools extend this base to provide structured AI capabilities.
---@brief ]]

---@class CoderToolParam
---@field name string Parameter name
---@field description string Parameter description
---@field type string Parameter type ("string", "number", "boolean", "table")
---@field optional? boolean Whether the parameter is optional
---@field default? any Default value for optional parameters

---@class CoderToolReturn
---@field name string Return value name
---@field description string Return value description
---@field type string Return type
---@field optional? boolean Whether the return is optional

---@class CoderToolOpts
---@field on_log? fun(message: string) Log callback
---@field on_complete? fun(result: any, error: string|nil) Completion callback
---@field session_ctx? table Session context
---@field streaming? boolean Whether response is still streaming
---@field confirm? fun(message: string, callback: fun(ok: boolean)) Confirmation callback

---@class CoderTool
---@field name string Tool identifier
---@field description string|fun(): string Tool description
---@field params CoderToolParam[] Input parameters
---@field returns CoderToolReturn[] Return values
---@field requires_confirmation? boolean Whether tool needs user confirmation
---@field func fun(input: table, opts: CoderToolOpts): any, string|nil Tool implementation

local M = {}
M.__index = M

--- Call the tool function
---@param opts CoderToolOpts Options for the tool call
---@return any result
---@return string|nil error
function M:__call(opts, on_log, on_complete)
	return self.func(opts, on_log, on_complete)
end

--- Get the tool description
---@return string
function M:get_description()
	if type(self.description) == "function" then
		return self.description()
	end
	return self.description
end

--- Validate input against parameter schema
---@param input table Input to validate
---@return boolean valid
---@return string|nil error
function M:validate_input(input)
	if not self.params then
		return true
	end

	for _, param in ipairs(self.params) do
		local value = input[param.name]

		-- Check required parameters
		if not param.optional and value == nil then
			return false, string.format("Missing required parameter: %s", param.name)
		end

		-- Type checking
		if value ~= nil then
			local actual_type = type(value)
			local expected_type = param.type

			-- Handle special types
			if expected_type == "integer" and actual_type == "number" then
				if math.floor(value) ~= value then
					return false, string.format("Parameter %s must be an integer", param.name)
				end
			elseif expected_type ~= actual_type and expected_type ~= "any" then
				return false, string.format("Parameter %s must be %s, got %s", param.name, expected_type, actual_type)
			end
		end
	end

	return true
end

--- Generate JSON schema for the tool (for LLM function calling)
---@return table schema
function M:to_schema()
	local properties = {}
	local required = {}

	for _, param in ipairs(self.params or {}) do
		local prop = {
			type = param.type == "integer" and "number" or param.type,
			description = param.description,
		}

		if param.default ~= nil then
			prop.default = param.default
		end

		properties[param.name] = prop

		if not param.optional then
			table.insert(required, param.name)
		end
	end

	return {
		type = "function",
		function_def = {
			name = self.name,
			description = self:get_description(),
			parameters = {
				type = "object",
				properties = properties,
				required = required,
			},
		},
	}
end

return M
