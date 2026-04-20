# Changelog

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
