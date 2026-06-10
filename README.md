# explorer.nvim

A minimal floating file explorer for Neovim using `fd` and `fzf`.

## Requirements

- [fd](https://github.com/sharkdp/fd)
- [fzf](https://github.com/junegunn/fzf)

## Usage

```
:Explorer
```

Opens a floating window listing files in the current working directory.

| Key         | Action                       |
| ----------- | ---------------------------- |
| `<cr>`      | Open file or enter directory |
| `<bs>`      | Go back                      |
| `a`         | Add file or directory        |
| `m`         | Move                         |
| `c`         | Copy                         |
| `d`         | Delete                       |
| `f`         | Filter                       |
| `R`         | Refresh                      |
| `q / <esc>` | Close                        |

