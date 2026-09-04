# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Nothing yet.

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

[Unreleased]: https://github.com/2hmad/ccswitch/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/2hmad/ccswitch/releases/tag/v0.1.0
