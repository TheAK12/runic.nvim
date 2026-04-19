# runic.nvim

Smart project/file runner for Neovim.

It detects project context, ranks candidate commands, runs the best one, and
can show or pick alternatives.

Module names:

- preferred: `runic`
- compatibility alias: `smart_run`

## Features

- Auto run (`:SmartRun`) from project/file context
- Candidate picker (`:SmartRunPick`)
- Explain mode (`:SmartRunExplain`)
- Last command rerun (`:SmartRunLast`)
- Cache + cache clear command (`:SmartRunCacheClear`)
- Override hooks (`vim.g.smart_run_command`, `vim.g.smart_run_filetype_commands`, `vim.g.smart_run_resolver`)

## Install (vim.pack)

```lua
vim.pack.add({
  { src = "https://github.com/TheAK12/runic.nvim" },
})
vim.cmd.packadd("runic.nvim")
require("smart_run").setup({})
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

or

```lua
require("smart_run").setup({})
```

## Global overrides

- `vim.g.smart_run_command = "<cmd>"`
- `vim.g.smart_run_filetype_commands = { python = "...", go = "..." }`
- `vim.g.smart_run_resolver = function(ctx) return { command = "...", priority = 9999 } end`
- `vim.g.smart_run_python_project_runner = true`
- `vim.g.smart_run_focus_terminal = true`
- `vim.g.smart_run_use_snacks_terminal = true`

## Commands

- `:SmartRun`
- `:SmartRunPick`
- `:SmartRunFile`
- `:SmartRunProject`
- `:SmartRunExplain`
- `:SmartRunLast`
- `:SmartRunCacheClear`
