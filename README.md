# explorer.nvim

A minimal floating file explorer for Neovim using `fd` and `fzf`.

## Requirements

- [fd](https://github.com/sharkdp/fd)
- [fzf](https://github.com/junegunn/fzf)
- [nerd font](https://www.nerdfonts.com/) (for the icons)
- unix commands (`touch`, `mkdir`, `mv`, `cp`, `rm`)

## Usage

```
:Explorer
```

Opens a floating window listing files in the current working directory.

### Example

```lua
-- Recommended: disable the builtin netrw file explorer
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

vim.keymap.set("n", "<leader>e", ":Explorer<cr>", { desc = "Open explorer" })
```

### Keymaps

| Key         | Action                                       |
| ----------- | -------------------------------------------- |
| `<cr>`      | Open file or enter directory (resets filter) |
| `<bs>`      | Go back                                      |
| `a`         | Add file or directory                        |
| `m`         | Move                                         |
| `c`         | Copy                                         |
| `d`         | Delete                                       |
| `f`         | Filter                                       |
| `R`         | Refresh (resets filter)                      |
| `q / <esc>` | Close                                        |
