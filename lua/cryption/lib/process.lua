---@class process
local M = {}

---@alias OnExit fun(obj:vim.SystemCompleted?)
---@alias RunSignature fun(cmd: string[], opts?: vim.SystemOpts, on_exit?: OnExit): vim.SystemObj|nil

---@type table<string, vim.SystemObj>
local jobs = {}

---@param cmd_id string|nil
---@param obj vim.SystemCompleted
---@param on_exit? OnExit
local function handle_exit(cmd_id, obj, on_exit)
  vim.schedule(function()
    if cmd_id then
      jobs[cmd_id] = nil
    end

    if on_exit then
      on_exit(obj)
    end
  end)
end

---@param single boolean
---@param cmd string[]
---@param opts? vim.SystemOpts
---@param on_exit? OnExit
---@return vim.SystemObj|nil
local function run(single, cmd, opts, on_exit)
  opts = opts or {}
  local cmd_id = ('%s_%s'):format(cmd[1], cmd[2] or '')

  if jobs[cmd_id] then
    if single then
      return nil
    else
      jobs[cmd_id]:kill('sigterm')
    end
  end

  opts.text = opts.text ~= false
  jobs[cmd_id] = vim.system(cmd, opts, function(obj)
    handle_exit(cmd_id, obj, on_exit)
  end)

  return jobs[cmd_id]
end

---@type  RunSignature
function M.override(cmd, opts, on_exit)
  return run(false, cmd, opts, on_exit)
end

---@param cmd string[]
---@param opts? vim.SystemOpts
---@return vim.SystemCompleted
function M.sync(cmd, opts)
  opts = opts or {}
  opts.text = opts.text ~= false
  return vim.system(cmd, opts):wait()
end

return M
