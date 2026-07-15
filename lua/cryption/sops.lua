local info = require('cryption.info')
local util = require('cryption.util')
local process = require('cryption.lib.process')

local M = {}

---Resolve and format the public key option for SOPS commands.
---If `public_key` is a 2-element table, formats it as a CLI flag pair (e.g., `{'age', 'age1...'}` → `{'--age', 'age1...'}`).
---If `public_key` is absent or invalid, checks for a `.sops.yaml` file in the directory tree.
---Note: Even if no public key is found, decryption may still succeed using keys
---configured in the environment (e.g., AGE_SECRET_KEY, GPG agent).
---@param filepath string # File path used to search for `.sops.yaml`.
---@param public_key? string[] # Key pair to use for encryption.
---@return boolean # `true` if encryption is possible.
---@return string[]? # Formatted public key flags, or `nil` if not applicable.
function M.build_pubkey_option(filepath, public_key)
  if type(public_key) == 'table' and #public_key == 2 then
    public_key = { ('--%s'):format(public_key[1]), public_key[2] }
  else
    if not vim.fs.root(filepath, '.sops.yaml') then
      return false
    end
  end
  return true, public_key
end

---@param filepath string
---@param opts? SopsEncryptOptions
---@param default_output_type string
---@return SopsEncryptOptions?
local function validate_encrypt_options(filepath, opts, default_output_type)
  opts = opts or {}
  opts.input_type = opts.input_type or vim.bo.filetype
  opts.output_type = opts.output_type or default_output_type
  local ok, public_key = M.build_pubkey_option(filepath, opts.public_key)
  if not ok then
    return
  end
  opts.public_key = public_key
  return opts
end

---@alias SelectRange {s:integer,e:integer}

---Normalize and validate a line range for partial buffer operations.
---Falls back to `0` for `s` and `-1` for `e` when values are absent or non-numeric.
---@param range? SelectRange # Input range. If `nil`, returns the full buffer range.
---@return SelectRange # Validated range with guaranteed numeric `s` and `e`.
function M.get_range(range)
  if range then
    range.s = (range.s and type(range.s) == 'number') and range.s or 0
    range.e = (range.e and type(range.e) == 'number') and range.e or -1
  else
    range = { s = 0, e = -1 }
  end
  return range
end

---Build the SOPS encrypt command argument list.
---@param sops string # Path to the sops executable.
---@param filepath string # Target output file path.
---@param opts SopsEncryptOptions|SopsDecryptOptions # Encryption options.
---@return string[] # Command argument list ready to pass to a process runner.
function M.parse_encrypt(sops, filepath, opts)
  local input_type = opts.input_type and { '--input-type', opts.input_type } or {}
  local output_type = opts.output_type and { '--output-type', opts.output_type } or {}
  local filename_override = { '--filename-override', filepath }
  local output = { '--output', filepath }
  --stylua: ignore start
  return vim.iter({ sops, 'encrypt', opts.public_key, input_type, output_type, filename_override, output }):flatten():totable()
  --stylua: ignore end
end

---Build the SOPS decrypt command argument list.
---When `opts.output` is `true`, adds `--output-type json` for structured output.
---When `opts.extract` is set, adds `--extract` for single-key extraction.
---@param sops string # Path to the sops executable.
---@param filepath string # Target encrypted file path.
---@param opts ParseOptions # Decryption options.
---@return string[] # Command argument list ready to pass to a process runner.
function M.parse_decrypt(sops, filepath, opts)
  local input_type = opts.input_type and { '--input-type', opts.input_type } or {}
  local output_type = opts.output and { '--output-type', 'json' } or {}
  local extract = opts.extract and { '--extract', opts.extract } or {}
  return vim.iter({ sops, 'decrypt', input_type, output_type, extract, filepath }):flatten():totable()
end

---@param sops string
---@param filepath string
---@return boolean
local function is_sops_encrypted_file(sops, filepath)
  local cmd = { sops, 'filestatus', filepath }
  local res = process.override(cmd, {}):wait()
  local ok, decoded = pcall(vim.json.decode, res.stdout)
  if ok and decoded and type(decoded) == 'table' then
    return decoded.encrypted == true
  end
  return false
end

---Convert a key path specification into a SOPS `--extract` expression string.
---String elements are formatted as `["key"]`, integer elements as `[index]`.
---e.g. `{'database', 'password'}` → `'["database"]["password"]'`
---e.g. `{'items', 1}` → `'["items"][1]'`
---@param key_spec string[] # Key path components. Must be a non-empty table.
---@return boolean # `true` on success.
---@return string # The extract expression on success, or an error message on failure.
function M.create_extract_value(key_spec)
  if (type(key_spec) == 'table') and (#key_spec ~= 0) then
    local it = vim.iter(key_spec)
    local extract = it:map(function(v)
      if type(v) == 'number' then
        return string.format('[%d]', v)
      else
        return string.format('["%s"]', v)
      end
    end):join('')
    return true, extract
  end
  return false, 'Invalid keys specified.'
end

function M.setup()
  local conf = require('cryption.config').get('sops')
  ---@cast conf SopsSchema

  ---@param filepath? string
  ---@param opts? SopsEncryptOptions
  function M.encrypt_buffer(filepath, opts)
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
    opts = validate_encrypt_options(filepath, opts, conf.encrypt_default_output_type)
    if not opts then
      info:echo('Public-key not found.', 'ERROR', false, {})
      return
    end
    local range = M.get_range(opts.range)
    local lines = vim.api.nvim_buf_get_lines(0, range.s, range.e, false)
    local cmd = M.parse_encrypt(conf.sops, filepath, opts)
    process.override(cmd, { stdin = lines }, function(res)
      vim.schedule(function()
        if res.code ~= 0 or res.stderr ~= '' then
          info:echo('Sops encryption failed.')
        else
          info:echo('Encrypted: ' .. filepath, 'INFO')
        end
      end)
    end)
  end

  ---@param filepath? string
  ---@param close_source boolean
  ---@param opts SopsDecryptOptions
  function M.decrypt_buffer(filepath, close_source, opts)
    opts = opts or {} --[[@as ParseOptions]]
    local source = util.get_bufinfo(filepath, opts.input_type)
    opts.input_type = source.filetype or vim.bo[source.bufnr].filetype
    local ok, public_key = M.build_pubkey_option(source.filepath, opts.public_key)
    if not ok then
      info:echo('Public-key not found.', 'WARN', false, {})
    end
    opts.public_key = public_key
    if not is_sops_encrypted_file(conf.sops, source.filepath) then
      info:echo('Is not a valid sops encrypt data.', 'WARN', false, {})
      return
    end
    local decrypt_cmd = M.parse_decrypt(conf.sops, source.filepath, opts)
    process.override(decrypt_cmd, { env = opts.env }, function(res_decrypt)
      if res_decrypt.code ~= 0 or res_decrypt.stderr ~= '' or res_decrypt.stdout == '' then
        info:echo(res_decrypt.stderr)
        return
      end
      local bufnr = util.create_scratch_contents(info.sops_uri, source.filepath, opts.input_type, res_decrypt.stdout)
      vim.cmd.buffer(bufnr)
      if close_source then
        util.renew_buffer(source.bufnr)
      end
      util.lifecycle(info.augroup, info.decrypted_buffers, bufnr, function()
        if not vim.api.nvim_buf_is_valid(bufnr) then
          info:echo('Buffer is no longer valid.', 'WARN', false, {})
          return
        end

        local answer = info:confirm(('Overwrite %s?'):format(source.filepath))
        if not answer then
          return
        end
        local encrypt_cmd = M.parse_encrypt(conf.sops, source.filepath, opts)
        local new_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        -- local contents = table.concat(new_lines, '\n')
        process.override(encrypt_cmd, { stdin = new_lines }, function(res_encrypt)
          if res_encrypt.code ~= 0 or res_encrypt.stderr ~= '' then
            info:echo(res_encrypt.stderr)
            return
          end
          local f = io.open(source.filepath, 'wb')
          if not f then
            info:echo('Failed to open source file for writing: ' .. source.filepath, 'ERROR', true, {})
            return
          end
          f:write(res_encrypt.stdout)
          f:close()
          vim.api.nvim_set_option_value('modified', false, { buf = bufnr })
          info:echo('Encrypted and saved: ' .. vim.fs.basename(source.filepath), 'INFO')
        end)
      end)
    end)
  end

  ---@param filepath string
  ---@param key_spec string[]
  ---@param opts? SopsGetKeyOptions
  ---@return string?
  function M.get_key(filepath, key_spec, opts)
    filepath = vim.fs.normalize(filepath)
    opts = opts or {} --[[@as ParseOptions]]
    opts.output = true
    local valid, extract_value = M.create_extract_value(key_spec)
    if not valid then
      info:echo(extract_value, 'ERROR')
      return
    end
    opts.extract = extract_value
    local cmd = M.parse_decrypt(conf.sops, filepath, opts)
    local result = process.sync(cmd, { env = opts.env })
    if result.code ~= 0 then
      info:notify(result.stderr, vim.log.levels.ERROR)
      return
    end
    return result.stdout
  end

  ---@param filepath string
  ---@param opts vim.SystemOpts
  ---@param term_fn fun(...)
  ---@param fn_args any[]
  function M.terminal_wrap(filepath, opts, term_fn, fn_args)
    opts = opts or {}
    process.override({ 'sops', 'decrypt', filepath }, opts, function(obj)
      if obj.code ~= 0 then
        info:notify(obj.stderr, 'ERROR')
        return
      end
      vim.schedule(function()
        local saved_envs = {}
        for line in vim.gsplit(obj.stdout, '\r?\n') do
          local key, val = line:match('^([^=]+)=(.*)$')
          if key then
            saved_envs[key] = vim.env[key]
            vim.env[key] = val
          end
        end
        term_fn(unpack(fn_args))
        for key, original_val in pairs(saved_envs) do
          vim.env[key] = original_val
        end
      end)
    end)
  end

  return M
end

return M
