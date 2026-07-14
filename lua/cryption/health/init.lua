local M = {}

local function check_settings()
  vim.health.start('options:')

  local invalid_keys = require('cryption.config').get_invalid_keys()

  if invalid_keys ~= nil then
    for _, key in ipairs(invalid_keys) do
      vim.health.warn('Invalid key detected: ' .. key)
    end
  else
    vim.health.ok('All configuration keys are valid.')
  end
end

local function check_executables()
  vim.health.start('executable check:')

  if vim.fn.executable('sops') == 1 then
    vim.health.ok('sops is installed.')
  else
    vim.health.error(
      'sops: not found.',
      'Please install sops (https://github.com/getsops/sops) or ensure it is in your PATH.'
    )
  end

  if vim.fn.executable('age') == 1 then
    vim.health.ok('age is installed.')
  else
    vim.health.error(
      'age: not found.',
      'Please install age (https://github.com/FiloSottile/age) or ensure it is in your PATH.'
    )
  end

  if vim.fn.executable('age-keygen') == 1 then
    vim.health.ok('age-keygen is installed.')
  else
    vim.health.warn(
      'age-keygen not found.',
      'This is required for extracting public keys from secret keys. Please install it.'
    )
  end

  if vim.fn.executable('age-inspect') == 1 then
    vim.health.ok('age-inspect is installed.')
  else
    vim.health.warn('age-inspect not found.', 'This is required for age file inspection. Please install it.')
  end
end

M.check = function()
  check_executables()
  check_settings()
end

return M
