---@class ConfigSpec
---@field type string|string[]
---@field default any
---@field optional? boolean
---@field message? string
---@field func? fun(value:any):any
---@field vim_var? '"global"'|'"local"'

---@alias ConfigSchema table<string, ConfigSpec|ConfigSchema>

local M = {}

---Capitalize the first lowercase character of a string.
---@param name? string Input string.
---@return string|nil capitalized String with the first character uppercased.
function M.capitalize(name)
  return (name and name:gsub('^%l', string.upper))
end

---Detect executable paths from a command table.
---@param commands table<string, string> Table of keys and executable names/paths.
---@return table<string, string> existence Resolved executable paths.
---@return string[] absences Commands that were not found.
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

---Recursively checks user configuration for unknown keys.
---@param schema_node table Current schema node.
---@param user_node table Current user configuration node.
---@param prefix string Current key prefix.
---@param unknown_keys string[] Accumulator for invalid keys.
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
---This function only checks for unknown keys.
---Type validation is handled separately in `resolve_config()`.
---
---@param schema table Configuration schema.
---@param user_spec table User configuration.
---@return table validated_spec Original user configuration.
---@return string[]|nil unknown_keys List of invalid keys, or nil if none exist.
function M.validate_options(schema, user_spec)
  local unknown_keys = {}

  check_unknown_keys(schema, user_spec, '', unknown_keys)

  if #unknown_keys == 0 then
    unknown_keys = nil
  end

  return user_spec, unknown_keys
end

---Generate metadata for a Vim variable.
---@param plugin_name string Plugin name.
---@param scope "global"|"local" Variable scope.
---@param mod_name string Module name.
---@param key string Configuration key.
---@return { scope: '"g"'|'"b"', name: string }
local function get_vim_var(plugin_name, scope, mod_name, key)
  return {
    scope = scope == 'local' and 'b' or 'g',
    name = ('%s_%s_%s'):format(plugin_name, mod_name, key),
  }
end

---Returns whether a schema node is a leaf spec.
---@param node any
---@return boolean
local function is_branch_node(node)
  return type(node) == 'table' and node.type == nil
end

---Validate a value using vim.validate().
---@param key string
---@param value any
---@param spec ConfigSpec
---@param failed string[]
---@return any
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

---@param active table
---@param plugin_name string
---@param mod_name string
---@param key string
---@param spec ConfigSpec
local function register_vim_var(active, plugin_name, mod_name, key, spec)
  active._vim_vars = active._vim_vars or {}
  active._vim_vars[key] = get_vim_var(plugin_name, spec.vim_var, mod_name, key)
end

---Resolve and validate configuration values from a schema.
---@param plugin_name string Plugin name.
---@param mod_name string Module name.
---@param mod_schema table Configuration schema.
---@param user_data? table User configuration values.
---@param failed string[] Validation error accumulator.
---@return table active Resolved configuration table.
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

return M
