# Changelog

## Unreleased (feat/runic-cf-mode)

- add root controls via `:RunicRoot` and `:RunicRootReset` with configurable `root.strategy`
- add `:RunicStatus` and `User RunicJobStart`/`User RunicJobEnd` run lifecycle events
- add `:RunicTasks` and task candidate discovery from `package.json`, `justfile`, and `Taskfile`
- add rule packs (`packs.*`) to enable/disable groups of resolver rules
- improve test intent with targeted Python/Go/Rust test candidates
- enable Python project runner by default and expand Python project marker detection
- add support for more project/file types including Deno, Zig, Laravel, Haskell, Clojure, Scala, F#, and more shell/script extensions
- add Codeforces problem statement pane (`RunicCFProblemOpen/Refresh/Close`) with auto-open on `RunicCFStart` and workspace cache fallback
- add anti-bot handling for CF problem pane by detecting challenge pages and using optional proxy fallback
- make CF problem pane fetch asynchronous to avoid UI stalls during start/refresh
- harden CF problem pane fallback path to avoid hard parser failures and show helpful fallback content when fetch fails
- add CF problem pane view toggle (`RunicCFProblemToggleView`) with comfortable/compact rendering modes
- add first complete Codeforces workflow:
  - workspace bootstrap via `RunicCFStart`
  - contest/debug profile switching via `RunicCFProfile`
  - clipboard sample import via `RunicCFImportSamples`
  - sample execution via `RunicCFTest`
  - watch-on-save mode via `RunicCFWatch`
  - pre-submit and manual submit helpers (`RunicCFCheck`, `RunicCFSubmit`)
- add CF-specific C++ runner priority when in a runic CF workspace
- add built-in CP C++ template generation for new CF problems
- add stress-testing workflow (`RunicCFStress`, `RunicCFReplayFail`) with counterexample persistence
- make CF watch non-blocking by running sample tests asynchronously with debounced pending rerun
- make CF stress loop non-blocking by chunking cases across scheduler ticks
- reduce default CF stress max cases from 10000 to 1000 for better out-of-box responsiveness
- make `RunicAction` bypass cache for CF intents to avoid stale command selection
- reduce default CF stress max cases from 1000 to 500 for faster feedback loops
- make CF watch/test/stress/submit consistently use the configured solution file (default: main.cpp)
- add `cf.chdir_on_start` so `RunicCFStart` can switch cwd to the new problem workspace

## v0.2.2

- add `:RunicAction` intent picker (`run`, `test`, `build`, `dev`) with per-project preference memory
- add process controls: `:RunicStop` and `:RunicRestart`
- improve TypeScript single-file runner preference order (`tsx` -> `bun` -> `deno` -> `ts-node`)
- improve Java single-file execution for package-declared classes
- add URL auto-open host allowlist (defaults to localhost loopback hosts)
- keep setup reconfigure behavior and expose reload via `:RunicReload`

## v0.2.1

- improve test-file intent for project runners (Go and Rust now prefer test commands on test files)
- improve URL auto-open handling with buffered parsing and better localhost:port detection
- add browser opener fallbacks with clear notifications when opening fails
- add setup reconfigure flow and `:RunicReload` for in-session option reloads
- keep terminal focused by default to support interactive program input
- root detection now prioritizes project markers near the current file path, not the editor cwd
