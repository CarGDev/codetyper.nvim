---@mod codetyper.executor.validate Plan validation forwarder
---@brief [[
--- Forwards validation requests to the Python agent.
--- Lua only checks response schema, never validates plan content.
---@brief ]]

local M = {}

local agent_client = require("codetyper.transport.agent_client")

---@class ValidationResult
---@field valid boolean Whether the plan is valid
---@field errors string[] List of errors if invalid
---@field warnings string[] List of warnings

--- Validate a plan by forwarding to the Python agent
---@param plan table The plan to validate
---@param files table<string, string> Map of file paths to their content
---@return ValidationResult
function M.validate(plan, files)
	-- If agent is not running, skip validation (trust the plan)
	if not agent_client.is_running() then
		return {
			valid = true,
			errors = {},
			warnings = { "Agent not running, skipping validation" },
		}
	end

	-- Forward to Python agent
	local response, err = agent_client.send_request("validate_plan", {
		plan = plan,
		original_files = files,
	})

	if err then
		return {
			valid = false,
			errors = { "Validation request failed: " .. err },
			warnings = {},
		}
	end

	-- Check response schema
	if type(response) ~= "table" then
		return {
			valid = false,
			errors = { "Invalid validation response from agent" },
			warnings = {},
		}
	end

	return {
		valid = response.valid == true,
		errors = response.errors or {},
		warnings = response.warnings or {},
	}
end

--- Quick check if a plan looks structurally valid (no agent call)
---@param plan table The plan to check
---@return boolean valid
---@return string|nil error
function M.quick_check(plan)
	if type(plan) ~= "table" then
		return false, "Plan must be a table"
	end

	if not plan.steps or type(plan.steps) ~= "table" then
		return false, "Plan must have steps array"
	end

	for i, step in ipairs(plan.steps) do
		if type(step) ~= "table" then
			return false, "Step " .. i .. " must be a table"
		end
		if not step.action or type(step.action) ~= "string" then
			return false, "Step " .. i .. " must have action string"
		end
	end

	return true, nil
end

return M
