local validate = require('cryption.lib.validate')

local M = {}

---Extracts the file extension from a filename. Removes the '.age' suffix.
---@param filename string
---@return string|nil # The extracted extension, or nil if not found.
function M.extract_filetype(filename)
  local base = filename:gsub('%.age$', '')
  local ext = base:match('%.([^%.]+)$')
  return ext
end

--- Retrieves buffer information including buffer number, file path, and file type.
--- If no buffer name is provided, it uses the current buffer's information.
--- @param bufname? string
--- @param filetype? string
--- @return { bufnr: integer, filepath: string, filetype: string|nil }
function M.get_bufinfo(bufname, filetype)
  local bufinfo = {}
  if validate.is_valid_str(bufname) then
    bufinfo.filepath = vim.fs.normalize(vim.fn.fnamemodify(bufname, ':p'))
    bufinfo.bufnr = vim.fn.bufnr(bufinfo.filepath)
  else
    bufinfo.bufnr = vim.api.nvim_get_current_buf()
    bufinfo.filepath = vim.fs.normalize(vim.api.nvim_buf_get_name(bufinfo.bufnr))
  end
  bufinfo.filetype = filetype or M.extract_filetype(bufinfo.filepath)
  return bufinfo
end

--- Resets the contents of a given buffer.
--- @param bufnr number
--- @param callback function The callback function to execute after resetting.
function M.reset_buffer_contents(bufnr, callback)
  local undolevels = vim.bo[bufnr].undolevels
  vim.api.nvim_set_option_value('undolevels', -1, { buf = bufnr })
  if type(callback) == 'function' then
    callback()
  else
    error('callback must be "function".')
  end
  vim.api.nvim_set_option_value('undolevels', undolevels, { buf = bufnr })
  vim.api.nvim_set_option_value('modified', false, { buf = bufnr })
end

--- Creates or recreates the scratch buffer.
--- @param uri string The URI part of the buffer.
--- @param bufname string The buffer name.
--- @param filetype string The file type of the buffer.
--- @param contents? string The content to set in the buffer.
--- @return number # bufnr of the created buffer.
function M.create_scratch_contents(uri, bufname, filetype, contents)
  local bufnr = vim.api.nvim_create_buf(true, true)
  local filename = ('%s%s'):format(uri, bufname)
  local exist_bufnr = vim.fn.bufnr(filename)
  if exist_bufnr ~= -1 then
    vim.api.nvim_buf_delete(exist_bufnr, { force = true })
  end
  vim.api.nvim_buf_set_name(bufnr, filename)

  if contents then
    M.reset_buffer_contents(bufnr, function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(contents, '\n'))
    end)
  end

  vim.api.nvim_set_option_value('filetype', filetype, { buf = bufnr })
  vim.api.nvim_set_option_value('buftype', 'acwrite', { buf = bufnr })

  return bufnr
end

--- Updates or deletes the specified source buffer.
--- @param source_bufnr number
function M.renew_buffer(source_bufnr)
  vim.api.nvim_buf_delete(source_bufnr, { force = true, unload = false })
  vim.cmd.clearjumps()
end

--- Sets up autocmds for buffer lifecycle management.
--- @param augroup number
--- @param buffers table<number,boolean>
--- @param bufnr number
--- @param callback function The callback function to be executed on `BufWriteCmd` event.
function M.lifecycle(augroup, buffers, bufnr, callback)
  buffers[bufnr] = true

  vim.api.nvim_create_autocmd('BufWriteCmd', {
    group = augroup,
    buffer = bufnr,
    callback = callback,
  })

  vim.api.nvim_create_autocmd('BufWipeout', {
    group = augroup,
    buffer = bufnr,
    callback = function()
      buffers[bufnr] = nil
      if vim.tbl_isempty(buffers) then
        pcall(vim.api.nvim_del_augroup_by_id, augroup)
      end
    end,
  })
end

return M
