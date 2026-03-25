--- Set appropriate filetype for coder files based on extension
local function set_coder_filetype()
  local filepath = vim.fn.expand("%:p")

  local ext = filepath:match("%.codetyper%.(%w+)$")

  if ext then
    local ft_map = {
      ts = "typescript",
      tsx = "typescriptreact",
      js = "javascript",
      jsx = "javascriptreact",
      py = "python",
      lua = "lua",
      go = "go",
      rs = "rust",
      rb = "ruby",
      java = "java",
      c = "c",
      cpp = "cpp",
      cs = "cs",
      json = "json",
      yaml = "yaml",
      yml = "yaml",
      md = "markdown",
      html = "html",
      css = "css",
      scss = "scss",
      vue = "vue",
      svelte = "svelte",
    }

    local filetype = ft_map[ext] or ext
    vim.bo.filetype = filetype
  end
end

return set_coder_filetype
