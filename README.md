# runic.nvim

Smart project/file runner for Neovim.

It detects project context, ranks candidate commands, runs the best one, and
can pick from candidates when needed.

Module name:

- `runic`

## Features

- Auto run (`:RunicRun`) from project/file context
- Intent picker (`:RunicAction`) for run/test/build/dev flow
- Candidate picker (`:RunicPick`)
- Explain mode (`:RunicExplain`)
- Last command rerun (`:RunicLast`)
- Cache controls (`:RunicCacheClear`, `:RunicCacheInfo`)
- Toolchain diagnostics (`:RunicHealth`)
- Override hooks (`vim.g.runic_command`, `vim.g.runic_filetype_commands`, `vim.g.runic_resolver`)
- Root detection follows the current file path (works even when current working directory is elsewhere)
- Codeforces mode with dedicated workspace, profile switching, sample testing, and watch mode

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

Codeforces-focused setup example:

```lua
require("runic").setup({
  cf = {
    enabled = true,
    workspace_root = "~/codeforces",
    profile = "contest",
    submit = {
      auto_submit = false,
    },
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

Notes:

- URL auto-open is allowlisted to `localhost`, `127.0.0.1`, and `::1` by default.
- TypeScript single-file execution now prefers `tsx`, then `bun`, `deno`, and `ts-node`.

## Commands

- `:RunicRun` - runs the top-ranked command for the current buffer
- `:RunicAction` - pick intent (`run`, `test`, `build`, `dev`) and run best match
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
- `:RunicStop` - stops the active runic process
- `:RunicRestart` - stops active run and reruns last command

## Codeforces Commands

- `:RunicCFStart <contestId> <problemIndex>` - creates/opens workspace under `~/codeforces`
- `:RunicCFModeOn` / `:RunicCFModeOff` - enable/disable CF-specific runner logic
- `:RunicCFStatus` - shows current CF mode/profile/workspace details
- `:RunicCFProfile <contest|debug>` - switches compile profile
- `:RunicCFImportSamples` - imports `Input/Output` sample blocks from clipboard
- `:RunicCFTest` - compiles and runs all sample tests in `samples/*.in`
- `:RunicCFWatch` / `:RunicCFWatchStop` - auto-run samples on save
- `:RunicCFStress` - runs generator/brute/solution stress loop and saves counterexample
- `:RunicCFReplayFail` - reruns current solution on saved `counterexample.in`
- `:RunicCFCheck` - pre-submit check alias (currently runs sample tests)
- `:RunicCFSubmit` - opens Codeforces problem page for manual submit
- `:RunicCFAutoSubmit` - experimental auto-submit using cookie env (disabled by default)

Auto-submit notes:

- Requires `cf.submit.auto_submit = true` in setup.
- Requires env var from `cf.submit.cookie_env` (default: `RUNIC_CF_COOKIE`) containing valid Codeforces cookie header content.
- If auto-submit fails, runic falls back to manual submit flow.

Stress notes:

- Default stress case count is 1000 (`cf.stress.max_cases`).
- For quick loops while coding, pass a smaller number in setup.
