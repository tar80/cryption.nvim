---A configuration instance returned by |M.config_instance()|.
---@class ConfigInstance
---@field setup fun(user_spec: {age?:AgeConfig, sops?:SopsConfig}) Validates and stores user configuration. Call this from the plugin's `setup()`.
---@field get fun(mod_name: string, mod_config?: table): GetMethods Resolves and returns a validated configuration instance for the given module.
---@field get_invalid_keys fun(): string[]|nil Returns unknown keys detected during `setup()`, or nil if none.

---Methods available on every instance returned by |ConfigInstance.get|.
---@class GetMethods
---Returns a direct reference to the active config
---table for `mod_name`. Because this is a live reference, values added by
---later `get()` calls are immediately visible through any existing instance.
---@field ref fun(self: table, mod_name: string): table|nil
---Restores the instance's values to the master
---config state, removing any keys added at runtime.
---@field reset fun(self: table, mod_name: string)
---When a key has `vim_var` declared in |ConfigSpec|,
---calling the instance as a function gives the corresponding Vim variable
---(`vim.g.*` or `vim.b.*`) priority over the in-memory value. Falls back
---to the in-memory value if the Vim variable is not set.
---@field __call fun(key)

---@class ConfigSpec
---@field type string|string[] Expected type(s) passed to `vim.validate()`.
---@field default any Fallback value when the user omits the key or provides an invalid value.
---@field optional? boolean If true, `nil` is accepted without a validation error.
---@field message? string Custom error message for validation failures.
---@field func? fun(value:any):any Optional post-processing function applied after validation.
---@field vim_var? '"global"'|'"local"' If set, registers a Vim variable (`g:` or `b:`) for runtime override.

---A schema node is either a |ConfigSpec| leaf or a nested table of specs.
---@alias ConfigSchema table<string, ConfigSpec|ConfigSchema>

local M = {}

---Capitalize the first lowercase character of a string.
---@param name? string Input string.
---@return string|nil capitalized String with the first character uppercased.
function M.capitalize(name)
  return (name and name:gsub('^%l', string.upper))
end

---Detect executable paths from a command table.
---
---Resolves each value using `vim.fn.exepath()` and normalizes the path.
---Commands that cannot be found are collected separately as absences.
---
---@param commands table<string, string> Table mapping keys to executable names or paths.
---@return table<string, string> existence Resolved and normalized executable paths.
---@return string[] absences Executable names that were not found.
function M.detect_exe_path(commands)
  local existence = {}
  local absences = {}

  for key, filepath in pairs(commands) do
    local exe_path = vim.fn.exepath(filepath)

    if exe_path ~= '' then
      existence[key] = vim.fs.normalize(exe_path)
    else
      table.insert(absences, filepath)
    end
  end

  return existence, absences
end

---Recursively checks user configuration for unknown keys against a schema.
---@param schema_node table Current schema node.
---@param user_node table Current user configuration node.
---@param prefix string Current key prefix for error messages.
---@param unknown_keys string[] Accumulator for unknown key paths.
---@private
local function check_unknown_keys(schema_node, user_node, prefix, unknown_keys)
  for key, value in pairs(user_node) do
    local current_key = prefix == '' and key or ('%s.%s'):format(prefix, key)
    local schema = schema_node[key]
    local v_type = type(value)

    if schema == nil then
      table.insert(unknown_keys, current_key)
    else
      local is_branch = type(schema) == 'table' and schema.type == nil

      if is_branch then
        if v_type == 'table' then
          check_unknown_keys(schema, value, current_key, unknown_keys)
        else
          table.insert(unknown_keys, ('%s (must be a table)'):format(current_key))
        end
      end
    end
  end
end

---Validate a user configuration table against a schema.
---
---Only checks for unknown keys. Type validation is handled separately
---in |M.resolve_config()| via `vim.validate()`.
---
---@param schema table Configuration schema.
---@param user_spec table User configuration.
---@return table validated_spec The original user configuration (passed through).
---@return string[]|nil unknown_keys List of unknown key paths, or nil if none exist.
function M.validate_options(schema, user_spec)
  local unknown_keys = {}

  check_unknown_keys(schema, user_spec, '', unknown_keys)

  if #unknown_keys == 0 then
    unknown_keys = nil
  end

  return user_spec, unknown_keys
end

---Generate metadata for a Vim variable.
---@param plugin_name string Plugin name used as the variable prefix.
---@param scope "global"|"local" Variable scope.
---@param mod_name string Module name.
---@param key string Configuration key.
---@return { scope: '"g"'|'"b"', name: string }
---@private
local function get_vim_var(plugin_name, scope, mod_name, key)
  return {
    scope = scope == 'local' and 'b' or 'g',
    name = ('%s_%s_%s'):format(plugin_name, mod_name, key),
  }
end

---Returns true if the schema node is a branch (nested schema), not a leaf spec.
---@param node any
---@return boolean
---@private
local function is_branch_node(node)
  return type(node) == 'table' and node.type == nil
end

---Validate a single value using `vim.validate()`.
---Returns the default if the value is nil or fails validation.
---@param key string Configuration key name.
---@param value any User-supplied value.
---@param spec ConfigSpec Schema specification for this key.
---@param failed string[] Accumulator for validation error messages.
---@return any Validated value, or `spec.default` on failure.
---@private
local function validate_value(key, value, spec, failed)
  if value == nil then
    return spec.default
  end

  local ok, err = pcall(vim.validate, key, value, spec.type, spec.optional, spec.message)

  if not ok then
    table.insert(failed, err)
    return spec.default
  end

  return value
end

---Register a Vim variable entry for a configuration key.
---Stores metadata under `active._vim_vars[key]` for later resolution
---via the `__call` metamethod on configuration instances.
---@param active table The active configuration table being built.
---@param plugin_name string Plugin name.
---@param mod_name string Module name.
---@param key string Configuration key.
---@param spec ConfigSpec Schema specification containing `vim_var` scope.
---@private
local function register_vim_var(active, plugin_name, mod_name, key, spec)
  active._vim_vars = active._vim_vars or {}
  active._vim_vars[key] = get_vim_var(plugin_name, spec.vim_var, mod_name, key)
end

---Resolve and validate configuration values from a schema.
---
---Recursively walks the schema, validates each value, applies optional
---post-processing via `spec.func`, and registers Vim variable metadata
---for keys that declare `vim_var`.
---
---@param plugin_name string Plugin name used in Vim variable naming.
---@param mod_name string Module name used in Vim variable naming.
---@param mod_schema table Configuration schema for this module.
---@param user_data? table User-supplied configuration values.
---@param failed string[] Accumulator for validation error messages.
---@return table active Resolved configuration table with validated values.
function M.resolve_config(plugin_name, mod_name, mod_schema, user_data, failed)
  local active = {}
  local user_table = type(user_data) == 'table' and user_data or {}

  for key, spec in pairs(mod_schema) do
    if is_branch_node(spec) then
      active[key] = M.resolve_config(plugin_name, mod_name, spec, user_table[key], failed)
    else
      local value = validate_value(key, user_table[key], spec, failed)

      if spec.func and type(spec.func) == 'function' then
        value = spec.func(value)
      end

      if spec.vim_var then
        register_vim_var(active, plugin_name, mod_name, key, spec)
      end

      active[key] = value
    end
  end

  return active
end

---Resolve executable paths declared in `schema_exec` for a module.
---
---Looks up each key listed in `schema_exec[mod_name]` from the master config,
---resolves them via `detect_exe_path()`, and writes the normalized paths back.
---
---@param config { master: table } Internal config state table.
---@param schema_exec table<string, string[]> Map of module names to executable key lists.
---@param mod_name string Target module name.
---@return boolean ok True if all executables were found.
---@return string[] absences List of executable names that were not found.
---@private
local function renew_exe_path(config, schema_exec, mod_name)
  local mod_config = config.master[mod_name]
  local items = schema_exec[mod_name] or {}
  local executables = {}

  for _, item in ipairs(items) do
    if type(mod_config[item]) == 'string' then
      executables[item] = mod_config[item]
    end
  end

  local existence, absences = M.detect_exe_path(executables)
  if #absences > 0 then
    return false, absences
  end

  for item, path in pairs(existence) do
    mod_config[item] = path
  end

  return true, {}
end

---Create a self-contained configuration instance for a plugin module.
---
---Encapsulates the full configuration lifecycle: user spec storage, validation,
---resolution, executable path detection, and instance creation with shared
---metamethods. See |ConfigInstance| and |CommonMethods| for the returned API.
---
---@param info table Plugin info object. Must expose `info.name` (string) and `info:echo(msg, level, notify, opts)`.
---@param schema ConfigSchema Full configuration schema for all modules. See |ConfigSchema|.
---@param schema_exec table<string, string[]>|nil Optional map of module names to executable key lists. Pass `nil` if the plugin has no executables to resolve.
---@return ConfigInstance
---@usage [[
---local M = require('myplugin.helper.config').config_instance(info, schema, schema_exec)
---@usage ]]
function M.config_instance(info, schema, schema_exec)
  local _invalid_keys = nil
  local _config = { user = {}, active = {}, master = {} }
  local _mt = {
    __index = {
      ref = function(_, mod_name)
        return _config.active[mod_name]
      end,
      reset = function(self, mod_name)
        local master = _config.master[mod_name]
        if master then
          for k in pairs(self) do
            if master[k] == nil then
              self[k] = nil
            end
          end
          for k, v in pairs(master) do
            self[k] = v
          end
        end
      end,
    },
    __call = function(t, key)
      local var = t._vim_vars and t._vim_vars[key]
      if var then
        local v_val = vim[var.scope][var.name]
        if v_val ~= nil then
          return v_val
        end
      end
      return t[key]
    end,
  }

  ---@type string[]
  local valid_mods = vim.tbl_keys(schema)

  ---@type ConfigInstance
  local instance = {
    setup = function(user_spec)
      _invalid_keys = nil
      _config.user, _invalid_keys = M.validate_options(schema, user_spec or {})
      if _invalid_keys and #_invalid_keys > 0 then
        vim.schedule(function()
          local msg = ('Unknown key detected in %s.nvim Run :checkhealth %s'):format(info.name, info.name)
          info:echo(msg, 'WARN', true, {})
        end)
      end
    end,
    get_invalid_keys = function()
      return _invalid_keys
    end,
    get = function(mod_name, mod_config)
      vim.validate('mod_name', mod_name, function()
        return vim.iter(valid_mods):find(mod_name) == mod_name
      end, true, 'module name')

      local plugin_name = info.name
      local mod_schema = schema[mod_name]
      local failed = {}
      local config_spec = mod_config or _config.user --[[@as table]]
      local new_config = M.resolve_config(plugin_name, mod_name, mod_schema, config_spec[mod_name], failed)

      if #failed > 0 then
        vim.schedule(function()
          local header = ("Configuration type error in '%s':"):format(mod_name)
          local msg = header .. '\n' .. table.concat(failed, '\n')
          info:echo(msg, 'ERROR', false)
        end)
      end

      _config.master[mod_name] = new_config

      if schema_exec then
        local ok, absences = renew_exe_path(_config, schema_exec, mod_name)
        if not ok then
          local msg = ('Not found executables: %s'):format(table.concat(absences, ', '))
          error(info.label .. msg)
        end
      end

      _config.active[mod_name] = vim.deepcopy(_config.master[mod_name])

      return setmetatable(_config.active[mod_name], _mt)
    end,
  }

  return instance
end

return M
