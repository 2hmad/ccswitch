# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.7.0] - 2026-09-09

### Added

- ccswitch records which machine last captured each account, and says so when
  that is not this one. Two machines cannot share one stored credential:
  refresh tokens rotate, so only the holder of the newest link stays signed in
  and the other gets a forced `/login`. ccswitch cannot prevent this - the
  server decides - but it no longer leaves it as a mystery. `ccswitch list`
  warns, and `ccswitch doctor` names the machine per account and explains why
  sharing a copied credential cannot work.

  The marker travels inside `ccswitch backup`, so restoring a vault onto a
  second machine warns immediately rather than after the first surprise
  logout.

### Note

- Copying a vault to a second machine is a **move**, not a way to use an
  account in two places. To use the same account on two machines, sign in
  separately on each (`ccswitch login <name>`): each sign-in gets its own
  token chain, which is what makes them independent.

## [0.6.2] - 2026-09-08

### Fixed

- A stale credential could destroy a newer stored one. `sync_active` adopted
  the live credential whenever it merely *differed* from the stored copy, with
  no notion of which was newer. Restoring a vault onto a machine that already
  had an old `~/.claude/.credentials.json` therefore overwrote the freshly
  restored tokens with the leftover ones on the very next ccswitch command -
  instantly, once `autosync` is watching. Hit in practice on a WSL install:
  a vault moved across was clobbered by a credential 103 days old.

  Sync now adopts a live credential only when its access-token expiry is at
  least as late as the stored one. Rotation always moves that expiry forward,
  so an earlier expiry identifies the live file as the stale side. A live
  credential with no expiry at all is refused rather than trusted.

  This is the mirror of the bug 0.4.0 fixed: that one lost rotations, this one
  overwrote good tokens with old ones.

## [0.6.1] - 2026-09-08

### Added

- A "Moving to another machine" guide, covering the part that is not a file
  copy: refresh tokens rotate, so an account cannot be live on two machines at
  once - whichever renews first invalidates the other. It also covers syncing
  before taking the backup, moving the shared `~/.claude` config separately,
  and the WSL caveats.

### Fixed

- `ccswitch autosync install` gave a confusing systemd error on WSL, which
  ships `systemctl` but does not run systemd as init unless enabled. It now
  detects that and prints the `/etc/wsl.conf` fix, or points at `ccswitch sync`
  where systemd is genuinely unavailable.

## [0.6.0] - 2026-09-08

### Added

- `ccswitch autosync install` puts a systemd path unit on the credential file,
  so every token rotation reaches the vault as it is written. Until now the
  vault only caught up when a ccswitch command happened to run, which left a
  window in which a rotation could be lost - and losing a rotation is the only
  thing that actually costs a browser re-login. `uninstall` and `status` do
  what they say. Not available with the macOS keychain backend, which has no
  file to watch.

- `ccswitch sync` captures the live credential into the account it belongs to.

### Changed

- `ccswitch sync` and the automatic sync now route the live credential to the
  stored account whose email matches it, and follow it, rather than writing
  into whatever slot is marked active. Signing in with `/login` inside Claude
  Code changes the live account without telling ccswitch; the rotation that
  follows belongs to that account. A credential matching no stored account is
  still refused rather than guessed at.

- `ccswitch list` reports `ready` instead of the access token's remaining life.
  The access token expires roughly every 8 hours by design and Claude Code
  renews it on use, so showing `expired 9h ago` as an account's headline status
  made a routine non-event look like a broken account. `ccswitch doctor` still
  shows it.

## [0.5.1] - 2026-09-08

### Fixed

- Being signed out trapped you on the dead account. `capture_into` refuses a
  cleared credential by design, but `save_active` let that refusal abort the
  whole switch, so `ccswitch use <other>` died with "the live credential has
  been cleared - refusing to overwrite '<current>'". Switching away is exactly
  what you need when a session dies. It now warns, leaves the slot at its last
  saved state, and carries on with the switch. Regression from 0.4.0.

- `identity_matches` compared `userID` as well as the account email, but
  `userID` in `.claude.json` is not the account identifier: the same value has
  been observed against two different accounts, and it changes across logins.
  Any such change produced a false mismatch, which silently disabled the sync
  that keeps the vault from holding a consumed refresh token - quietly
  reopening the daily re-login bug 0.4.0 set out to close. Matching is now on
  the email alone, and a genuinely different account is still refused.

## [0.5.0] - 2026-09-06

### Added

- `ccswitch update` updates ccswitch in place from the latest GitHub release,
  and `ccswitch update --check` only reports. It detects how the copy was
  installed and defers to npm or Homebrew rather than overwriting a
  package-managed file. The download must start with a bash shebang, declare
  the expected version, exceed 4KB and pass `bash -n` before it is installed,
  and it is swapped in by rename - overwriting in place would corrupt the
  running script, which bash reads incrementally.

- `ccswitch list` notes when a newer version is available. The check itself
  runs during the scheduled `refresh`, so `list` reads a cache and never makes
  a network call. `CCSWITCH_NO_UPDATE_NOTICE=1` silences it.

- An npm package, `@2hmad/ccswitch`, so installing and updating no longer means
  piping curl to bash. Scoped because the unscoped `ccswitch` name is taken by
  an unrelated project; the installed command is still `ccswitch`. Marked
  `os: [darwin, linux]`, and Node is only a delivery mechanism - nothing at
  runtime uses it.

  CI publishes on tag when an `NPM_TOKEN` secret exists, and skips with a
  warning when it does not. A lint step keeps `package.json` and the `VERSION`
  in `bin/ccswitch` from drifting apart.

## [0.4.2] - 2026-09-06

### Fixed

- `ccswitch save` wrote the live credential into the active account without
  checking it belonged there. Signing in with `/login` inside Claude Code
  changes the live account while ccswitch still points at the previous one, so
  a save in that state silently overwrote a healthy slot with another account's
  credential - destroying it. It now refuses, and names the account the
  credential actually belongs to.

### Added

- `ccswitch save <name>` stores the live credential into a named account. This
  is the missing step after a `/login` done inside Claude Code: previously the
  only way to adopt that credential was `ccswitch rm <name>` followed by
  `ccswitch add <name>`.

## [0.4.1] - 2026-09-06

### Fixed

- `ccswitch use` and `ccswitch login` refused to run with "a claude process is
  running" even after every Claude Code session was closed. Several long-lived
  helpers share the `claude` binary and process name - above all the
  Claude-in-Chrome native messaging host, which Chrome keeps alive for as long
  as the browser is open - and both `pgrep -x claude` and `pgrep -f <binary>`
  matched them. With Chrome open, ccswitch was blocked indefinitely and the only
  way through was `--force`, which `login` does not accept at all.

  Candidates are now filtered by command line, so the Chrome host, a stdio
  `mcp serve`, and ccswitch's own process no longer count as sessions.

- `ccswitch doctor` lists the session PIDs it detects, so a false positive is
  visible rather than guesswork.

## [0.4.0] - 2026-09-06

### Fixed

- Accounts demanding a fresh browser `/login` roughly daily. Refresh tokens
  rotate - each renewal consumes the old one - so any snapshot taken before a
  rotation is worthless afterwards. Restoring one made the server answer
  `invalid_grant`, at which point Claude Code marks the token dead and blanks
  the credential on disk. Four changes:

  - `capture_into` refuses to snapshot a cleared credential. Storing one
    overwrote a good slot with empty tokens, turning a single re-login into a
    permanently broken account that `ccswitch list` reported only as `unknown`.
  - Every ccswitch run now syncs the live credential into the active account's
    slot, not just `use`. Claude Code rotates mid-session and on `/login`,
    neither of which went through ccswitch, so the vault kept a consumed token.
    Guarded by an identity check so a `/login` as a different account cannot
    write into the wrong slot.
  - `refresh` decides from `refreshTokenExpiresAt` rather than the 8h access
    token, and only acts within `CCSWITCH_REFRESH_WINDOW_DAYS` (default 7) of
    expiry - each renewal is itself a rotation, so refreshing early was risk
    without benefit. It now captures the result even when `claude` exits
    non-zero, since a rotation can land before an unrelated failure, and reports
    a signed-out account instead of trying to renew it.
  - `refresh` finally has the `INT`/`TERM`/`EXIT` trap the 0.2.0 notes claimed:
    it was never implemented, so an interrupted run left you signed in as
    whichever account the loop was holding.

- `ccswitch list` gained a `RELOGIN` column (real refresh-token life) and
  reports a cleared slot as `BROKEN - re-login` instead of `unknown`.

### Changed

- The scheduling docs lead with the systemd user timer and demote cron. A
  4am cron job never fires on a machine that is powered off overnight, and
  cron neither runs it late nor says anything - the run is simply lost.

## [0.3.0] - 2026-09-04

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
  not Keychain semantics. It has not yet been run against a real Keychain,
  so treat macOS as experimental until someone confirms it on hardware.

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
