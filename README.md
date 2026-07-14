# cryption.nvim

A Neovim plugin for encrypting and decrypting buffers using Age and Sops.

## Requirements

- Neovim >= 0.13
- [Age](https://github.com/FiloSottile/age)
- [Sops](https://github.com/getsops/sops)

## Installation

**lazy.nvim**

```lua
{
  'tar80/cryption.nvim',
  opts = {
    age = {
      enable = true,
    },
    sops = {
      enable = true,
    },
  },
}
```

**vim.pack** (Neovim 0.13+)

```lua
vim.pack.add('https://github.com/tar80/cryption.nvim')
```

## Configuration

```lua
require('cryption').setup({
  age = {
    enable = false, -- Enable age backend
    age = 'age', -- Path to age executable
    keygen = 'age-keygen', -- Path to age-keygen executable
    inspect = 'age-inspect', -- Path to age-inspect executable
  },
  sops = {
    enable = false, -- Enable SOPS backend
    sops = 'sops', -- Path to sops executable
    encrypt_default_output_type = 'yaml', -- Default output format when encrypting
  },
})
```

## API

### age

#### `require('cryption').age_encrypt(filepath, opts)`

Encrypt the current buffer using age.

| Parameter  | Type                | Description                                      |
| ---------- | ------------------- | ------------------------------------------------ |
| `filepath` | `string\|nil`       | Target file path. Prompts to overwrite if `nil`. |
| `opts`     | `AgeEncryptOptions` | Encryption options (see below).                  |

**AgeEncryptOptions**

| Field        | Type      | Description                                 |
| ------------ | --------- | ------------------------------------------- |
| `passphrase` | `boolean` | Encrypt with a passphrase.                  |
| `key_file`   | `string`  | Path to a recipients file or identity file. |
| `public_key` | `string`  | Recipient public key string.                |
| `armor`      | `boolean` | Output ASCII-armored encryption.            |

---

#### `require('cryption').age_decrypt(filepath, close_source, opts)`

Decrypt an age-encrypted file into a scratch buffer. When the scratch buffer is saved, the source file is re-encrypted and overwritten.

| Parameter      | Type                | Description                                     |
| -------------- | ------------------- | ----------------------------------------------- |
| `filepath`     | `string\|nil`       | Target file path. Uses current buffer if `nil`. |
| `close_source` | `boolean`           | Close the source buffer after decryption.       |
| `opts`         | `AgeDecryptOptions` | Decryption options (see below).                 |

**AgeDecryptOptions**

| Field         | Type               | Description                                                               |
| ------------- | ------------------ | ------------------------------------------------------------------------- |
| `filetype`    | `string`           | Override the detected filetype of the decrypted buffer.                   |
| `get_key_cmd` | `string\|string[]` | Command to retrieve the secret key. A string is used directly as the key. |
| `key_file`    | `string`           | Path to an identity file for decryption.                                  |
| `public_key`  | `string`           | Explicit public key to use for re-encryption.                             |
| `armor`       | `boolean`          | Use ASCII-armored format when re-encrypting.                              |

---

### sops

#### `require('cryption').sops_encrypt(filepath, opts)`

Encrypt the current buffer using SOPS.

| Parameter  | Type                 | Description                                      |
| ---------- | -------------------- | ------------------------------------------------ |
| `filepath` | `string\|nil`        | Target file path. Prompts to overwrite if `nil`. |
| `opts`     | `SopsEncryptOptions` | Encryption options (see below).                  |

**SopsEncryptOptions**

| Field         | Type                     | Description                                                                 |
| ------------- | ------------------------ | --------------------------------------------------------------------------- |
| `input_type`  | `string`                 | Format of the unencrypted buffer (e.g. `'yaml'`, `'json'`).                 |
| `output_type` | `string`                 | Target encrypted file format.                                               |
| `public_key`  | `string[]`               | Key pair for encryption, e.g. `{'age', 'age1...'}` or `{'pgp', 'FBC7...'}`. |
| `range`       | `{s:integer, e:integer}` | Line range for partial encryption.                                          |

---

#### `require('cryption').sops_decrypt(filepath, close_source, opts)`

Decrypt a SOPS-encrypted file into a scratch buffer. When the scratch buffer is saved, the source file is re-encrypted and overwritten.

| Parameter      | Type                 | Description                                     |
| -------------- | -------------------- | ----------------------------------------------- |
| `filepath`     | `string\|nil`        | Target file path. Uses current buffer if `nil`. |
| `close_source` | `boolean`            | Close the source buffer after decryption.       |
| `opts`         | `SopsDecryptOptions` | Decryption options (see below).                 |

**SopsDecryptOptions**

| Field        | Type                   | Description                                                   |
| ------------ | ---------------------- | ------------------------------------------------------------- |
| `input_type` | `string`               | Source file format to guide the decryption parser.            |
| `public_key` | `string[]`             | Explicit public key override pair for the decryption process. |
| `env`        | `table<string,string>` | Custom environment variables (e.g. AWS/GCP credentials).      |

---

#### `require('cryption').sops_extract(filepath, key_spec, opts)`

Synchronously retrieve a specific value from a SOPS-encrypted file.

| Parameter  | Type                | Description                                           |
| ---------- | ------------------- | ----------------------------------------------------- |
| `filepath` | `string`            | Target encrypted file path.                           |
| `key_spec` | `string[]`          | Key path components, e.g. `{'database', 'password'}`. |
| `opts`     | `SopsGetKeyOptions` | Retrieval options (see below).                        |

**Returns:** `string|nil` — The decrypted value, or `nil` if failed.

**SopsGetKeyOptions**

| Field        | Type                   | Description                                              |
| ------------ | ---------------------- | -------------------------------------------------------- |
| `input_type` | `string`               | Source file format.                                      |
| `env`        | `table<string,string>` | Custom environment variables (e.g. AWS/GCP credentials). |

---

#### `require('cryption').sops_exec_env_wrap(filepath, opts, term_fn, fn_args)`

Decrypt a SOPS dotenv-style file and inject the values as environment variables before calling `term_fn`. Environment variables are restored after `term_fn` returns. `term_fn` must complete synchronously.

| Parameter  | Type             | Description                                           |
| ---------- | ---------------- | ----------------------------------------------------- |
| `filepath` | `string`         | Path to the SOPS-encrypted dotenv file.               |
| `opts`     | `vim.SystemOpts` | Options passed to the underlying process.             |
| `term_fn`  | `fun(...)`       | Function to call with environment variables injected. |
| `fn_args`  | `any[]`          | Arguments to pass to `term_fn`.                       |
