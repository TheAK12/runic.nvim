# runic.nvim

Smart project/file runner for Neovim.

It detects project context, ranks candidate commands, runs the best one, and
can pick from candidates when needed.

Module name:

- `runic`

## Features

- Auto run (`:RunicRun`) from project/file context
- Candidate picker (`:RunicPick`)
- Explain mode (`:RunicExplain`)
- Last command rerun (`:RunicLast`)
- Cache controls (`:RunicCacheClear`, `:RunicCacheInfo`)
- Toolchain diagnostics (`:RunicHealth`)
- Override hooks (`vim.g.runic_command`, `vim.g.runic_filetype_commands`, `vim.g.runic_resolver`)
- Root detection follows the current file path (works even when current working directory is elsewhere)

## Install (vim.pack)

```lua
vim.pack.add({
  { src = "https://github.com/TheAK12/runic.nvim" },
})
vim.cmd.packadd("runic.nvim")
require("runic").setup({})
```

## Install (lazy.nvim)

```lua
{
  "TheAK12/runic.nvim",
  main = "runic",
  opts = {
    create_commands = true,
    create_keymaps = true,
  },
}
```

## Setup

```lua
require("runic").setup({
  create_commands = true,
  create_keymaps = true,
  keymaps = {
    run = "<leader>r",
    pick = "<leader>rp",
    last = "<leader>rl",
    legacy = "<leader>R",
  },
})
```

## Global overrides

- `vim.g.runic_command = "<cmd>"`
- `vim.g.runic_filetype_commands = { python = "...", go = "..." }`
- `vim.g.runic_resolver = function(ctx) return { command = "...", priority = 9999 } end`
- `vim.g.runic_python_project_runner = true`
- `vim.g.runic_focus_terminal = true`
- `vim.g.runic_use_snacks_terminal = true`
- `vim.g.runic_open_url = true`

## Commands

- `:RunicRun` - runs the top-ranked command for the current buffer
- `:RunicPick` - opens a picker so you can choose which command to run
- `:RunicRunFile` - ignores project rules and runs in file mode only
- `:RunicRunProject` - ignores file rules and runs in project mode only
- `:RunicPreview` - shows selected command, working directory, and top candidates
- `:RunicExplain` - alias of `:RunicPreview`
- `:RunicLast` - reruns the last command executed by runic
- `:RunicHistory` - shows recent runic commands and lets you rerun one
- `:RunicCacheClear` - clears cached resolution results
- `:RunicCacheInfo` - shows cache entry count, generation, hits, and misses
- `:RunicHealth` - checks common language/tool executables on your system
- `:RunicReload` - reapplies setup/options without restarting Neovim
