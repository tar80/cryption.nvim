local assert = require('luassert')
local helper_config = require('cryption.helper.config')
local config = require('cryption.config')
local info = require('cryption.info')

describe('config', function()
  describe('common_methods', function()
    local org_resolve = helper_config.resolve_config
    local org_detect = helper_config.detect_exe_path
    local org_echo = info.echo

    before_each(function()
      ---@diagnostic disable-next-line: duplicate-set-field
      helper_config.resolve_config = function(_, _, _, user_spec, _)
        return user_spec or {}
      end

      ---@diagnostic disable-next-line: duplicate-set-field
      helper_config.detect_exe_path = function(executables)
        local existence = {}
        for k, _ in pairs(executables) do
          existence[k] = '/mock/bin/' .. k
        end
        return existence, {}
      end

      info.echo = function() end
    end)

    after_each(function()
      helper_config.resolve_config = org_resolve
      helper_config.detect_exe_path = org_detect
      info.echo = org_echo
      package.loaded['cryption.config'] = nil
      config = require('cryption.config')
    end)

    describe(':ref()', function()
      it('can resolve a module config that is loaded later (lazy evaluation)', function()
        local instance_a = config.get('age', { age = { get_key_timeout = 1000 } })
        assert.is_nil(instance_a:ref('sops'))
        local instance_b = config.get('sops', { sops = { sops = 'custom_sops' } })

        local ref_to_b = instance_a:ref('sops')
        assert.is_not_nil(ref_to_b)
        assert.are.equal('/mock/bin/sops', ref_to_b.sops)
      end)

      it('returns a direct reference to the active master config table', function()
        local instance = config.get('age', { age = { get_key_timeout = 5000 } })
        local ref_1 = instance:ref('age')
        local ref_2 = instance:ref('age')

        assert.are.equal(ref_1, ref_2)

        ref_1.get_key_timeout = 9999
        assert.are.equal(9999, ref_2.get_key_timeout)
      end)
    end)

    describe(':reset()', function()
      it('restores instance values back to the master config state', function()
        local active = config.get('age', { age = { get_key_timeout = 5000 } })

        active.get_key_timeout = 0
        active.new_dirty_key = 'garbage'

        local refs = active:ref('age')
        assert.are.equal(0, refs.get_key_timeout)
        assert.are.equal('garbage', refs.new_dirty_key)

        active:reset('age')

        assert.are.equal(5000, active.get_key_timeout)
        assert.is_nil(active.new_dirty_key)
      end)
    end)
  end)
end)
