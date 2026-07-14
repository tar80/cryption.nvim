---@diagnostic disable: duplicate-set-field
local assert = require('luassert')
local util = require('cryption.util')

describe('util', function()
  describe('.extract_filetype()', function()
    it('should correctly extract extension from filenames with standard extensions', function()
      assert.are.equal('yaml', util.extract_filetype('secrets.yaml'))
      assert.are.equal('json', util.extract_filetype('config.json'))
    end)

    it('should strip the .age extension and extract the underlying file extension', function()
      assert.are.equal('yaml', util.extract_filetype('secrets.yaml.age'))
      assert.are.equal('json', util.extract_filetype('config.json.age'))
    end)

    it('should correctly extract the final extension even from multi-dot filenames', function()
      assert.are.equal('yaml', util.extract_filetype('app.production.yaml'))
      assert.are.equal('json', util.extract_filetype('auth.config.json.age'))
    end)

    it('should return nil if there is no extension or if the filename ends with a dot', function()
      assert.is_nil(util.extract_filetype('Dockerfile'))
      assert.is_nil(util.extract_filetype('no_extension_file.age'))
      assert.is_nil(util.extract_filetype('basename.'))
    end)
  end)

  describe('.create_scratch_contents()', function()
    local original_create_buf
    local original_bufnr_fn
    local original_buf_delete
    local original_buf_set_name
    local original_buf_set_lines
    local original_set_option
    local original_reset_buffer

    before_each(function()
      original_create_buf = vim.api.nvim_create_buf
      original_bufnr_fn = vim.fn.bufnr
      original_buf_delete = vim.api.nvim_buf_delete
      original_buf_set_name = vim.api.nvim_buf_set_name
      original_buf_set_lines = vim.api.nvim_buf_set_lines
      original_set_option = vim.api.nvim_set_option_value
      original_reset_buffer = util.reset_buffer_contents
    end)

    after_each(function()
      vim.api.nvim_create_buf = original_create_buf
      vim.fn.bufnr = original_bufnr_fn
      vim.api.nvim_buf_delete = original_buf_delete
      vim.api.nvim_buf_set_name = original_buf_set_name
      vim.api.nvim_buf_set_lines = original_buf_set_lines
      vim.api.nvim_set_option_value = original_set_option
      rawset(util, 'reset_buffer_contents', original_reset_buffer)
    end)

    it('should create and configure a new scratch buffer when no duplicate buffer exists', function()
      local new_bufnr = 101
      vim.api.nvim_create_buf = function(_, _)
        return new_bufnr
      end
      vim.fn.bufnr = function(_)
        return -1
      end

      local delete_called = false
      vim.api.nvim_buf_delete = function(_, _)
        delete_called = true
      end

      local set_name_called_with = nil
      vim.api.nvim_buf_set_name = function(bufnr, name)
        if bufnr == new_bufnr then
          set_name_called_with = name
        end
      end

      local set_lines_called = false
      vim.api.nvim_buf_set_lines = function(bufnr, idx_start, idx_end, strict, lines)
        set_lines_called = true
        assert.are.same({ 'line1', 'line2' }, lines)
      end

      rawset(util, 'reset_buffer_contents', function(_, cb)
        cb()
      end)

      local options_set = {}
      vim.api.nvim_set_option_value = function(name, value, opts)
        if opts.buf == new_bufnr then
          options_set[name] = value
        end
      end

      local res_bufnr = util.create_scratch_contents('sops://', 'secret.yaml', 'yaml', 'line1\nline2')

      assert.are.equal(new_bufnr, res_bufnr)
      assert.is_false(delete_called)
      assert.are.equal('sops://secret.yaml', set_name_called_with)
      assert.is_true(set_lines_called)
      assert.are.equal('yaml', options_set['filetype'])
      assert.are.equal('acwrite', options_set['buftype'])
    end)

    it('should force-delete the existing duplicate buffer before creating a new one', function()
      local old_bufnr = 55
      local new_bufnr = 102

      vim.api.nvim_create_buf = function()
        return new_bufnr
      end

      -- Mock that an existing buffer (No. 55) already exists
      vim.fn.bufnr = function(name)
        if name == 'sops://secret.yaml' then
          return old_bufnr
        end
        return -1
      end

      local deleted_bufnr = nil
      local delete_opts = nil
      vim.api.nvim_buf_delete = function(bufnr, opts)
        deleted_bufnr = bufnr
        delete_opts = opts
      end

      vim.api.nvim_buf_set_name = function() end
      vim.api.nvim_set_option_value = function() end

      util.create_scratch_contents('sops://', 'secret.yaml', 'yaml', nil)

      -- Verify that the old duplicate buffer was force-deleted
      assert.are.equal(old_bufnr, deleted_bufnr)
      assert.is_true(delete_opts.force)
    end)
  end)

  describe('.get_bufinfo()', function()
    local original_fnamemodify
    local original_bufnr
    local original_get_current_buf
    local original_buf_get_name
    local original_extract

    before_each(function()
      original_fnamemodify = vim.fn.fnamemodify
      original_bufnr = vim.fn.bufnr
      original_get_current_buf = vim.api.nvim_get_current_buf
      original_buf_get_name = vim.api.nvim_buf_get_name
      original_extract = util.extract_filetype
    end)

    after_each(function()
      vim.fn.fnamemodify = original_fnamemodify
      vim.fn.bufnr = original_bufnr
      vim.api.nvim_get_current_buf = original_get_current_buf
      vim.api.nvim_get_name = original_buf_get_name
      rawset(util, 'extract_filetype', original_extract)
    end)

    it('should resolve the filepath and bufnr when a valid bufname string is provided', function()
      vim.fn.fnamemodify = function(_, _)
        return '/path/to/test.json'
      end
      vim.fn.bufnr = function(path)
        if path == '/path/to/test.json' then
          return 42
        end
        return -1
      end

      local info = util.get_bufinfo('test.json', 'json')

      assert.are.equal('/path/to/test.json', info.filepath)
      assert.are.equal(42, info.bufnr)
      assert.are.equal('json', info.filetype)
    end)

    it(
      'should retrieve info from the current buffer and automatically extract the filetype if bufname is nil or empty',
      function()
        vim.api.nvim_get_current_buf = function()
          return 10
        end
        vim.api.nvim_buf_get_name = function(bufnr)
          if bufnr == 10 then
            return '/path/to/secret.yaml.age'
          end
          return ''
        end

        vim.api.nvim_buf_set_name = function() end
        vim.api.nvim_set_option_value = function() end

        rawset(util, 'extract_filetype', function(path)
          if path == '/path/to/secret.yaml.age' then
            return 'yaml'
          end
          return nil
        end)

        local info = util.get_bufinfo(nil, nil)

        assert.are.equal(10, info.bufnr)
        assert.are.equal('/path/to/secret.yaml.age', info.filepath)
        assert.are.equal('yaml', info.filetype)
      end
    )
  end)
end)
