local utils = require("codetyper.support.utils")

--- Read attached files from prompt content
---@param prompt_content string Prompt content
---@param base_path string Base path to resolve relative file paths
---@return table[] attached_files List of {path, content} tables
local function read_attached_files(prompt_content, base_path)
  local extract_file_references = require("codetyper.parser.extract_file_references")
  local file_refs = extract_file_references(prompt_content)
  local attached = {}
  local cwd = vim.fn.getcwd()
  local base_dir = vim.fn.fnamemodify(base_path, ":h")

  for _, ref in ipairs(file_refs) do
    local file_path = nil

    local cwd_path = cwd .. "/" .. ref
    if utils.file_exists(cwd_path) then
      file_path = cwd_path
    else
      local rel_path = base_dir .. "/" .. ref
      if utils.file_exists(rel_path) then
        file_path = rel_path
      end
    end

    if file_path then
      local content = utils.read_file(file_path)
      if content then
        table.insert(attached, {
          path = ref,
          full_path = file_path,
          content = content,
        })
      end
    end
  end

  return attached
end

return read_attached_files
