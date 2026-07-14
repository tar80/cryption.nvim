local M = {}

---Check if a path exists.
---@param filepath string
---@return boolean
function M.is_file(filepath)
  local stat = vim.uv.fs_stat(vim.fs.normalize(filepath))

  return (stat and stat.type == 'file' or false)
end

return M
