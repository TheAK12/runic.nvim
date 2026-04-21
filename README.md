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
  keymap_mode = "safe", -- "safe" | "force" | "off"
  keymaps = {
    run = "<leader>r",
    pick = "<leader>rp",
    last = "<leader>rl",
    legacy = "<leader>R",
    cf_mode_on = "<leader>cfo",
    cf_mode_off = "<leader>cfO",
    cf_status = "<leader>cfs",
    cf_start = "<leader>cfn",
    cf_profile_contest = "<leader>cfp",
    cf_profile_debug = "<leader>cfP",
    cf_import = "<leader>cfi",
    cf_test = "<leader>cft",
    cf_watch_on = "<leader>cfw",
    cf_watch_off = "<leader>cfW",
    cf_stress = "<leader>cfx",
    cf_replay = "<leader>cfr",
    cf_check = "<leader>cfc",
    cf_submit = "<leader>cfu",
    cf_problem_view = "<leader>cfv",
  },
})
```

Use:

- `:RunicRun` to run the top-ranked candidate
- `:RunicPreview` to inspect why it chose that command

For projects with task runners, use `:RunicTasks`.

## Default keymaps

When `create_keymaps = true`, runic can set these defaults.

Core:

- `<leader>r` run
- `<leader>rp` pick candidate
- `<leader>rl` run last
- `<leader>R` legacy `:RunFile`

Codeforces:

- `<leader>cfo` mode on
- `<leader>cfO` mode off
- `<leader>cfs` status
- `<leader>cfn` start/new problem (prompt)
- `<leader>cfp` contest profile
- `<leader>cfP` debug profile
- `<leader>cfi` import samples
- `<leader>cft` test samples
- `<leader>cfw` watch on
- `<leader>cfW` watch off
- `<leader>cfx` stress
- `<leader>cfr` replay fail
- `<leader>cfc` check
- `<leader>cfu` submit (manual)
- `<leader>cfv` problem pane view toggle

Use `:RunicKeymaps` to see which mappings were applied or skipped.

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
- `:RunicKeymaps` show active and skipped runic mappings
- `:RunicRoot` show resolved root or set a temporary root override
- `:RunicRootReset` clear temporary root override
- `:RunicStatus` show active/last run status
- `:RunicLast` rerun last command
- `:RunicHistory` pick from command history
- `:RunicTasks` pick and run discovered project tasks
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
- `:RunicCFProblemOpen` open problem statement pane on the right
- `:RunicCFProblemRefresh` refetch and rerender statement pane
- `:RunicCFProblemClose` close statement pane
- `:RunicCFProblemToggleView` toggle pane view (`comfortable` / `compact`)

## Codeforces workflow

Recommended flow:

1. `:RunicCFStart 1234 A`
2. Paste samples and run `:RunicCFImportSamples`
3. Run `:RunicCFTest`
4. Enable watch with `:RunicCFWatch` while coding
5. Use `:RunicCFStress` if you have `stress/gen.cpp` and `stress/brute.cpp`
6. Use `:RunicCFSubmit` for manual submit

## Codeforces guide (default keymaps)

This is the same workflow using built-in default CF mappings.

1. Start problem with `<leader>cfn` and enter contest/problem.
2. Confirm mode/status with `<leader>cfo` and `<leader>cfs`.
3. Import samples with `<leader>cfi`.
4. Run sample tests with `<leader>cft`.
5. Turn watch on while coding with `<leader>cfw` (off with `<leader>cfW`).
6. Run stress with `<leader>cfx`; replay fail with `<leader>cfr`.
7. Run final check with `<leader>cfc`.
8. Submit manually with `<leader>cfu`.
9. Toggle problem pane layout with `<leader>cfv`.

Problem pane:

- `RunicCFStart` can open a read-only problem statement pane on the right.
- The pane fetches from Codeforces and caches rendered text in the workspace.
- Use `RunicCFProblemRefresh` to update, and `RunicCFProblemClose` to close.
- Fetch is asynchronous; the pane shows a loading message while content is retrieved.
- Use `RunicCFProblemToggleView` to switch between `comfortable` and `compact` layout.

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

Task discovery supports `package.json` scripts, `justfile`, and `Taskfile.yml`/`Taskfile.yaml`.

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
  keymap_mode = "safe", -- skip mappings that already exist
  root = {
    use_lsp = true,
    resolver = nil,
    strategy = { "custom", "marker", "lsp", "file" },
    markers = { ".git", "package.json", "pyproject.toml", "Cargo.toml", "go.mod" },
  },
  tasks = {
    enabled = true,
    include_in_auto = true,
    base_priority = 7600,
  },
  packs = {
    tasks = true,
    python = true,
    go = true,
    rust = true,
    node = true,
    c_cpp = true,
    scripting = true,
    fallback = true,
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
    problem = {
      auto_open = true,
      pane_width = 72,
      cache = true,
      cache_file = ".runic-problem.md",
      refresh_on_start = false,
      lang = "en",
      proxy_fallback = true,
      proxy_base = "https://r.jina.ai/http://",
      view = "comfortable", -- "comfortable" | "compact"
    },
  },
})
```

If direct Codeforces fetch is blocked by anti-bot challenge, runic uses `proxy_fallback`
to retrieve readable statement text.

## Overrides

You can override command selection with globals:

- `vim.g.runic_command = "<cmd>"`
- `vim.g.runic_filetype_commands = { python = "...", go = "..." }`
- `vim.g.runic_resolver = function(ctx) return { command = "...", priority = 9999 } end`
- `vim.g.runic_python_project_runner = true`
- `vim.g.runic_focus_terminal = true`
- `vim.g.runic_use_snacks_terminal = true`
- `vim.g.runic_open_url = true`

Status hooks:

- `User RunicJobStart`
- `User RunicJobEnd`

Keymap modes:

- `safe` (default): set only unmapped keys; skip conflicts
- `force`: always set runic keymaps
- `off`: do not create runic keymaps

## Troubleshooting

- Run `:RunicPreview` to inspect selection and candidate list.
- Run `:RunicRoot` to inspect root source and override root when needed.
- Run `:RunicCacheClear` after changing project files or config.
- Run `:RunicHealth` if a toolchain command fails.
- If root detection is wrong, configure `root.markers` or `root.resolver`.

### Cookbook

- Monorepo temporary root:
  - `:RunicRoot path/to/package`
  - run commands
  - `:RunicRootReset`
- Task-first project:
  - keep `tasks.include_in_auto = true`
  - use `:RunicTasks` for explicit task picking
- Test-first flow:
  - use `:RunicAction` -> `Test`
  - runic prefers targeted tests for Python/Go/Rust

## Help and license

- Vim help: `:h runic`
- License: MIT
