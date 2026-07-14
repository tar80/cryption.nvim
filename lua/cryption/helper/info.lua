local M = {}

local HL_LEVELS = {
  INFO = 'OkMsg',
  WARN = 'WarningMsg',
  ERROR = 'ErrorMsg',
}

local function get_log_level(level)
  local t = type(level)
  if t == 'string' then
    level = vim.log.levels[level]
  elseif t == 'number' then
    level = math.max(0, math.min(4, level))
  end
  return level or vim.log.levels.INFO
end

---@param msg string|[string, string|integer?]
---@param level? 'INFO'|'WARN'|'ERROR'
---@param history? boolean
---@param opts?  vim.api.keyset.echo_opts
function M:echo(msg, level, history, opts)
  level = level or 'INFO'
  history = history or false
  opts = opts or {}
  opts.id = self.name
  msg = (type(msg) == 'string' and { msg, HL_LEVELS[level] } or msg) --[[@as table]]
  vim.api.nvim_echo({ { self.label, 'Label' }, msg }, history, opts)
end

function M:notify(msg, level, once)
  local notif = once and 'notify_once' or 'notify'
  level = get_log_level(level)
  vim[notif](msg, level, { title = self.name })
end

---@param self table
---@return table self
function M.instance(self)
  assert(self.name, 'Requires "name" parameter.')

  self.label = ('[%s] '):format(self.name)

  return setmetatable(self, { __index = M })
end

return M
