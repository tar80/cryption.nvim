local M = {}

local HL_LEVELS = {
  INFO = 'OkMsg',
  WARN = 'WarningMsg',
  ERROR = 'ErrorMsg',
}

---@private
local function get_log_level(level)
  local t = type(level)
  if t == 'string' then
    level = vim.log.levels[level]
  elseif t == 'number' then
    level = math.max(0, math.min(4, level))
  end
  return level or vim.log.levels.INFO
end

---Display a message in the Neovim command line via `nvim_echo`.
---
---The message is prefixed with |Information.label| and highlighted according
---to `level`. When `msg` is a string, it is automatically wrapped with the
---appropriate highlight group. Pass a `{text, hl}` tuple to override.
---
---@param msg string|[string, string|integer?] Message text, or a `{text, hl}` tuple.
---@param level? 'INFO'|'WARN'|'ERROR' Highlight level. Defaults to `'INFO'`.
---@param history? boolean Whether to add the message to message history. Defaults to `false`.
---@param opts? vim.api.keyset.echo_opts Additional options passed to `nvim_echo`.
function M:echo(msg, level, history, opts)
  level = level or 'INFO'
  history = history or false
  opts = opts or {}
  opts.id = self.name
  msg = (type(msg) == 'string' and { msg, HL_LEVELS[level] } or msg) --[[@as table]]
  vim.api.nvim_echo({ { self.label, 'Label' }, msg }, history, opts)
end

---Send a notification via `vim.notify` or `vim.notify_once`.
---
---`level` accepts either a string key (`'INFO'`, `'WARN'`, `'ERROR'`) or
---a numeric `vim.log.levels` value. The notification title is set to
---|Information.name|.
---
---@param msg string Notification message.
---@param level? 'INFO'|'WARN'|'ERROR'|integer Log level. Defaults to `INFO`.
---@param once? boolean If `true`, uses `vim.notify_once`. Defaults to `false`.
function M:notify(msg, level, once)
  local notif = once and 'notify_once' or 'notify'
  level = get_log_level(level)
  vim[notif](msg, level, { title = self.name })
end

---Augment a plugin info table with label, echo, and notify support.
---
---The table must have a `name` field set before calling this function.
---A `label` field is generated as `"[name] "` and the methods
---|Information:echo()| and |Information:notify()| are attached via metatable.
---
---@param self table Plugin info table. Must have `self.name` set.
---@return self Information The augmented info table.
function M.instance(self)
  assert(self.name, 'Requires "name" parameter.')
  self.label = ('[%s] '):format(self.name)
  return setmetatable(self, { __index = M })
end

return M
