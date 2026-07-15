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
