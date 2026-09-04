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

Claude Code stores one signed-in account at a time. The usual workaround is to give each account its own `CLAUDE_CONFIG_DIR`, but that isolates *everything* — your MCP servers, plugins, skills, agents, slash commands, session history and `CLAUDE.md` all get duplicated per account, and each copy drifts.

ccswitch takes the opposite approach. One `~/.claude`, shared by every account. Only the credential and the identity it belongs to are swapped.

| | Separate `CLAUDE_CONFIG_DIR` | ccswitch |
|---|---|---|
| MCP servers | duplicated per account | shared |
| Plugins & marketplaces | duplicated per account | shared |
| Skills, agents, commands | duplicated per account | shared |
| Session history | duplicated per account | shared |
| `settings.json`, `CLAUDE.md` | duplicated per account | shared |
| Accounts active at once | many | one |

That last row is the trade-off. If you need two accounts running *simultaneously* in different terminals, use `CLAUDE_CONFIG_DIR` instead — ccswitch changes which account `claude` runs as, globally.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/2hmad/ccswitch/main/install.sh | bash
```

Or manually:

```bash
git clone https://github.com/2hmad/ccswitch
cd ccswitch && ./install.sh
```

Requires `bash`, `python3`, and Claude Code. Linux is supported today; see [Platform support](#platform-support).

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

| Command | Description |
|---|---|
| `ccswitch <name>` | Switch to an account |
| `ccswitch use <name> [--force]` | Same, explicit form |
| `ccswitch login <name>` | Sign a new account in and store it |
| `ccswitch add <name>` | Store the account you're already signed in as |
| `ccswitch list` | Accounts, emails, token status |
| `ccswitch current` | Print the active account name |
| `ccswitch save` | Write the live token back to the active slot |
| `ccswitch rm <name>` | Forget an account |
| `ccswitch rename <old> <new>` | Rename an account |
| `ccswitch backup [file]` | Archive the vault |
| `ccswitch restore <file>` | Restore a vault archive |
| `ccswitch doctor` | Diagnose the setup |
| `ccswitch completion bash\|zsh` | Print a completion script |

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

**Tokens still expire.** ccswitch does not extend token lifetime; it only saves you from re-authenticating the accounts you aren't currently using. `ccswitch list` shows how long each has left, and `ccswitch login <name>` refreshes one in place.

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

| Platform | Status |
|---|---|
| Linux | Supported |
| macOS | Not yet — Claude Code stores credentials in the Keychain rather than a file. A keychain backend would be a welcome contribution. |
| Windows / WSL | WSL behaves like Linux and should work; untested |

## Contributing

Issues and pull requests welcome. Please run `shellcheck bin/ccswitch` before submitting; CI runs it on every push.

## License

MIT — see [LICENSE](LICENSE).
