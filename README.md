# ccswitch

Switch between multiple Claude Code accounts with one command — without re-running `/login` every time, and without splitting your setup into isolated copies.

```console
$ ccswitch list
  ACCOUNT      EMAIL                          TOKEN
* work         you@example.com                valid 8h 12m
  personal     you@example.net                valid 6h 40m
  client       you@example.org                expired 3h ago

$ ccswitch personal
switched to personal  (you@example.net)  valid 6h 40m

$ claude          # runs as personal
```

## Why

Claude Code stores one signed-in account at a time. The usual workaround is to give each account its own `CLAUDE_CONFIG_DIR`, but that isolates _everything_ — your MCP servers, plugins, skills, agents, slash commands, session history and `CLAUDE.md` all get duplicated per account, and each copy drifts.

ccswitch takes the opposite approach. One `~/.claude`, shared by every account. Only the credential and the identity it belongs to are swapped.

|                              | Separate `CLAUDE_CONFIG_DIR` | ccswitch |
| ---------------------------- | ---------------------------- | -------- |
| MCP servers                  | duplicated per account       | shared   |
| Plugins & marketplaces       | duplicated per account       | shared   |
| Skills, agents, commands     | duplicated per account       | shared   |
| Session history              | duplicated per account       | shared   |
| `settings.json`, `CLAUDE.md` | duplicated per account       | shared   |
| Accounts active at once      | many                         | one      |

That last row is the trade-off. If you need two accounts running _simultaneously_ in different terminals, use `CLAUDE_CONFIG_DIR` instead — ccswitch changes which account `claude` runs as, globally.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/2hmad/ccswitch/main/install.sh | bash
```

Or manually:

```bash
git clone https://github.com/2hmad/ccswitch
cd ccswitch && ./install.sh
```

Requires `bash`, `python3`, and Claude Code. Works on Linux and macOS; see [Platform support](#platform-support).

## Usage

Sign each account in once:

```bash
ccswitch login work        # opens Claude Code; run /login, then /exit
ccswitch login personal
ccswitch login client
```

Already signed in as one of them? Capture it without a fresh login:

```bash
ccswitch add work
```

Then switch whenever you like:

```bash
ccswitch personal         # shorthand
ccswitch use personal     # same thing
claude                    # runs as personal
```

### All commands

| Command                          | Description                                   |
| -------------------------------- | --------------------------------------------- |
| `ccswitch <name>`                | Switch to an account                          |
| `ccswitch use <name> [--force]`  | Same, explicit form                           |
| `ccswitch login <name>`          | Sign a new account in and store it            |
| `ccswitch add <name>`            | Store the account you're already signed in as |
| `ccswitch list`                  | Accounts, emails, token status                |
| `ccswitch current`               | Print the active account name                 |
| `ccswitch save`                  | Write the live token back to the active slot  |
| `ccswitch refresh [name\|--all]` | Refresh a stored token before it goes stale   |
| `ccswitch rm <name>`             | Forget an account                             |
| `ccswitch rename <old> <new>`    | Rename an account                             |
| `ccswitch backup [file]`         | Archive the vault                             |
| `ccswitch restore <file>`        | Restore a vault archive                       |
| `ccswitch doctor`                | Diagnose the setup                            |
| `ccswitch completion bash\|zsh`  | Print a completion script                     |

### Keeping parked accounts alive

An account you haven't switched to in a few weeks can lose its refresh token, which forces a full `ccswitch login <name>` with a browser round-trip. `ccswitch refresh --all` prevents that: it restores each stored account in turn, makes one tiny API call to exercise its token, saves the renewed credential back, and returns you to the account you started on.

Run it by hand whenever it occurs to you:

```bash
ccswitch refresh --all
```

Or schedule it daily. Accounts whose access token is still valid are skipped without any API call, so a typical run does nothing at all:

```console
$ ccswitch refresh --all
skip    work  (you@example.com)  valid 6h 2m - not due yet
refreshed personal  (you@example.net)  valid 8h 0m
```

#### cron

`crontab -e`, then:

```cron
PATH=/home/you/.local/bin:/usr/local/bin:/usr/bin:/bin

30 4 * * * ccswitch refresh --all >> "$HOME/.cache/ccswitch-refresh.log" 2>&1
```

Two things that trip people up:

- **Set `PATH`.** cron runs with a bare `/usr/bin:/bin`, and `refresh` needs both `ccswitch` and the `claude` binary. Run `command -v claude` and put that directory first — it's usually `~/.local/bin`. Without this the job dies with `the 'claude' command was not found on PATH`.
- **Pick an hour you're not working.** `refresh` refuses to run while a `claude` process is alive, so a job that fires mid-session just logs an error and does nothing. (A run where every account is skipped doesn't check this, so it stays quiet either way.)

#### systemd user timer

Better on a laptop, because `Persistent=true` catches up on a run that was missed while the machine was asleep — cron simply skips it.

`~/.config/systemd/user/ccswitch-refresh.service`:

```ini
[Unit]
Description=Refresh parked ccswitch account tokens

[Service]
Type=oneshot
Environment=PATH=%h/.local/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=%h/.local/bin/ccswitch refresh --all
```

`~/.config/systemd/user/ccswitch-refresh.timer`:

```ini
[Unit]
Description=Daily ccswitch token refresh

[Timer]
OnCalendar=*-*-* 04:30:00
Persistent=true

[Install]
WantedBy=timers.target
```

Enable it:

```bash
systemctl --user daemon-reload
systemctl --user enable --now ccswitch-refresh.timer

systemctl --user list-timers ccswitch-refresh.timer   # when it next fires
journalctl --user -u ccswitch-refresh.service         # what happened last time
```

If you want it to run while you're logged out, also `sudo loginctl enable-linger $USER`.

## How it works

Claude Code keeps two pieces of account state:

- `~/.claude/.credentials.json` — the OAuth access and refresh tokens
- `~/.claude.json` — a mixed file holding your sign-in identity **and** your MCP servers, per-project trust decisions, and other config

ccswitch stores per account, under `~/.config/ccswitch/accounts/<name>/`:

```
credentials.json   copy of .credentials.json
identity.json      only the oauthAccount and userID keys from .claude.json
```

Switching writes those two back into place and leaves every other key in `~/.claude.json` untouched — which is why `mcpServers`, `projects` and the rest stay shared.

Before switching away, ccswitch saves the live credential back into the account you're leaving. Claude Code refreshes tokens during a session, so without this you'd restore a stale token the next time around.

## Notes and caveats

**One account is active at a time.** This is by design — it's the price of sharing everything. `ccswitch use` refuses to run while a `claude` process is detected; pass `--force` to override.

**The vault holds live session tokens.** `~/.config/ccswitch` is created mode 700 and files mode 600. `ccswitch backup` produces an archive containing those tokens — encrypt it if you keep it anywhere but your own disk.

**Tokens still expire.** The access token (~8h) refreshes itself automatically whenever the _active_ account is used — Claude Code does this on its own. Accounts sitting parked in the vault aren't touched by anything, though, so their refresh token (~28 days) can eventually lapse, forcing a full `ccswitch login <name>` re-authentication. Run `ccswitch refresh --all` occasionally, or schedule it — see [Keeping parked accounts alive](#keeping-parked-accounts-alive). It only makes a real (tiny, tool-free) API call — and only for accounts whose access token has actually expired, since a still-valid one means the refresh token isn't at risk yet — so it won't burn much of an account's session quota. `ccswitch list` shows how long each account's access token has left.

**`CLAUDE_CONFIG_DIR` takes priority.** If it's set, ccswitch operates on that directory instead of `~/.claude`. `ccswitch doctor` will warn you. If you're migrating from per-account config dirs, unset it first.

**Project config is unaffected.** `.mcp.json`, `.claude/settings.json` and `CLAUDE.md` inside a repo load from the repo regardless of which account is active.

## Migrating from per-account `CLAUDE_CONFIG_DIR`

If you already have isolated config dirs, pick the one with the setup you want to keep, make it your `~/.claude`, then capture each account's credential:

```bash
unset CLAUDE_CONFIG_DIR                    # and remove it from ~/.zshrc

# keep the best-configured directory as the shared one
mv ~/.claude ~/.claude.old
cp -r ~/.claude-accounts/work ~/.claude
cp ~/.claude-accounts/work/.claude.json ~/.claude.json

ccswitch add work                          # captures what's now live

# for each remaining account, drop its credential in and capture it
cp ~/.claude-accounts/personal/.credentials.json ~/.claude/.credentials.json
python3 - <<'EOF'
import json, os
h = os.path.expanduser("~")
src = json.load(open(f"{h}/.claude-accounts/personal/.claude.json"))
dst = json.load(open(f"{h}/.claude.json"))
for k in ("oauthAccount", "userID"):
    dst[k] = src.get(k)
json.dump(dst, open(f"{h}/.claude.json", "w"), indent=2)
EOF
ccswitch add personal
```

Then `ccswitch list` to confirm all of them are there.

## Platform support

| Platform      | Status                                           |
| ------------- | ------------------------------------------------ |
| Linux         | Supported                                        |
| macOS         | Supported via the login keychain — see below     |
| Windows / WSL | WSL behaves like Linux and should work; untested |

On macOS, Claude Code keeps the OAuth credential in your login keychain rather than in `~/.claude/.credentials.json`, so ccswitch reads and writes it there with `security(1)`. It derives the same item Claude Code does:

|         | Value                                                                                         |
| ------- | --------------------------------------------------------------------------------------------- |
| Service | `Claude Code-credentials`, plus `-<sha256(config dir)[:8]>` when `CLAUDE_CONFIG_DIR` is set   |
| Account | `$USER`, or `claude-code-user` if that is unset or contains anything outside `[a-zA-Z0-9._-]` |

`ccswitch doctor` prints what it resolved to. The first switch may raise a keychain prompt — macOS asks before letting a new binary read an item it did not create. Choose **Always Allow** if you would rather not be asked again.

The keychain is used only when there is no `~/.claude/.credentials.json`; a file left by an older Claude Code still wins. Force it either way with `CCSWITCH_BACKEND=keychain` or `CCSWITCH_BACKEND=file`.

## Contributing

Issues and pull requests welcome. Please run `shellcheck bin/ccswitch` before submitting; CI runs it on every push.

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## License

MIT — see [LICENSE](LICENSE).
