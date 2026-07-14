---@meta
---@brief [[
---*cryption.txt*                             Encrypt and decrypt buffers in Neovim
---
---Author: tar80 (https://github.com/tar80)
---License: Apache License
---Repository: https://github.com/tar80/cryption.nvim
---@brief ]]
---@toc cryption-contents

---@mod cryption-introduction INTRODUCTION

---@brief [[
---*cryption.nvim* encrypts and decrypts buffers using age and SOPS.
---Decrypted content is opened in a scratch buffer. On save, the source
---file is automatically re-encrypted and overwritten.
---@brief ]]

local cryption = {}

---@mod cryption-setup SETUP

---Configures the cryption.nvim plugin with user-defined settings.
---@param user_config? {age?:AgeConfig, sops?:SopsConfig}
function cryption.setup(user_config) end

---@class AgeConfig
---Whether the Age encryption module is enabled.
---@field enable boolean Default: false
---Resolved executable path for age.
---@field age string Default: "age"
---Resolved executable path for age-keygen.
---@field keygen string Default: "age-keygen"
---Resolved executable path for age-inspect.
---@field inspect string Default: "age-inspect"

---@class SopsConfig
---Whether the SOPS encryption module is enabled.
---@field enable boolean Default: false
---Resolved executable path or command for sops.
---@field sops string Default: "sops"
---Default output format when encrypting new files.
---@field encrypt_default_output_type string Default: "yaml"

---@mod cryption-function FUNCTIONS

---Encrypt the current buffer using the age backend and write to `filepath`.
---If `filepath` is `nil`, prompts to overwrite the current buffer.
---@param filepath? string Target file path to encrypt.
---@param opts? AgeEncryptOptions
function cryption.age_encrypt(filepath, opts) end

---@class AgeEncryptOptions
---Output ASCII-armored encryption.
---@field armor? boolean
---Encrypt with a passphrase (interactive).
---@field passphrase? boolean
---Path to a recipients file or identity file.
---@field key_file? string
---Recipient public key string.
---@field public_key? string

---Decrypt an age-encrypted file into a scratch buffer.
---On save, the source file is re-encrypted and overwritten.
---@param filepath? string Target buffer name or path. Uses current buffer if `nil`.
---@param close_source boolean Whether to close the source buffer after decryption.
---@param opts AgeDecryptOptions
---@usage [[
--->
---local cryption = require('cryption')
---
---## Direct secret key
---# get_key_cmd as string: used directly as the age secret key.
---cryption.age_decrypt('secrets.yaml.age', true, {
---  get_key_cmd = 'AGE-SECRET-KEY-1QQQQQQ...',
---})
---
---## KeePassXC
---# get_key_cmd as table: executed as a command.
---# The user is prompted for a master password via inputsecret,
---# which is passed to the command via stdin.
---# The command's stdout is used as the age secret key.
---cryption.age_decrypt('secrets.yaml.age', true, {
---  get_key_cmd = {
---    'keepassxc-cli', 'show',
---    '-q',
---    '-k', '/path/to/key.file',
---    '/path/to/database.kdbx',
---    'Age',
---    '-a', 'Password',
---  },
---})
---
---## Bitwarden
---# Ensure BW_SESSION is set before calling: bw unlock
---cryption.age_decrypt('secrets.yaml.age', true, {
---  get_key_cmd = {
---    'bw', 'get', 'password', 'age-secret-key',
---  },
---})
---@usage ]]
function cryption.age_decrypt(filepath, close_source, opts) end

---@class AgeDecryptOptions
---Override the detected filetype of the decrypted buffer.
---@field filetype? string
---A string is used directly as the age secret key.
---A table is executed as a command via stdin.
---@field get_key_cmd? string|string[]
---Use ASCII-armored format when re-encrypting on save.
---@field armor? boolean
---Path to an identity file for decryption. Used as-is for re-encryption, preserving all original recipients.
---@field key_file? string
---Explicit public key to use for re-encryption.
---@field public_key? string

---@divider -

---Encrypt the current buffer using the SOPS backend and write to `filepath`.
---If `filepath` is `nil`, prompts to overwrite the current buffer.
---@param filepath? string Target file path to encrypt.
---@param opts? SopsEncryptOptions
function cryption.sops_encrypt(filepath, opts) end

---@class SopsEncryptOptions
---Format of the current unencrypted buffer (e.g., `'yaml'`, `'json'`).
---@field input_type? string
---Target encrypted file format (e.g., `'yaml'`, `'json'`).
---@field output_type? string
---Targeted encryption key as a pair. e.g. `{'age', 'age1...'}` or `{'pgp', 'FBC7...'}`.
---@field public_key? string[]
---Specific line range for selective/partial encryption.
---@field range? {s:integer,e:integer}

---Decrypt a SOPS-encrypted file into a scratch buffer.
---On save, the source file is re-encrypted and overwritten.
---@param filepath? string Target buffer name or path. Uses current buffer if `nil`.
---@param close_source boolean Whether to close the source buffer after decryption.
---@param opts SopsDecryptOptions
function cryption.sops_decrypt(filepath, close_source, opts) end

---@class SopsDecryptOptions
---Explicit public key override pair for the decryption process.
---@field public_key? string[]
---Source file format to guide the decryption parser.
---@field input_type? string
---Custom environment variables injection.
---@field env? table<string, string>

---Synchronously retrieve a specific value from a SOPS-encrypted file.
---Requires `SOPS_AGE_KEY_FILE` to be set in the environment, or pass credentials explicitly via `opts.env` (e.g., `{ SOPS_AGE_KEY_FILE = '/path/to/key.txt' }`).
---@param filepath string Target encrypted file path.
---@param key_spec string[] Key path components (e.g., `{"path/to/secrets", "key_name"}`).
---@param opts? SopsGetKeyOptions Retrieval options.
---@return string|nil _ The decrypted value, or `nil` if failed.
---@usage [[
--->
---local cryption = require('cryption')
---local value = cryption.sops_extract('secrets.yaml', { 'path/to/secrets', 'SOME_API_KEY' })
---if value then
---  print(value)
---end
---@usage ]]
function cryption.sops_extract(filepath, key_spec, opts) end

---@class SopsGetKeyOptions
---Source file format to guide the decryption parser.
---@field input_type? string
---Custom environment variables injection.
---@field env? table<string, string>

---Decrypt a SOPS dotenv-style file and inject values as environment variables,
---then call `term_fn` with `fn_args`. Environment variables are restored after
---`term_fn` returns. `term_fn` must complete synchronously.
---@param filepath string Path to the SOPS-encrypted dotenv file.
---@param opts vim.SystemOpts Options passed to the underlying process.
---@param term_fn fun(...) Function to call with environment variables injected.
---@param fn_args any[] Arguments unpacked and passed to `term_fn`.
---@usage [[
--->
---local cryption = require('cryption')
---
---local function open_terminal(cmd)
---  vim.cmd.new()
---  vim.fn.jobstart(cmd, { term = true })
---end
---
---cryption.sops_exec_env_wrap(
---  '.env.sops',
---  {},
---  open_terminal,
---  { 'bash' }
---)
---@usage ]]
function cryption.sops_exec_env_wrap(filepath, opts, term_fn, fn_args) end

---@divider -
---@export cryption
return cryption
