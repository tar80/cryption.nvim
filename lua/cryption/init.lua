---@type cryption
local M = {}

function M.setup(user_config)
  require('cryption.config').setup(user_config)

  if type(user_config.age) == 'table' and user_config.age.enable then
    local age = require('cryption.age')
    age.setup()

    function M.age_encrypt(filepath, opts)
      age.encrypt_buffer(filepath, opts)
    end

    function M.age_decrypt(filepath, close_source, opts)
      age.decrypt_buffer(filepath, close_source, opts)
    end
  end

  if type(user_config.sops) == 'table' and user_config.sops.enable then
    local sops = require('cryption.sops')
    sops.setup()

    function M.sops_encrypt(filepath, opts)
      sops.encrypt_buffer(filepath, opts)
    end

    function M.sops_decrypt(filepath, close_source, opts)
      sops.decrypt_buffer(filepath, close_source, opts)
    end

    function M.sops_extract(filepath, key_spec, opts)
      return sops.get_key(filepath, key_spec, opts)
    end

    function M.sops_exec_env_wrap(filepath, opts, term_fn, fn_args)
      sops.terminal_wrap(filepath, opts, term_fn, fn_args)
    end
  end
end

return M
