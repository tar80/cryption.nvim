local assert = require('luassert')
local age = require('cryption.age')
age.setup()

describe('age', function()
  describe('.detect_encrypt_type()', function()
    local process_mod = require('cryption.lib.process')
    local original_sync

    before_each(function()
      original_sync = process_mod.sync
    end)

    after_each(function()
      rawset(process_mod, 'sync', original_sync)
    end)

    it('returns nil when inspect command exits with a non-zero code', function()
      rawset(process_mod, 'sync', function()
        return { code = 1, stdout = '', stderr = 'error' }
      end)

      local res = age.detect_encrypt_type('/path/to/file.age', 'age-keygen')

      assert.is_nil(res)
    end)

    it('returns nil when stdout is empty', function()
      rawset(process_mod, 'sync', function()
        return { code = 0, stdout = '', stderr = '' }
      end)

      local res = age.detect_encrypt_type('/path/to/file.age', 'age-keygen')

      assert.is_nil(res)
    end)

    it('returns nil when stdout is not valid JSON', function()
      rawset(process_mod, 'sync', function()
        return { code = 0, stdout = 'not json', stderr = '' }
      end)

      local res = age.detect_encrypt_type('/path/to/file.age', 'age-keygen')

      assert.is_nil(res)
    end)

    it('returns nil when JSON does not contain version field', function()
      rawset(process_mod, 'sync', function()
        return { code = 0, stdout = '{"stanza_types":["X25519"]}', stderr = '' }
      end)

      local res = age.detect_encrypt_type('/path/to/file.age', 'age-keygen')

      assert.is_nil(res)
    end)

    it('returns "scrypt" when stanza_types contains "scrypt"', function()
      rawset(process_mod, 'sync', function()
        return {
          code = 0,
          stdout = '{"version":"v1","stanza_types":["scrypt"]}',
          stderr = '',
        }
      end)

      local res = age.detect_encrypt_type('/path/to/file.age', 'age-keygen')

      assert.are.equal('scrypt', res)
    end)

    it('returns "key" when stanza_types does not contain "scrypt"', function()
      rawset(process_mod, 'sync', function()
        return {
          code = 0,
          stdout = '{"version":"v1","stanza_types":["X25519"]}',
          stderr = '',
        }
      end)

      local res = age.detect_encrypt_type('/path/to/file.age', 'age-keygen')

      assert.are.equal('key', res)
    end)
  end)

  describe('.get_secret_key()', function()
    local process_mod = require('cryption.lib.process')
    local original_sync
    local original_inputsecret

    before_each(function()
      original_sync = process_mod.sync
      original_inputsecret = vim.fn.inputsecret
    end)

    after_each(function()
      rawset(process_mod, 'sync', original_sync)
      vim.fn.inputsecret = original_inputsecret
    end)

    it('returns the string as-is when get_key_cmd is a non-empty string', function()
      local ok, res = age.get_secret_key({ get_key_cmd = 'AGE-SECRET-KEY-...' })

      assert.is_true(ok)
      assert.are.equal('AGE-SECRET-KEY-...', res)
    end)

    it('returns false when get_key_cmd is neither a string nor a table', function()
      local ok, res = age.get_secret_key({ get_key_cmd = nil })

      assert.is_false(ok)
      assert.are.equal('Cannot get the secret key.', res)
    end)

    it('returns trimmed stdout when get_key_cmd is a table and the command succeeds', function()
      vim.fn.inputsecret = function()
        return 'master_password'
      end

      rawset(process_mod, 'sync', function(cmd, opts)
        assert.are.same({ 'get-key-cmd' }, cmd)
        assert.are.equal('master_password', opts.stdin)
        return { code = 0, stdout = 'AGE-SECRET-KEY-...\n', stderr = '' }
      end)

      local ok, res = age.get_secret_key({ get_key_cmd = { 'get-key-cmd' } })

      assert.is_true(ok)
      assert.are.equal('AGE-SECRET-KEY-...', res)
    end)

    it('returns false when get_key_cmd is a table and the command fails', function()
      vim.fn.inputsecret = function()
        return 'wrong_password'
      end

      rawset(process_mod, 'sync', function()
        return { code = 1, stdout = '', stderr = 'auth failed' }
      end)

      local ok, res = age.get_secret_key({ get_key_cmd = { 'get-key-cmd' } })

      assert.is_false(ok)
      assert.are.equal('Failed to get the secret key.', res)
    end)
  end)

  describe('.parse_encrypt()', function()
    local original_shellescape

    before_each(function()
      original_shellescape = vim.fn.shellescape
    end)

    after_each(function()
      vim.fn.shellescape = original_shellescape
    end)

    it('builds a passphrase encrypt command with shellescape applied to filepath', function()
      vim.fn.shellescape = function(s)
        return ("'%s'"):format(s)
      end

      local res = age.parse_encrypt('age', 'passphrase', '/path/to/file.age', {})

      assert.are.same({
        '!age',
        '--encrypt',
        '--passphrase',
        '-o',
        "'/path/to/file.age'",
      }, res)
    end)

    it('builds a passphrase encrypt command with --armor when armor is true', function()
      vim.fn.shellescape = function(s)
        return ("'%s'"):format(s)
      end

      local res = age.parse_encrypt('age', 'passphrase', '/path/to/file.age', { armor = true })

      assert.are.same({
        '!age',
        '--encrypt',
        '--passphrase',
        '--armor',
        '-o',
        "'/path/to/file.age'",
      }, res)
    end)

    it('builds a key_file encrypt command', function()
      local res = age.parse_encrypt('age', 'key_file', '/path/to/file.age', {
        key_file = '/path/to/recipients.txt',
      })

      assert.are.same({
        'age',
        '--encrypt',
        '--recipients-file',
        '/path/to/recipients.txt',
        '-o',
        '/path/to/file.age',
      }, res)
    end)

    it('builds a public_key encrypt command', function()
      local res = age.parse_encrypt('age', 'public_key', '/path/to/file.age', {
        public_key = 'age1...key',
      })

      assert.are.same({
        'age',
        '--encrypt',
        '--recipient',
        'age1...key',
        '-o',
        '/path/to/file.age',
      }, res)
    end)

    it('raises an error when an invalid keytype is given', function()
      assert.has_error(function()
        age.parse_encrypt('age', 'invalid', '/path/to/file.age', {})
      end)
    end)
  end)

  describe('.stdin_decrypt()', function()
    local process_mod = require('cryption.lib.process')
    local util_mod = require('cryption.util')
    local filesystem_mod = require('cryption.lib.filesystem')
    local info_mod = require('cryption.info')

    local original_sync
    local original_create_scratch
    local original_is_file
    local original_echo
    local original_inputsecret
    local original_buffer_cmd
    local scratch_bufnr

    before_each(function()
      scratch_bufnr = vim.api.nvim_create_buf(true, true)
      original_sync = process_mod.sync
      original_create_scratch = util_mod.create_scratch_contents
      original_is_file = filesystem_mod.is_file
      original_echo = info_mod.echo
      original_inputsecret = vim.fn.inputsecret
      original_buffer_cmd = vim.cmd.buffer
      rawset(info_mod, 'echo', function() end)
      rawset(util_mod, 'create_scratch_contents', function()
        return scratch_bufnr
      end)
      vim.cmd.buffer = function() end
    end)

    after_each(function()
      rawset(process_mod, 'sync', original_sync)
      rawset(util_mod, 'create_scratch_contents', original_create_scratch)
      rawset(filesystem_mod, 'is_file', original_is_file)
      rawset(info_mod, 'echo', original_echo)
      vim.fn.inputsecret = original_inputsecret
      vim.cmd.buffer = original_buffer_cmd
      if vim.api.nvim_buf_is_valid(scratch_bufnr) then
        vim.api.nvim_buf_delete(scratch_bufnr, { force = true })
      end
    end)

    it('sets age_crypt_pubkey to nil and warns when keygen returns empty string', function()
      local warned = false
      rawset(info_mod, 'echo', function(_, msg, level)
        if level == 'WARN' then
          warned = true
        end
      end)

      rawset(process_mod, 'sync', function(cmd)
        if vim.tbl_contains(cmd, '-y') then
          return { code = 0, stdout = '\n', stderr = '' }
        end
        return { code = 0, stdout = 'decrypted_content', stderr = '' }
      end)

      local source = { bufnr = 1, filepath = '/path/to/secret.age', filetype = 'yaml' }
      local ok, bufnr = age.stdin_decrypt(
        source,
        { age = 'age', keygen = 'age-keygen' },
        { get_key_cmd = 'AGE-SECRET-KEY-...' }
      )

      assert.is_true(ok)
      assert.are.equal(scratch_bufnr, bufnr)
      assert.is_nil(vim.b[scratch_bufnr].age_crypt_pubkey)
      assert.is_true(warned)
    end)

    it('returns false when key_file is specified but does not exist', function()
      rawset(filesystem_mod, 'is_file', function()
        return false
      end)

      local source = { bufnr = 1, filepath = '/path/to/secret.age', filetype = 'yaml' }
      local ok, bufnr, err = age.stdin_decrypt(source, { age = 'age', keygen = 'age-keygen' }, {
        key_file = '/path/to/missing.txt',
      })

      assert.is_false(ok)
      assert.are.equal(0, bufnr)
      assert.are.equal('/path/to/missing.txt is not exists.', err)
    end)

    it('returns false when get_secret_key fails', function()
      local source = { bufnr = 1, filepath = '/path/to/secret.age', filetype = 'yaml' }
      local ok, bufnr, err = age.stdin_decrypt(source, { age = 'age', keygen = 'age-keygen' }, { get_key_cmd = nil })

      assert.is_false(ok)
      assert.are.equal(0, bufnr)
      assert.are.equal('Cannot get the secret key.', err)
    end)

    it('returns false when the decrypt command fails', function()
      rawset(process_mod, 'sync', function()
        return { code = 1, stdout = '', stderr = 'decryption error' }
      end)

      local source = { bufnr = 1, filepath = '/path/to/secret.age', filetype = 'yaml' }
      local ok, bufnr, err = age.stdin_decrypt(
        source,
        { age = 'age', keygen = 'age-keygen' },
        { get_key_cmd = 'AGE-SECRET-KEY-...' }
      )

      assert.is_false(ok)
      assert.are.equal(0, bufnr)
      assert.are.equal('decryption error', err)
    end)

    it('returns true and scratch bufnr when key_file is given and decrypt succeeds', function()
      rawset(filesystem_mod, 'is_file', function()
        return true
      end)

      rawset(process_mod, 'sync', function(cmd)
        if vim.tbl_contains(cmd, '-y') then
          return { code = 0, stdout = 'age1...pubkey\n', stderr = '' }
        end
        assert.is_true(vim.tbl_contains(cmd, '--identity'))
        assert.is_true(vim.tbl_contains(cmd, '/path/to/key.txt'))
        return { code = 0, stdout = 'decrypted_content', stderr = '' }
      end)

      local source = { bufnr = 1, filepath = '/path/to/secret.age', filetype = 'yaml' }
      local ok, bufnr = age.stdin_decrypt(source, { age = 'age', keygen = 'age-keygen' }, {
        key_file = '/path/to/key.txt',
      })

      assert.is_true(ok)
      assert.are.equal(scratch_bufnr, bufnr)
      assert.are.equal('/path/to/secret.age', vim.b[scratch_bufnr].age_crypt_source)
      assert.are.same({ type = 'key_file', value = '/path/to/key.txt' }, vim.b[scratch_bufnr].age_crypt_pubkey)
    end)

    it('sets age_crypt_pubkey when keygen extracts public key successfully', function()
      rawset(process_mod, 'sync', function(cmd)
        if vim.tbl_contains(cmd, '-y') then
          return { code = 0, stdout = 'age1...pubkey\n', stderr = '' }
        end
        return { code = 0, stdout = 'decrypted_content', stderr = '' }
      end)

      local source = { bufnr = 1, filepath = '/path/to/secret.age', filetype = 'yaml' }
      local ok, bufnr = age.stdin_decrypt(
        source,
        { age = 'age', keygen = 'age-keygen' },
        { get_key_cmd = 'AGE-SECRET-KEY-...' }
      )

      assert.is_true(ok)
      assert.are.equal(scratch_bufnr, bufnr)
      assert.are.same({ type = 'public_key', value = 'age1...pubkey' }, vim.b[scratch_bufnr].age_crypt_pubkey)
    end)
  end)

  describe('.decrypt_buffer()', function()
    local process_mod = require('cryption.lib.process')
    local util_mod = require('cryption.util')
    local filesystem_mod = require('cryption.lib.filesystem')
    local info_mod = require('cryption.info')

    local original_sync
    local original_get_bufinfo
    local original_create_scratch
    local original_renew_buffer
    local original_lifecycle
    local original_buffer_cmd
    local original_echo
    local original_is_file
    local scratch_bufnr

    before_each(function()
      scratch_bufnr = vim.api.nvim_create_buf(true, true)
      original_sync = process_mod.sync
      original_get_bufinfo = util_mod.get_bufinfo
      original_create_scratch = util_mod.create_scratch_contents
      original_renew_buffer = util_mod.renew_buffer
      original_lifecycle = util_mod.lifecycle
      original_buffer_cmd = vim.cmd.buffer
      original_echo = info_mod.echo
      original_is_file = filesystem_mod.is_file
      rawset(info_mod, 'echo', function() end)
      rawset(util_mod, 'create_scratch_contents', function()
        return scratch_bufnr
      end)
      vim.cmd.buffer = function() end
    end)

    after_each(function()
      rawset(process_mod, 'sync', original_sync)
      rawset(util_mod, 'get_bufinfo', original_get_bufinfo)
      rawset(util_mod, 'create_scratch_contents', original_create_scratch)
      rawset(util_mod, 'renew_buffer', original_renew_buffer)
      rawset(util_mod, 'lifecycle', original_lifecycle)
      vim.cmd.buffer = original_buffer_cmd
      rawset(info_mod, 'echo', original_echo)
      rawset(filesystem_mod, 'is_file', original_is_file)
      if vim.api.nvim_buf_is_valid(scratch_bufnr) then
        vim.api.nvim_buf_delete(scratch_bufnr, { force = true })
      end
    end)

    it('returns early when the file is not valid age-encrypted data', function()
      rawset(util_mod, 'get_bufinfo', function()
        return { bufnr = 1, filepath = '/path/to/plain.txt', filetype = 'text' }
      end)

      rawset(process_mod, 'sync', function()
        return { code = 1, stdout = '', stderr = '' }
      end)

      local lifecycle_called = false
      rawset(util_mod, 'lifecycle', function()
        lifecycle_called = true
      end)

      age.decrypt_buffer('/path/to/plain.txt', false, {})

      assert.is_false(lifecycle_called)
    end)

    it('decrypts with key_file and opens a scratch buffer when enc_type is "key"', function()
      rawset(util_mod, 'get_bufinfo', function()
        return { bufnr = 1, filepath = '/path/to/secret.age', filetype = 'yaml' }
      end)

      local create_scratch_called = false
      rawset(util_mod, 'create_scratch_contents', function(uri, filepath, filetype, contents)
        create_scratch_called = true
        assert.are.equal('decrypted_content', contents)
        return scratch_bufnr
      end)

      local lifecycle_called = false
      rawset(util_mod, 'lifecycle', function(augroup, buffers, bufnr, callback)
        lifecycle_called = true
        assert.are.equal(scratch_bufnr, bufnr)
      end)

      rawset(filesystem_mod, 'is_file', function()
        return true
      end)

      rawset(process_mod, 'sync', function(cmd)
        if vim.tbl_contains(cmd, '--json') then
          return {
            code = 0,
            stdout = '{"version":"v1","stanza_types":["X25519"]}',
            stderr = '',
          }
        end
        return { code = 0, stdout = 'decrypted_content', stderr = '' }
      end)

      age.decrypt_buffer('/path/to/secret.age', false, { key_file = '/path/to/key.txt' })

      assert.is_true(create_scratch_called)
      assert.is_true(lifecycle_called)
    end)

    it('does not call renew_buffer when close_source is false', function()
      rawset(util_mod, 'get_bufinfo', function()
        return { bufnr = 1, filepath = '/path/to/secret.age', filetype = 'yaml' }
      end)

      local renew_buffer_called = false
      rawset(util_mod, 'renew_buffer', function()
        renew_buffer_called = true
      end)

      rawset(util_mod, 'lifecycle', function() end)

      rawset(filesystem_mod, 'is_file', function()
        return true
      end)

      rawset(process_mod, 'sync', function(cmd)
        if vim.tbl_contains(cmd, '--json') then
          return {
            code = 0,
            stdout = '{"version":"v1","stanza_types":["X25519"]}',
            stderr = '',
          }
        end
        return { code = 0, stdout = 'decrypted_content', stderr = '' }
      end)

      age.decrypt_buffer('/path/to/secret.age', false, { key_file = '/path/to/key.txt' })

      assert.is_false(renew_buffer_called)
    end)

    it('calls renew_buffer when close_source is true', function()
      rawset(util_mod, 'get_bufinfo', function()
        return { bufnr = 1, filepath = '/path/to/secret.age', filetype = 'yaml' }
      end)

      local renew_buffer_called = false
      rawset(util_mod, 'renew_buffer', function(bufnr)
        renew_buffer_called = true
        assert.are.equal(1, bufnr)
      end)

      rawset(util_mod, 'lifecycle', function() end)

      rawset(filesystem_mod, 'is_file', function()
        return true
      end)

      rawset(process_mod, 'sync', function(cmd)
        if vim.tbl_contains(cmd, '--json') then
          return {
            code = 0,
            stdout = '{"version":"v1","stanza_types":["X25519"]}',
            stderr = '',
          }
        end
        return { code = 0, stdout = 'decrypted_content', stderr = '' }
      end)

      age.decrypt_buffer('/path/to/secret.age', true, { key_file = '/path/to/key.txt' })

      assert.is_true(renew_buffer_called)
    end)
  end)
end)
