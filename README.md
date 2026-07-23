# highlighter.nvim

Persistent yellow highlights for neovim.

Mark regions like with a highlighter pen, toggling an overlapping region erases
the highlights.

## features

- `gh{motion}`: toggle a highlight (e.g. `ghiw` for inner word, `ghip` for paragraph)
- `gh`: (visual) toggle over a selection
- `gH`: clear all highlights in the buffer
- persists across sessions
- smart trimming

## install

with lazy.nvim:

```lua
{
    "marcelmanz/highlighter.nvim",
    config = function()
        require("highlighter").setup()
    end,
}
```

with `vim.pack` (built-in, neovim 0.12+):

```lua
vim.pack.add({ "https://github.com/marcelmanz/highlighter.nvim" })
require("highlighter").setup()
```

# development

Requires neovim 0.10+ and [stylua](https://github.com/JohnnyMorganz/StyLua).
