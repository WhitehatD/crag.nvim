# crag.nvim

Neovim integration for [**crag**](https://crag.sh) — make every AI agent obey your codebase.

## Features

- `:CragAnalyze`, `:CragCompile`, `:CragAudit`, `:CragDiff`, `:CragDoctor`, `:CragHookInstall`
- Auto-compile on `.claude/governance.md` save
- Statusline summary based on `crag audit --json`
- Native `vim.diagnostic` integration
- Windows-friendly CLI execution via argv lists instead of shell strings
- `:checkhealth crag` support

## Requirements

- Neovim 0.9+
- `crag` installed globally, or available via `npx`

## Installation

### lazy.nvim

```lua
{
  'WhitehatD/crag.nvim',
  config = function()
    require('crag').setup()
  end,
}
```

### packer.nvim

```lua
use({
  'WhitehatD/crag.nvim',
  config = function()
    require('crag').setup()
  end,
})
```

## Configuration

```lua
require('crag').setup({
  auto_compile = true,
  status_line = true,
  diagnostics = true,
  cli_path = nil,
})
```

## Commands

- `:CragAnalyze`
- `:CragCompile [target]`
- `:CragAudit`
- `:CragDiff`
- `:CragDoctor`
- `:CragHookInstall`
- `:CragRefresh`

## Statusline

```lua
require('lualine').setup({
  sections = {
    lualine_x = { function() return require('crag').status() end },
  },
})
```

---

## The crag ecosystem

[**crag.sh**](https://crag.sh) &middot; [Docs](https://crag.sh/docs) &middot; [GitHub](https://github.com/WhitehatD/crag) &middot; [npm](https://www.npmjs.com/package/@whitehatd/crag) &middot; [Dashboard](https://app.crag.sh) &middot; [VS Code](https://marketplace.visualstudio.com/items?itemName=whitehatd.vscode-crag) &middot; [Status](https://crag.sh/status)
