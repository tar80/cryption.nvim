local info = require('cryption.info')
local util = require('cryption.util')
local process = require('cryption.lib.process')
local validate = require('cryption.lib.validate')
local filesystem = require('cryption.lib.filesystem')

local M = {}

---Detect the encryption type of an age-encrypted file.
---@param filepath string # Path to the age-encrypted file.
---@param inspect string # Path to the age-inspect executable.
---@return 'scrypt'|'key'|nil # `'scrypt'` for passphrase-encrypted, `'key'` for public-key-encrypted, `nil` if not a valid age file.
function M.detect_encrypt_type(filepath, inspect)
  local cmd = { inspect, '--json', filepath }
  local res = process.sync(cmd, {})
  if res.code ~= 0 or res.stdout == '' then
    return
  end

  local ok, data = pcall(vim.json.decode, res.stdout)
  if not (ok and data and data.version) then
    return
  end

  local has_scrypt = vim.iter(data.stanza_types):any(function(r)
    return r == 'scrypt'
  end)

  return has_scrypt and 'scrypt' or 'key'
end

---Retrieve the secret key from `opts.get_key_cmd`.
---If `get_key_cmd` is a string, it is returned directly as the key.
---If `get_key_cmd` is a table, it is executed as a command with the master password passed via stdin.
---@param opts AgeDecryptOptions
---@return boolean # `true` on success.
---@return string # The secret key string on success, or an error message on failure.
function M.get_secret_key(opts)
  local is_valid, type_key_cmd = validate.is_valid_str(opts.get_key_cmd)
  if is_valid then
    return true, opts.get_key_cmd --[[@as string]]
  end

  if type_key_cmd == 'table' then
    local password = vim.fn.inputsecret('Input Master Password: ')
    local cmd = opts.get_key_cmd --[=[@as string[]]=]
    local res = process.sync(cmd, { stdin = password })
    if res.code ~= 0 or res.stderr ~= '' then
      return false, 'Failed to get the secret key.'
    end

    return true, vim.trim(res.stdout)
  end

  return false, 'Cannot get the secret key.'
end

local function extract_public_key(keygen, key_file, secret_key, opts)
  if validate.is_valid_str(opts.public_key) then
    return { type = 'public_key', value = opts.public_key }
  end
  if validate.is_valid_str(key_file) then
    return { type = 'key_file', value = key_file }
  end

  if not validate.is_valid_str(secret_key) then
    info:echo('Public key not found. You cannot save changes to this buffer.', 'WARN', false)
    return
  end

  local cmd = { keygen, '-y', '-' }

  local res = process.sync(cmd, { stdin = secret_key })
  if res.code ~= 0 or res.stderr ~= '' then
    info:echo(res.stderr or 'Failed public key extraction.', 'ERROR', true)
    return
  end

  local trimmed = vim.trim(res.stdout)
  if not validate.is_valid_str(trimmed) then
    info:echo('Public key not found. You cannot save changes to this buffer.', 'WARN', false)
    return
  end
  return { type = 'public_key', value = trimmed }
end

local function confirm_decrypt(source, conf)
  local bufnr = util.create_scratch_contents(info.age_uri, source.filepath, source.filetype)
  vim.b[bufnr].age_crypt_pubkey = { type = 'passphrase', value = vim.NIL }
  vim.b[bufnr].age_crypt_source = source.filepath
  vim.cmd.buffer(bufnr)

  util.reset_buffer_contents(bufnr, function()
    local args = ('read !%s -d %s'):format(conf.age, source.filepath)
    vim.cmd(args)
    if vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1] == '' then
      vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, {})
    end
  end)

  vim.cmd.mode()
  local first_line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]

  if not first_line then
    vim.cmd.buffer(source.bufnr)
    vim.api.nvim_buf_delete(bufnr, { force = true })
    return false, bufnr, 'Cannot get contents.'
  end

  if first_line:find('^age: error:', 1, true) == 1 then
    vim.cmd.buffer(source.bufnr)
    vim.api.nvim_buf_delete(bufnr, { force = true })
    return false, bufnr, 'Incorrect passphrase.'
  end

  return true, bufnr
end

---Decrypt an age-encrypted file into a scratch buffer using stdin-based identity.
---Supports identity file (`key_file`), raw secret key (`get_key_cmd`), or explicit public key (`public_key`).
---On save, the source file is re-encrypted using the same key material used for decryption.
---@param source {bufnr:integer, filepath:string, filetype:string|nil} # Source buffer information.
---@param conf AgeSchema # Active age configuration instance.
---@param opts AgeDecryptOptions # Decryption options.
---@return boolean # `true` on success.
---@return integer # Scratch buffer number on success, `0` on failure.
---@return string? # Error message on failure.
function M.stdin_decrypt(source, conf, opts)
  local key_file, secret_key
  if opts.key_file then
    if not filesystem.is_file(opts.key_file) then
      return false, 0, ('%s is not exists.'):format(opts.key_file)
    end
    key_file = opts.key_file
  else
    local ok, res = M.get_secret_key(opts)
    if not ok then
      return false, 0, res
    end
    secret_key = res
  end

  local cmd = { conf.age, '--decrypt', '--identity', (key_file or '-'), source.filepath }
  local process_opts = secret_key and { stdin = secret_key } or {}
  local res = process.sync(cmd, process_opts)

  if res.code ~= 0 or res.stderr ~= '' or res.stdout == '' then
    return false, 0, (res.stderr or 'Age decrypt failed.')
  end

  local bufnr = util.create_scratch_contents(info.age_uri, source.filepath, source.filetype, res.stdout)
  vim.b[bufnr].age_crypt_pubkey = extract_public_key(conf.keygen, key_file, secret_key, opts)
  vim.b[bufnr].age_crypt_source = source.filepath

  vim.cmd.buffer(bufnr)

  return true, bufnr
end

---@alias KeyType 'passphrase'|'key_file'|'public_key'

---@param opts AgeEncryptOptions
---@return KeyType|nil
local function validate_encrypt_options(opts)
  if opts.passphrase then
    return 'passphrase'
  elseif opts.key_file then
    return 'key_file'
  elseif opts.public_key then
    return 'public_key'
  else
    return
  end
end

---Build the age encrypt command argument list.
---@param age string # Path to the age executable.
---@param keytype KeyType # Encryption key type.
---@param filepath string # Target output file path.
---@param opts AgeEncryptOptions # Encryption options.
---@return string[] # Command argument list ready to pass to a process runner.
function M.parse_encrypt(age, keytype, filepath, opts)
  local armor = opts.armor and '--armor' or nil
  local key
  if keytype == 'passphrase' then
    age = ('!%s'):format(age)
    filepath = vim.fn.shellescape(filepath)
    key = { '--passphrase' }
  elseif keytype == 'key_file' then
    key = { '--recipients-file', opts.key_file }
  elseif keytype == 'public_key' then
    key = { '--recipient', opts.public_key }
  else
    info:echo('Invalid key type specified for encryption.')
  end
  return vim.iter({ age, '--encrypt', key, armor, '-o', filepath }):flatten():totable()
end

---Execute encryption and write the result to `filepath`.
---For `passphrase` keytype, uses `vim.cmd.write` for interactive passphrase input.
---For other keytypes, runs asynchronously via `process.override`.
---@param bufnr integer # Source buffer number.
---@param filepath string # Target output file path.
---@param keytype KeyType # Encryption key type.
---@param cmd string[] # Command argument list produced by `parse_encrypt`.
function M.do_encrypt(bufnr, filepath, keytype, cmd)
  if keytype == 'passphrase' then
    local ok, _ = pcall(vim.cmd.write, cmd)
    if not ok then
      info:notify('Failed to encrypt and save file with passphrase.', 'ERROR')
      return
    end
    vim.api.nvim_set_option_value('modified', false, { buf = bufnr })
    info:echo('Encrypted and saved ' .. vim.fs.basename(filepath), 'INFO')
    return
  end
  local new_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  process.override(cmd, { stdin = new_lines }, function(res_encrypt)
    if res_encrypt.code ~= 0 or res_encrypt.stderr ~= '' then
      info:echo(res_encrypt.stderr or 'Failed to encrypt.', 'ERROR', true)
      return
    end
    local f = io.open(filepath, 'wb')
    if not f then
      info:echo('Failed to open ' .. vim.fs.basename(filepath), 'ERROR', true, {})
      return
    end
    f:write(res_encrypt.stdout)
    f:close()
    vim.api.nvim_set_option_value('modified', false, { buf = bufnr })
    info:echo('Encrypted and saved ' .. vim.fs.basename(filepath), 'INFO')
  end)
end

function M.setup()
  ---@type AgeSchema
  local conf = require('cryption.config').get('age')

  ---@param filepath? string # Target file path to encrypt.
  ---@param opts? AgeEncryptOptions # Encryption options.
  function M.encrypt_buffer(filepath, opts)
    opts = opts or {}
    local bufnr = vim.api.nvim_get_current_buf()

    if not filepath then
      if vim.api.nvim_buf_get_name(bufnr) == '' then
        info:echo('Scratch buffer is not overwrite.', 'WARN', false, {})
        return
      end
      local answer = info:confirm('No filepath specified. Overwrite the current buffer?')
      if not answer then
        return
      end
      filepath = '%'
    end
    filepath = vim.fn.fnamemodify(filepath, ':p')
    local keytype = validate_encrypt_options(opts)
    if not keytype then
      info:echo('No passphrase or public-key has been specified.', 'ERROR', true, {})
      return
    end

    local cmd = M.parse_encrypt(conf.age, keytype, filepath, opts)
    M.do_encrypt(bufnr, filepath, keytype, cmd)
  end

  ---@param filepath? string
  ---@param close_source boolean
  ---@param opts AgeDecryptOptions
  function M.decrypt_buffer(filepath, close_source, opts)
    opts = opts or {}
    local source = util.get_bufinfo(filepath, opts.filetype)
    local enc_type = M.detect_encrypt_type(source.filepath, conf.inspect)
    if not enc_type then
      info:echo('Is not a valid age encrypt data.', 'WARN', false, {})
      return
    end
    local success, scratch_bufnr, err
    if enc_type == 'scrypt' then
      success, scratch_bufnr, err = confirm_decrypt(source, conf)
    else
      success, scratch_bufnr, err = M.stdin_decrypt(source, conf, opts)
    end
    if not success then
      info:echo(err, 'ERROR', true, {})
      return
    end
    if close_source then
      util.renew_buffer(source.bufnr)
    end
    util.lifecycle(info.augroup, info.decrypted_buffers, scratch_bufnr, function()
      local b = vim.b[scratch_bufnr]
      local pubkey = b.age_crypt_pubkey
      local source_path = b.age_crypt_source
      if not (pubkey and source_path) then
        info:notify('Missing encryption metadata.', 'ERROR')
        return
      end
      local keytype = pubkey.type
      local cmd = M.parse_encrypt(
        conf.age,
        keytype,
        source_path,
        { armor = opts.armor, public_key = pubkey.value, key_file = pubkey.value }
      )
      M.do_encrypt(scratch_bufnr, source_path, keytype, cmd)
    end)
  end
end

return M
