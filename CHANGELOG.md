# Changelog

## Unreleased (feat/runic-cf-mode)

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
- add experimental auto-submit path with cookie-based session fallback to manual submit
- make CF watch non-blocking by running sample tests asynchronously with debounced pending rerun
- make CF stress loop non-blocking by chunking cases across scheduler ticks
- reduce default CF stress max cases from 10000 to 1000 for better out-of-box responsiveness

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
