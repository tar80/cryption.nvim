local M = {}

M.name = 'cryption'
M.age_uri = M.name .. '-age://'
M.sops_uri = M.name .. '-sops://'
M.augroup = vim.api.nvim_create_augroup(M.name, { clear = true })
M.decrypted_buffers = {}

function M:confirm(msg)
  local ask_msg = ('[%s] %s'):format(self.name, msg)
  local choice = vim.fn.confirm(ask_msg, '&Yes\n&No', 2)
  return (choice == 1)
end

M = require('cryption.helper.info').instance(M)

return M --[[@as CryptionInformation]]
