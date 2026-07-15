---@meta

---Core plugin information and internal runtime states shared across modules.
---@class CryptionInformation
---@field name string # The canonical plugin name ("cryption").
---@field label string # Prefixed label used for errors and logs.
---@field age_uri string # URI scheme prefix used for age scratch buffers ("cryption-age://").
---@field sops_uri string # URI scheme prefix used for SOPS scratch buffers ("cryption-sops://").
---@field augroup integer # The Neovim autocmd group ID for managing decrypted buffer lifecycles.
---@field decrypted_buffers table<integer, boolean> # Registry of active decrypted buffer numbers.
---@field confirm fun(self, msg: string): boolean # Prompts the user with a [Yes/No] dialog via vim.fn.confirm. Returns true if Yes.
---@field echo fun(self, msg, level?, history?, opts?) # Custom messaging pipeline for consistent plugin echoes.
---@field notify fun(self, msg, level?, once?) # Wrapper for safe Neovim notifications.

---Available encryption backend modules.
---@alias Modules
---| 'age' # Age encryption backend.
---| 'sops' # Mozilla SOPS backend.

---@private
---Combined configuration options used internally by the SOPS command parser.
---@class ParseOptions : SopsDecryptOptions,SopsGetKeyOptions
---@field output? boolean # Directs output formatting behavior during the parse stream.
---@field extract? string # Pre-computed path expression string used to pluck specific keys.
