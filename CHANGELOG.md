# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- macOS support. Claude Code stores the OAuth credential in the login keychain
  there rather than in `~/.claude/.credentials.json`, so ccswitch now reads and
  writes it with `security(1)`, deriving the same item Claude Code does:
  service `Claude Code-credentials` (suffixed with the first 8 hex digits of
  the SHA-256 of the config dir when `CLAUDE_CONFIG_DIR` is set), account
  `$USER` falling back to `claude-code-user`. All credential access moved
  behind a small backend layer, so the file and keychain paths share one code
  path above it. `CCSWITCH_BACKEND=file|keychain` forces the choice, and
  `ccswitch doctor` reports which store is in use.

  The keychain backend is covered by `test/keychain.sh`, which runs on any
  platform against a `security(1)` stand-in. That verifies ccswitch's side of
  the contract - item naming, flags, and that no credentials file is written -
  not Keychain semantics, so it wants a real run on a Mac before release.

### Fixed

- The test scripts pinned their vault with `HOME` alone, but `VAULT` falls back
  to `$XDG_CONFIG_HOME`, which escapes it. On a machine with that variable set,
  `test/smoke.sh` ran its `rm`, `rename` and `restore` cases against the real
  vault instead of a throwaway one. Both scripts now set `CCSWITCH_HOME`.

### Changed

- README documents how to schedule `ccswitch refresh --all`, with worked
  cron and systemd user timer examples and the two things that bite in
  practice: cron's bare `PATH` hiding the `claude` binary, and `refresh`
  refusing to run while a `claude` process is alive.

## [0.2.0] - 2026-09-04

### Added

- `ccswitch refresh [name|--all] [--force]` refreshes a stored account's OAuth
  tokens in place, without a browser re-login. Skips accounts whose access
  token is still valid (their refresh token isn't at risk), so routine use
  (e.g. a daily cron) makes real API calls only for accounts that actually
  need it. Meant to keep parked accounts' longer-lived refresh tokens from
  lapsing from disuse.

### Fixed

- An interrupted `refresh` no longer strands you signed in as whichever account
  the loop was holding. The live credential is restored from a trap on `INT`,
  `TERM` and `EXIT`, and the temporary stash directory is always removed.
- `ccswitch refresh --force` with no account name is now read as "all accounts,
  forced" instead of failing with `no such account '--force'`.
- `refresh` reports success only when the token's expiry actually advanced.
  Previously a call that exited cleanly without renewing anything printed a
  success line beside an expired timestamp.

### Changed

- CI runs shellcheck at `-S style` via `ludeeus/action-shellcheck` rather than
  the distribution package, and on `v*` tags verifies that `VERSION` in
  `bin/ccswitch` matches the tag and that this file has a matching section.

## [0.1.0] - 2026-09-04

First release.

### Added

- `ccswitch <name>` switches the signed-in Claude Code account in place. MCP
  servers, plugins, skills, agents, slash commands, settings, `CLAUDE.md` and
  session history stay in a single shared `~/.claude`.
- `ccswitch login <name>` signs a new account in and stores it; `ccswitch add
<name>` captures an account you are already signed in as.
- `ccswitch list` shows each stored account with its email and remaining token
  life; `ccswitch current` prints the active name.
- `ccswitch rm`, `ccswitch rename`, `ccswitch save`, `ccswitch backup` and
  `ccswitch restore` for managing the vault.
- `ccswitch doctor` reports the resolved config paths, the live credential, the
  active account, and warns when `CLAUDE_CONFIG_DIR` is set.
- `ccswitch completion bash|zsh` emits a completion script that reads account
  names from the vault at runtime.
- Installer (`install.sh`) supporting both a local checkout and `curl | bash`,
  with `PREFIX`, `CCSWITCH_REPO` and `CCSWITCH_REF` overrides.
- Smoke test suite (`test/smoke.sh`, 21 checks) running against a throwaway
  `HOME`, plus a CI workflow running shellcheck and the suite.

### Notes on behaviour

- Only `.credentials.json` and the `oauthAccount` / `userID` keys of
  `.claude.json` are swapped. Every other key in that file — `mcpServers`,
  per-project trust decisions, onboarding state — is left untouched, which is
  what keeps configuration shared across accounts.
- The live credential is written back to the outgoing account before a switch,
  so a token refreshed mid-session is not lost.
- `ccswitch use` refuses to run while a `claude` process is detected; pass
  `--force` to override.

### Known limitations

- One account is active at a time. This is inherent to sharing one config
  directory; use `CLAUDE_CONFIG_DIR` if you need accounts running in parallel.
- Linux only. macOS stores Claude Code credentials in the Keychain rather than
  a file, and ccswitch refuses to run there rather than doing the wrong thing.
- Token lifetime is unchanged. ccswitch saves you from re-authenticating the
  accounts you are not currently using; it does not extend how long any token
  lasts.

[Unreleased]: https://github.com/2hmad/ccswitch/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/2hmad/ccswitch/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/2hmad/ccswitch/releases/tag/v0.1.0
