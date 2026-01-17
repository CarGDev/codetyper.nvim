---@mod codetyper.executor.apply_plan Pure plan execution
---@brief [[
--- Executes plans received from the agent. No validation or decision-making.
--- The agent has already validated the plan before sending it here.
---@brief ]]

local M = {}

local file_ops = require("codetyper.executor.file_ops")
local logs = require("codetyper.adapters.nvim.ui.logs")

---@class PlanStep
---@field action string Action type: "read", "write", "edit", "delete", "bash"
---@field target string File path or command
---@field params table Action-specific parameters
---@field depends_on? string[] IDs of steps this depends on

---@class Plan
---@field steps PlanStep[] Steps to execute in order
---@field dependencies? table<string, string[]> Step dependency graph
---@field rollback? PlanStep[] Steps to undo the plan if needed

---@class PlanResult
---@field success boolean Whether all steps succeeded
---@field results table<number, {success: boolean, result: any, error: string|nil}> Per-step results
---@field failed_step? number Index of first failed step

--- Execute a single plan step
---@param step PlanStep
---@return boolean success
---@return any result
---@return string|nil error
local function execute_step(step)
	local action = step.action
	local target = step.target
	local params = step.params or {}

	if action == "read" then
		local content, err = file_ops.read_file(target)
		return content ~= nil, content, err

	elseif action == "write" then
		local success, err = file_ops.write_file(target, params.content)
		return success, success and "Written" or nil, err

	elseif action == "edit" then
		local success, err = file_ops.edit_file(target, params.old_string, params.new_string)
		return success, success and "Edited" or nil, err

	elseif action == "delete" then
		local success, err = file_ops.delete_file(target)
		return success, success and "Deleted" or nil, err

	elseif action == "bash" then
		local output, err = file_ops.execute_command(params.command or target, params.timeout)
		return output ~= nil, output, err

	elseif action == "create_dir" then
		local success, err = file_ops.ensure_dir(target)
		return success, success and "Created directory" or nil, err

	else
		return false, nil, "Unknown action: " .. tostring(action)
	end
end

--- Apply a plan received from the agent
---@param plan Plan The plan to execute
---@param opts? {on_step?: fun(step: number, action: string), on_result?: fun(step: number, result: any)}
---@return PlanResult
function M.apply(plan, opts)
	opts = opts or {}

	local result = {
		success = true,
		results = {},
		failed_step = nil,
	}

	if not plan or not plan.steps or #plan.steps == 0 then
		result.success = false
		return result
	end

	for i, step in ipairs(plan.steps) do
		-- Notify step start
		if opts.on_step then
			opts.on_step(i, step.action)
		end

		-- Log the step
		logs.add({
			type = "action",
			message = string.format("Step %d/%d: %s %s", i, #plan.steps, step.action, step.target or ""),
		})

		-- Execute the step
		local success, step_result, err = execute_step(step)

		-- Store result
		result.results[i] = {
			success = success,
			result = step_result,
			error = err,
		}

		-- Notify result
		if opts.on_result then
			opts.on_result(i, result.results[i])
		end

		-- Log result
		if success then
			logs.add({ type = "result", message = "  \226\142\191  Done" })
		else
			logs.add({ type = "error", message = "  \226\142\191  Failed: " .. (err or "unknown error") })
		end

		-- Stop on failure
		if not success then
			result.success = false
			result.failed_step = i
			break
		end
	end

	return result
end

--- Execute rollback steps if plan failed
---@param plan Plan The plan with rollback steps
---@param failed_step number The step that failed
---@return boolean success
function M.rollback(plan, failed_step)
	if not plan.rollback or #plan.rollback == 0 then
		return true
	end

	logs.add({ type = "action", message = "Rolling back changes..." })

	for i, step in ipairs(plan.rollback) do
		local success, _, err = execute_step(step)
		if not success then
			logs.add({ type = "error", message = "Rollback step " .. i .. " failed: " .. (err or "unknown") })
		end
	end

	return true
end

return M
