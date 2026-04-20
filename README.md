# runic.nvim

`runic.nvim` is a Neovim runner that chooses a command based on the current file and project context.

Module name: `runic`

## What it does

- Resolves both project-level and single-file commands.
- Ranks candidates and runs the highest-priority match.
- Lets you inspect or override the decision when needed.
- Supports a dedicated Codeforces workflow for C++ practice.

## Installation

### vim.pack

```lua
vim.pack.add({
  { src = "https://github.com/TheAK12/runic.nvim" },
})

vim.cmd.packadd("runic.nvim")
require("runic").setup({})
```

### lazy.nvim

```lua
{
  "TheAK12/runic.nvim",
  main = "runic",
  opts = {},
}
```

## Quick start

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

Use:

- `:RunicRun` to run the top-ranked candidate
- `:RunicPreview` to inspect why it chose that command

## How command selection works

`runic` uses a ranked rule list:

1. Build context from current buffer.
2. Detect root from markers near the file, then LSP root, then file directory.
3. Generate candidates from:
   - overrides
   - project rules (`Cargo.toml`, `go.mod`, `package.json`, etc.)
   - file rules (`python file.py`, `rustc file.rs`, `g++ file.cpp`, etc.)
4. Sort by priority and run the top candidate.

If you want to force behavior:

- `:RunicRunProject` for project-only resolution
- `:RunicRunFile` for file-only resolution

## Commands

### Core

- `:RunicRun` run top-ranked command
- `:RunicAction` choose intent (`run`, `test`, `build`, `dev`) and execute
- `:RunicPick` choose from ranked candidates
- `:RunicRunFile` force file-mode
- `:RunicRunProject` force project-mode
- `:RunicPreview` show selection details
- `:RunicExplain` alias of `RunicPreview`
- `:RunicLast` rerun last command
- `:RunicHistory` pick from command history
- `:RunicCacheClear` clear resolver cache
- `:RunicCacheInfo` show cache stats
- `:RunicHealth` check common toolchain executables
- `:RunicReload` reapply setup without restart
- `:RunicStop` stop active process
- `:RunicRestart` restart last command

### Codeforces

- `:RunicCFStart <contestId> <problemIndex>` create/open workspace
- `:RunicCFModeOn` / `:RunicCFModeOff` toggle CF mode
- `:RunicCFStatus` show CF status
- `:RunicCFProfile <contest|debug>` switch compile profile
- `:RunicCFImportSamples` import samples from clipboard
- `:RunicCFTest` run sample tests
- `:RunicCFWatch` / `:RunicCFWatchStop` test on save
- `:RunicCFStress` run stress test (gen vs brute vs solution)
- `:RunicCFReplayFail` rerun on saved counterexample
- `:RunicCFCheck` run pre-submit checks
- `:RunicCFSubmit` open manual submit page

## Codeforces workflow

Recommended flow:

1. `:RunicCFStart 1234 A`
2. Paste samples and run `:RunicCFImportSamples`
3. Run `:RunicCFTest`
4. Enable watch with `:RunicCFWatch` while coding
5. Use `:RunicCFStress` if you have `stress/gen.cpp` and `stress/brute.cpp`
6. Use `:RunicCFSubmit` for manual submit

Workspace layout:

```text
~/codeforces/<contest>/<problem>/
  main.cpp
  notes.md
  samples/
  stress/gen.cpp
  stress/brute.cpp
  .runic-cf.json
  .runic-bin/
```

Notes:

- `watch/test/stress/submit` operate on configured solution file (`main.cpp` by default).
- `cf.chdir_on_start` controls cwd switch only when `:RunicCFStart` runs.

## Configuration

### Common options

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
  root = {
    use_lsp = true,
    resolver = nil,
    markers = { ".git", "package.json", "pyproject.toml", "Cargo.toml", "go.mod" },
  },
  terminal = {
    use_snacks = false,
    focus = true,
    height = 12,
    close_keys = { "<Esc>", "q" },
    open_url = true,
    url_allowlist = { "localhost", "127.0.0.1", "::1" },
  },
})
```

### Codeforces options

```lua
require("runic").setup({
  cf = {
    enabled = true,
    workspace_root = "~/codeforces",
    chdir_on_start = "tab", -- "tab" | "window" | "global" | false
    profile = "contest",
    sample = {
      auto_watch = false,
      dir = "samples",
      timeout_ms = 3000,
    },
    stress = {
      timeout_ms = 2000,
      max_cases = 500,
      save_counterexample = true,
    },
    check = {
      run_stress = false,
      stress_cases = 200,
    },
  },
})
```

## Overrides

You can override command selection with globals:

- `vim.g.runic_command = "<cmd>"`
- `vim.g.runic_filetype_commands = { python = "...", go = "..." }`
- `vim.g.runic_resolver = function(ctx) return { command = "...", priority = 9999 } end`
- `vim.g.runic_python_project_runner = true`
- `vim.g.runic_focus_terminal = true`
- `vim.g.runic_use_snacks_terminal = true`
- `vim.g.runic_open_url = true`

## Troubleshooting

- Run `:RunicPreview` to inspect selection and candidate list.
- Run `:RunicCacheClear` after changing project files or config.
- Run `:RunicHealth` if a toolchain command fails.
- If root detection is wrong, configure `root.markers` or `root.resolver`.

## Help and license

- Vim help: `:h runic`
- License: MIT
