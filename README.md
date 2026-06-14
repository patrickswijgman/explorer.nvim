# explorer.nvim

A minimal floating file explorer for Neovim where you manage files by editing a
buffer, inspired by [oil.nvim](https://github.com/stevearc/oil.nvim).

It lists every file in the current working directory (recursively) with `fd`. To
create, move, copy, or delete files you edit the list like a normal buffer and
write it with `:w` — the changes are then applied to disk.

## Requirements

- [fd](https://github.com/sharkdp/fd)
- [nerd font](https://www.nerdfonts.com/) (for the icons)
- unix commands (`touch`, `mkdir`, `mv`, `cp`, `rm`)

## Usage

```
:Explorer
```

Opens a floating window listing the files in the current working directory.
Opens automatically when Neovim is started with a directory, e.g. `nvim .`

Each line is prefixed with a dimmed id like `[001]` that ties it back to its
file on disk. Edit the path after the id — the cursor stays out of the id — and
leave the id itself alone. New lines you add have no id and become new files.

### Editing

Make your changes in the buffer, then `:w` to apply them:

| Edit                                 | Result                              |
| ------------------------------------ | ----------------------------------- |
| Change a line's path                 | Move / rename the file              |
| Add a new line with a path           | Create a file                       |
| Add a new line ending in `/`         | Create a directory                  |
| Duplicate a line and change its path | Copy the file                       |
| Delete a line                        | Delete the file                     |

On `:w` you get a summary of the planned operations and a confirmation prompt
before anything touches disk.

Paths are relative to the working directory, so you can move a file into another
directory by editing its path (e.g. `src/foo.lua` → `lib/foo.lua`). Intermediate
directories are created as needed. Existing files are never overwritten — a move
or copy onto a path that already exists is skipped.

### Keymaps

| Key    | Action                         |
| ------ | ------------------------------ |
| `<cr>` | Open the file under the cursor |
| `:w`   | Apply changes                  |
| `q`    | Close                          |

### Example

```lua
-- Recommended: disable the builtin netrw file explorer
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

vim.keymap.set("n", "<leader>e", ":Explorer<cr>", { desc = "Open explorer" })
```
