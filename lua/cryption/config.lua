local helper = require('cryption.helper.config')
local info = require('cryption.info')

---@class Config
local M = {}

local schema = {
  age = {
    enable = { type = 'boolean', default = false, optional = true },
    age = { type = 'string', default = 'age', optional = true },
    keygen = { type = 'string', default = 'age-keygen', optional = true },
    inspect = { type = 'string', default = 'age-inspect', optional = true },
  },
  sops = {
    enable = { type = 'boolean', default = false, optional = true },
    sops = { type = 'string', default = 'sops' },
    encrypt_default_output_type = { type = 'string', default = 'yaml', optional = true },
  },
}

local schema_exec = {
  age = { 'age', 'keygen', 'inspect' },
  sops = { 'sops' },
}

local _invalid_keys = nil

---@type table<string, table|boolean> User-specified modifications
local user_config = {}

---@type table<string, table> The final validated state used at runtime
local active_config = {}

---@class CommonMethods
---@field ref fun(self: table, mod_name: Schemas): table|nil Returns a reference to the active master configuration table.
---@field reset fun(self: table, mod_name: Schemas) Resets the current instance values back to the master configuration state.
local common_methods = {}

---Returns a reference to the active master configuration table.
---@param mod_name Schemas The target module name.
---@return table|nil The master configuration table.
function common_methods:ref(mod_name)
  return active_config[mod_name]
end

---Resets the current instance values back to the master configuration state.
---@param mod_name Schemas The module name to fetch master values from.
function common_methods:reset(mod_name)
  local master = active_config[mod_name]
  if master then
    for k, v in pairs(master) do
      self[k] = v
    end
  end
end

local function renew_exe_path(mod_name)
  local mod_config = active_config[mod_name]
  local items = schema_exec[mod_name] or {}

  local executables = {}
  for _, item in ipairs(items) do
    if type(mod_config[item]) == 'string' then
      executables[item] = mod_config[item]
    end
  end

  local existence, absences = helper.detect_exe_path(executables)
  if #absences > 0 then
    return false, absences
  end

  for item, path in pairs(existence) do
    mod_config[item] = path
  end

  return true, {}
end

---@type Schemas[]
local valid_mods = vim.tbl_keys(schema)

---Validates, processes, and retrieves a configuration instance for a specific module.
---@param mod_name Modules
---@param mod_config? table|boolean for test uses
---@return table A validated configuration instance with dynamic Vim variable support.
function M.get(mod_name, mod_config)
  vim.validate('mod_name', mod_name, function()
    return vim.iter(valid_mods):find(mod_name) == mod_name
  end, true, 'module name')

  local plugin_name = info.name
  local mod_schema = schema[mod_name]
  local failed = {}
  local config_spec = mod_config or user_config --[[@as table]]
  local new_config = helper.resolve_config(plugin_name, mod_name, mod_schema, config_spec[mod_name], failed)

  if #failed > 0 then
    vim.schedule(function()
      local header = ("Configuration type error in '%s':"):format(mod_name)
      local msg = header .. '\n' .. table.concat(failed, '\n')

      info:echo(msg, 'ERROR', false)
    end)
  end

  active_config[mod_name] = new_config

  local ok, absences = renew_exe_path(mod_name)

  if not ok then
    local msg = ('Not found executables: %s'):format(table.concat(absences, ', '))
    error(info.label .. msg)
  end

  local instance = vim.deepcopy(active_config[mod_name])

  return setmetatable(instance, { __index = common_methods })
end

function M.setup(user_spec)
  _invalid_keys = nil
  user_config, _invalid_keys = helper.validate_options(schema, user_spec or {})

  if _invalid_keys and #_invalid_keys > 0 then
    vim.schedule(function()
      local msg = ('Unknown key detected in %s.nvim Run :checkhealth %s'):format(info.name, info.name)
      info:echo(msg, 'WARN', true, {})
    end)
  end
end

---Retrieves a list of invalid or unknown configuration keys for health checks.
---@return string[]|nil A list of invalid keys, or nil if none.
function M.get_invalid_keys()
  return _invalid_keys
end

return M
