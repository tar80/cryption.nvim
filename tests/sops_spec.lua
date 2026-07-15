local assert = require('luassert')
local sops = require('cryption.sops')
sops.setup()

describe('sops', function()
  describe('.build_pubkey_option()', function()
    it('returns false when public_key is an empty table and .sops.yaml is not found', function()
      rawset(vim.fs, 'root', function()
        return nil
      end)
      local ok, res = sops.build_pubkey_option('/path/to/file.txt', {})
      assert.is_false(ok)
      assert.is_nil(res)
    end)
  end)

  describe('.adjust_public_key()', function()
    local original_root

    before_each(function()
      original_root = vim.fs.root
    end)

    after_each(function()
      rawset(vim.fs, 'root', original_root)
    end)

    it('returns true and formats the key when a valid 2-element public_key is given', function()
      local filepath = '/path/to/file.txt'
      local public_key = { 'age', 'age1...key' }
      local ok, res = sops.build_pubkey_option(filepath, public_key)
      assert.is_true(ok)
      assert.are.same({ '--age', 'age1...key' }, res)
    end)

    it('returns false when public_key is invalid and .sops.yaml is not found', function()
      local called_with_args = {}
      rawset(vim.fs, 'root', function(...)
        called_with_args = { ... }
        return nil
      end)
      local filepath = '/path/to/file.txt'
      local public_key = { 'invalid_format' }
      local ok, res = sops.build_pubkey_option(filepath, public_key)
      assert.is_false(ok)
      assert.is_nil(res)
      assert.are.same({ filepath, '.sops.yaml' }, called_with_args)
    end)

    it('returns true and the original key when public_key is invalid but .sops.yaml is found', function()
      local called_with_args = {}
      rawset(vim.fs, 'root', function(...)
        called_with_args = { ... }
        return '/path/to'
      end)
      local filepath = '/path/to/file.txt'
      local public_key = { 'invalid_format' }
      local ok, res = sops.build_pubkey_option(filepath, public_key)
      assert.is_true(ok)
      assert.are.same({ 'invalid_format' }, res)
      assert.are.same({ filepath, '.sops.yaml' }, called_with_args)
    end)

    it('returns true and nil when public_key is nil and .sops.yaml is found', function()
      rawset(vim.fs, 'root', function()
        return '/path/to'
      end)
      local filepath = '/path/to/file.txt'
      local ok, res = sops.build_pubkey_option(filepath, nil)
      assert.is_true(ok)
      assert.is_nil(res)
    end)
  end)

  describe('.get_range()', function()
    it('returns default { s = 0, e = -1 } when range is nil', function()
      local res = sops.get_range(nil)
      assert.are.same({ s = 0, e = -1 }, res)
    end)

    it('returns the range as-is when valid numeric s and e are given', function()
      local range = { s = 2, e = 5 }
      local res = sops.get_range(range)
      assert.are.same({ s = 2, e = 5 }, res)
    end)

    it('falls back to defaults when s or e are non-numeric', function()
      local range1 = { s = 'invalid', e = nil }
      local res1 = sops.get_range(range1)
      assert.are.same({ s = 0, e = -1 }, res1)

      local range2 = { s = nil, e = true }
      local res2 = sops.get_range(range2)
      assert.are.same({ s = 0, e = -1 }, res2)
    end)

    it('falls back e to -1 when only s is a valid number', function()
      local range = { s = 3, e = nil }
      local res = sops.get_range(range)
      assert.are.same({ s = 3, e = -1 }, res)
    end)

    it('falls back s to 0 when only e is a valid number', function()
      local range = { s = nil, e = 10 }
      local res = sops.get_range(range)
      assert.are.same({ s = 0, e = 10 }, res)
    end)
  end)

  describe('.parse_encrypt()', function()
    it('builds the correct command array when all options are specified', function()
      local sops_bin = 'sops'
      local filepath = 'secrets.yaml'
      local opts = {
        public_key = { '--age', 'age1...key' },
        input_type = 'yaml',
        output_type = 'yaml',
      }
      local res = sops.parse_encrypt(sops_bin, filepath, opts)
        --stylua: ignore start
        local expected = {
          'sops',
          'encrypt',
          '--age', 'age1...key',
          '--input-type', 'yaml',
          '--output-type', 'yaml',
          '--filename-override', 'secrets.yaml',
          '--output', 'secrets.yaml',
        }
      --stylua: ignore end
      assert.are.same(expected, res)
    end)

    it('builds the correct command array without unnecessary flags when options are minimal', function()
      local sops_bin = 'sops'
      local filepath = 'secrets.json'
      local opts = { public_key = { '--age', 'age1...key' } }
      local res = sops.parse_encrypt(sops_bin, filepath, opts)
        --stylua: ignore start
        local expected = {
          'sops',
          'encrypt',
          '--age', 'age1...key',
          '--filename-override', 'secrets.json',
          '--output', 'secrets.json',
        }
      --stylua: ignore end
      assert.are.same(expected, res)
    end)
  end)

  describe('.parse_decrypt()', function()
    it('builds a minimal decrypt command when called from decrypt_buffer', function()
      local res = sops.parse_decrypt('sops', 'secrets.yaml', { input_type = 'yaml' })
      local expected = { 'sops', 'decrypt', '--input-type', 'yaml', 'secrets.yaml' }
      assert.are.same(expected, res)
    end)

    it('builds a decrypt command with json output and key extraction when called from get_key', function()
      local opts = {
        input_type = 'yaml',
        output = true,
        extract = '["database"]["password"]',
      }
      local res = sops.parse_decrypt('sops', 'secrets.yaml', opts)
      local expected = {
        'sops',
        'decrypt',
        '--input-type',
        'yaml',
        '--output-type',
        'json',
        '--extract',
        '["database"]["password"]',
        'secrets.yaml',
      }
      assert.are.same(expected, res)
    end)

    it('does not include --input-type flag when input_type is nil', function()
      local res = sops.parse_decrypt('sops', 'secrets.yaml', {})
      assert.is_false(vim.tbl_contains(res, '--input-type'))
    end)
  end)

  describe('.create_extract_value()', function()
    it('returns false and an error message when an empty table is given', function()
      local ok, res = sops.create_extract_value({})
      assert.is_false(ok)
      assert.are.equal('Invalid keys specified.', res)
    end)

    it('converts all string keys to quoted bracket notation', function()
      local ok, res = sops.create_extract_value({ 'database', 'password' })
      assert.is_true(ok)
      assert.are.equal('["database"]["password"]', res)
    end)

    it('converts numeric keys to unquoted index notation', function()
      local ok, res = sops.create_extract_value({ 'items', 1 })
      assert.is_true(ok)
      assert.are.equal('["items"][1]', res)
    end)

    it('returns false and an error message when a non-table is given', function()
      local ok, res = sops.create_extract_value('invalid_input')
      assert.is_false(ok)
      assert.are.equal('Invalid keys specified.', res)
    end)
  end)

  describe('.get_key()', function()
    local original_sync
    local process_mod = require('cryption.lib.process')

    before_each(function()
      original_sync = process_mod.sync
    end)

    after_each(function()
      rawset(process_mod, 'sync', original_sync)
    end)

    it('notifies an error and returns nil when key_spec is not a table', function()
      local info_mod = require('cryption.info')
      local original_echo = info_mod.echo
      local echoed_msg = nil
      local echoed_level = nil
      rawset(info_mod, 'echo', function(_, msg, level)
        echoed_msg = msg
        echoed_level = level
      end)

      local res = sops.get_key('secrets.yaml', 'invalid_key_spec')

      assert.is_nil(res)
      assert.are.equal('Invalid keys specified.', echoed_msg)
      assert.are.equal('ERROR', echoed_level)

      rawset(info_mod, 'echo', original_echo)
    end)

    it('returns stdout when sops succeeds', function()
      local called_cmd = nil
      local called_opts = nil
      rawset(process_mod, 'sync', function(cmd, opts)
        called_cmd = cmd
        called_opts = opts
        return { code = 0, stdout = 'my_secret_password\n', stderr = '' }
      end)

      local filepath = 'secrets.yaml'
      local key_spec = { 'database', 'password' }
      local opts = { env = { SOPS_AGE_KEY_FILE = 'key.txt' } }
      local res = sops.get_key(filepath, key_spec, opts)

      assert.are.equal('my_secret_password\n', res)
      assert.is_true(vim.tbl_contains(called_cmd, 'decrypt'))
      assert.is_true(vim.tbl_contains(called_cmd, '["database"]["password"]'))
      assert.are.same(opts.env, called_opts.env)
    end)

    it('notifies an error via vim.notify and returns nil when sops exits with a non-zero code', function()
      rawset(process_mod, 'sync', function()
        return { code = 1, stdout = '', stderr = 'Error: key not found' }
      end)

      local notified_msg = nil
      local notified_level = nil
      local original_notify = vim.notify
      vim.notify = function(msg, level, _)
        notified_msg = msg
        notified_level = level
      end

      local res = sops.get_key('secrets.yaml', { 'invalid' })

      assert.is_nil(res)
      assert.are.equal('Error: key not found', notified_msg)
      assert.are.equal(vim.log.levels.ERROR, notified_level)

      vim.notify = original_notify
    end)
  end)

  describe('.decrypt_buffer()', function()
    local process_mod = require('cryption.lib.process')
    local util_mod = require('cryption.util')
    local info_mod = require('cryption.info')

    local original_override
    local original_get_bufinfo
    local original_create_scratch
    local original_renew_buffer
    local original_lifecycle
    local original_buffer_cmd
    local original_echo

    before_each(function()
      original_override = process_mod.override
      original_get_bufinfo = util_mod.get_bufinfo
      original_create_scratch = util_mod.create_scratch_contents
      original_renew_buffer = util_mod.renew_buffer
      original_lifecycle = util_mod.lifecycle
      original_buffer_cmd = vim.cmd.buffer
      original_echo = info_mod.echo
    end)

    after_each(function()
      rawset(process_mod, 'override', original_override)
      rawset(util_mod, 'get_bufinfo', original_get_bufinfo)
      rawset(util_mod, 'create_scratch_contents', original_create_scratch)
      rawset(util_mod, 'renew_buffer', original_renew_buffer)
      rawset(util_mod, 'lifecycle', original_lifecycle)
      rawset(info_mod, 'echo', original_echo)
      vim.cmd.buffer = original_buffer_cmd
    end)

    it('decrypts and opens a scratch buffer when the file is valid sops-encrypted data', function()
      rawset(util_mod, 'get_bufinfo', function(bufname, filetype)
        return { bufnr = 12, filepath = '/path/to/secret.yaml', filetype = filetype or 'yaml' }
      end)
      rawset(info_mod, 'echo', function(_, msg, _)
        assert.are.equal('Public-key not found.', msg)
      end)

      local scratch_bufnr = 99
      local create_scratch_called = false
      rawset(util_mod, 'create_scratch_contents', function(uri, filepath, filetype, contents)
        create_scratch_called = true
        assert.are.equal('/path/to/secret.yaml', filepath)
        assert.are.equal('decrypted_content_here', contents)
        return scratch_bufnr
      end)

      local renew_buffer_called = false
      rawset(util_mod, 'renew_buffer', function(bufnr)
        renew_buffer_called = true
        assert.are.equal(12, bufnr)
      end)

      local lifecycle_called = false
      rawset(util_mod, 'lifecycle', function(augroup, buffers, bufnr, callback)
        lifecycle_called = true
        assert.are.equal(scratch_bufnr, bufnr)
        assert.is_not_nil(callback)
      end)

      local buffer_cmd_called_with = nil
      vim.cmd.buffer = function(bufnr)
        buffer_cmd_called_with = bufnr
      end

      local override_call_count = 0
      rawset(process_mod, 'override', function(cmd, opts, on_exit)
        override_call_count = override_call_count + 1
        if override_call_count == 1 then
          assert.is_true(vim.tbl_contains(cmd, 'filestatus'))
          return {
            wait = function()
              return { code = 0, stdout = '{"encrypted":true}', stderr = '' }
            end,
          }
        elseif override_call_count == 2 then
          assert.is_true(vim.tbl_contains(cmd, 'decrypt'))
          on_exit({ code = 0, stdout = 'decrypted_content_here', stderr = '' })
          return {}
        end
      end)

      sops.decrypt_buffer('secret.yaml', true, { input_type = 'yaml' })

      assert.are.equal(2, override_call_count)
      assert.is_true(create_scratch_called)
      assert.are.equal(scratch_bufnr, buffer_cmd_called_with)
      assert.is_true(renew_buffer_called)
      assert.is_true(lifecycle_called)
    end)

    it('if a non-table value is passed to key_spec, report an error and return nil', function()
      local echoed_msg = nil
      local echoed_level = nil
      rawset(info_mod, 'echo', function(_, msg, level)
        echoed_msg = msg
        echoed_level = level
      end)

      local res = sops.get_key('secrets.yaml', 'invalid_key_spec')

      assert.is_nil(res)
      assert.are.equal('Invalid keys specified.', echoed_msg)
      assert.are.equal('ERROR', echoed_level)

      rawset(info_mod, 'echo', original_echo)
    end)
  end)

  describe('.encrypt_buffer()', function()
    local process_mod = require('cryption.lib.process')
    local info_mod = require('cryption.info')

    local original_override
    local original_confirm
    local original_buf_get_name
    local original_buf_get_lines
    local original_fnamemodify
    local original_root

    before_each(function()
      original_override = process_mod.override
      original_confirm = info_mod.confirm
      original_buf_get_name = vim.api.nvim_buf_get_name
      original_buf_get_lines = vim.api.nvim_buf_get_lines
      original_fnamemodify = vim.fn.fnamemodify
      original_root = vim.fs.root
    end)

    after_each(function()
      rawset(process_mod, 'override', original_override)
      rawset(info_mod, 'confirm', original_confirm)
      vim.api.nvim_buf_get_name = original_buf_get_name
      vim.api.nvim_buf_get_lines = original_buf_get_lines
      vim.fn.fnamemodify = original_fnamemodify
      rawset(vim.fs, 'root', original_root)
    end)

    it('encrypts the current buffer asynchronously when filepath is nil and the user confirms', function()
      local target_bufnr = vim.api.nvim_get_current_buf()

      vim.api.nvim_buf_get_name = function(bufnr)
        if bufnr == target_bufnr then
          return '/path/to/current_secret.yaml'
        end
        return original_buf_get_name(bufnr)
      end

      local confirm_called = false
      rawset(info_mod, 'confirm', function(msg)
        confirm_called = true
        return true
      end)

      vim.fn.fnamemodify = function(mods, flag)
        if mods == '%' then
          return '/path/to/current_secret.yaml'
        end
        return original_fnamemodify(mods, flag)
      end

      rawset(vim.fs, 'root', function()
        return '/path/to'
      end)

      local dummy_lines = { 'foo: bar', 'baz: qux' }
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.api.nvim_buf_get_lines = function(bufnr, start_idx, end_idx, strict)
        if bufnr == 0 or bufnr == target_bufnr then
          return dummy_lines
        end
        return original_buf_get_lines(bufnr, start_idx, end_idx, strict)
      end

      local override_called = false
      rawset(process_mod, 'override', function(cmd, opts, on_exit)
        override_called = true
        assert.is_true(vim.tbl_contains(cmd, 'encrypt'))
        assert.is_true(vim.tbl_contains(cmd, '/path/to/current_secret.yaml'))
        assert.are.same(dummy_lines, opts.stdin)
        on_exit({ code = 0, stdout = 'encrypted_data', stderr = '' })
        return {}
      end)

      local echoed_msg = nil
      local original_echo = info_mod.echo
      rawset(info_mod, 'echo', function(self, msg, level, ...)
        echoed_msg = msg
      end)

      sops.encrypt_buffer(nil, { range = { s = 0, e = -1 } })
      vim.cmd('redraw')

      assert.is_true(confirm_called)
      assert.is_true(override_called)
      vim.schedule(function()
        assert.are.equal('Encrypted: /path/to/current_secret.yaml', echoed_msg)
      end)

      rawset(info_mod, 'echo', original_echo)
    end)
  end)

  describe('.terminal_wrap()', function()
    local process_mod = require('cryption.lib.process')
    local original_override

    before_each(function()
      original_override = process_mod.override
    end)

    after_each(function()
      rawset(process_mod, 'override', original_override)
    end)

    it('sets env vars before calling term_fn and restores them afterward', function()
      local info_mod = require('cryption.info')
      local original_echo = info_mod.echo
      local original_notify = info_mod.notify
      rawset(info_mod, 'echo', function() end)
      rawset(info_mod, 'notify', function() end)

      rawset(process_mod, 'override', function(cmd, opts, on_exit)
        vim.schedule(function()
          on_exit({
            code = 0,
            stdout = 'SECRET_KEY=abc123\nANOTHER_VAR=hello\n',
            stderr = '',
          })
        end)
        return {}
      end)

      local env_during_call = {}
      local term_fn = function(arg1, arg2)
        env_during_call.SECRET_KEY = vim.env.SECRET_KEY
        env_during_call.ANOTHER_VAR = vim.env.ANOTHER_VAR
        env_during_call.arg1 = arg1
        env_during_call.arg2 = arg2
      end

      local original_secret = vim.env.SECRET_KEY
      local original_another = vim.env.ANOTHER_VAR

      sops.terminal_wrap('secrets.env', {}, term_fn, { 'foo', 'bar' })
      vim.cmd('redraw')

      vim.schedule(function()
        assert.are.equal('abc123', env_during_call.SECRET_KEY)
        assert.are.equal('hello', env_during_call.ANOTHER_VAR)
        assert.are.equal('foo', env_during_call.arg1)
        assert.are.equal('bar', env_during_call.arg2)
        assert.are.equal(original_secret, vim.env.SECRET_KEY)
        assert.are.equal(original_another, vim.env.ANOTHER_VAR)

        rawset(info_mod, 'echo', original_echo)
        rawset(info_mod, 'notify', original_notify)
      end)
    end)

    it('does not call term_fn when sops exits with a non-zero code', function()
      rawset(process_mod, 'override', function(cmd, opts, on_exit)
        on_exit({ code = 1, stdout = '', stderr = 'access denied' })
        return {}
      end)

      local term_fn_called = false
      local term_fn = function()
        term_fn_called = true
      end

      sops.terminal_wrap('secrets.env', {}, term_fn, {})

      assert.is_false(term_fn_called)
    end)
  end)
end)
