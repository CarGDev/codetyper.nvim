--- Safe synchronous facade for the shared import planner.

local imports = require("codetyper.core.agent.tools.imports")

local M = {}

local function bounded_error(value)
  local message = tostring(value or "import request failed"):gsub("[%z\1-\31\127]", " ")
  if #message > 256 then
    message = message:sub(1, 256)
  end
  return message
end

local function error_result(message)
  return {
    status = "error",
    data = nil,
    error = bounded_error(message),
    stale = false,
  }
end

local function result_from_plan(plan, action)
  return {
    status = "available",
    data = {
      action = action,
      changed = action == "inserted",
      imports_added = action == "inserted" and plan.imports_added or 0,
      language = plan.language,
      path = plan.path,
    },
    error = nil,
    stale = false,
  }
end

--- Plan one safe import without mutating a file or buffer.
---@param args table {root,path,statement,bufnr,filetype}
---@return table|nil plan
---@return string|nil error
function M.plan(args)
  if type(args) ~= "table" then
    return nil, "import arguments must be an object"
  end
  return imports.plan(args)
end

--- Add one import to a project-relative file or an open buffer.
---@param args table {root,path,statement,bufnr,filetype}
---@return table result
function M.run(args)
  local plan, plan_error = M.plan(args)
  if not plan then
    return error_result(plan_error)
  end
  if plan.status == "noop" then
    return result_from_plan(plan, "noop")
  end
  local applied, apply_error = imports.apply(plan)
  if not applied then
    return error_result(apply_error)
  end
  return result_from_plan(plan, "inserted")
end

--- Callback-compatible facade for future tool dispatch.
---@param args table Tool arguments
---@param callback fun(result: table)|nil Completion callback
---@param opts table|nil Reserved injectable options
---@return table handle
function M.call(args, callback, opts)
  opts = opts or {}
  local result = M.run(args, opts)
  if type(callback) == "function" then
    callback(result)
  end
  return { cancel = function() end }
end

M.add = M.run
M.add_import = M.run
M.insert = M.run
M.apply = M.run
M.execute = M.run
M.dispatch = M.call

return M
