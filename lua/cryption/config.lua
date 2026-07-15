---Configuration schema definition for the Age backend instance.
---@class AgeSchema : AgeConfig, GetMethods

---Configuration schema definition for the SOPS backend instance.
---@class SopsSchema : SopsConfig, GetMethods

---A configuration instance returned by |M.config_instance()|.
---@class ConfigInstance
---@field setup fun(user_config?: {age:AgeConfig?, sops:SopsConfig?}) Validates and stores user configuration. Call this from the plugin's `setup()`.
---@field get fun(mod_name: string, mod_config?: table): AgeSchema|SopsSchema Resolves and returns a validated configuration instance for the given module.
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

local info = require('cryption.info')

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

---@class ConfigInstance
return require('cryption.helper.config').config_instance(info, schema, schema_exec)
