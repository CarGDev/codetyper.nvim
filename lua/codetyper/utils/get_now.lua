local function now()
  return vim.uv and vim.uv.now() or (os.clock() * 1000)
end

return now
