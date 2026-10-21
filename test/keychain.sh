#!/usr/bin/env bash
# Exercises the macOS keychain backend on any platform, using the security(1)
# stand-in in test/fixtures. That stub is not the real Keychain, so this proves
# ccswitch's side of the contract - the item name it derives, the flags it
# passes, that it never falls back to writing a credentials file - and not
# Keychain semantics themselves.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP"
mkdir -p "$TMP/bin"
printf '#!/usr/bin/env bash\nprintf "Darwin\\n"\n' > "$TMP/bin/uname"
chmod +x "$TMP/bin/uname"
export PATH="$TMP/bin:$ROOT/test/fixtures:$ROOT/bin:$PATH"
export NO_COLOR=1
# Pin the vault inside TMP. VAULT falls back to $XDG_CONFIG_HOME, which
# escapes $HOME - without this the test would operate on a real vault.
export CCSWITCH_HOME="$TMP/vault"
unset XDG_CONFIG_HOME
unset CCSWITCH_BACKEND
export FAKE_KEYCHAIN="$TMP/keychain"
export USER=testuser
unset CLAUDE_CONFIG_DIR
unset CLAUDE_SECURESTORAGE_CONFIG_DIR

pass=0; fail=0
ok()   { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  FAIL %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want '$3', got '$2')"; fi; }

kc_get() { security find-generic-password -a "$USER" -s "$1" -w 2>/dev/null || echo MISSING; }

seed_login() {  # $1=uid $2=email $3=token
  mkdir -p "$HOME/.claude"
  python3 - "$1" "$2" "$3" <<'PY'
import json, os, sys, time
import hashlib
# Each real login ends on its own date, and ccswitch tells logins apart by it.
def login_end(email):
    spread = int(hashlib.sha256(email.encode()).hexdigest()[:8], 16) % 43200 + 600
    return int((time.time() + 28 * 86400 + spread) * 1000)
uid, email, tok = sys.argv[1], sys.argv[2], sys.argv[3]
h = os.environ["HOME"]
p = h + "/.claude.json"
d = json.load(open(p)) if os.path.exists(p) else {}
d["userID"] = uid
d["oauthAccount"] = {"emailAddress": email}
json.dump(d, open(p, "w"), indent=2)
cred = json.dumps({"claudeAiOauth": {"accessToken": tok, "refreshToken": "r-" + tok,
                                     "scopes": ["user:inference", "user:profile"],
                                     "expiresAt": int((time.time() + 9 * 3600) * 1000),
                                     "refreshTokenExpiresAt": login_end(email)}})
os.system('security add-generic-password -U -a "$USER" -s "Claude Code-credentials" -X '
          + cred.encode().hex())
PY
}

tok() { kc_get "Claude Code-credentials" | python3 -c 'import json,sys;print(json.load(sys.stdin)["claudeAiOauth"]["accessToken"])' 2>/dev/null || echo MISSING; }
j() { python3 -c "import json,os,sys;print(json.load(open(os.environ['HOME']+sys.argv[1]))$2)" "$1" 2>/dev/null || echo MISSING; }

echo "ccswitch keychain backend test"

# the item name must match what Claude Code derives, or we read nothing
check "service name (default)" \
  "$(ccswitch doctor 2>/dev/null | sed -n 's/.*service \(Claude Code[^,]*\).*/\1/p')" \
  "Claude Code-credentials"
check "service name (CLAUDE_CONFIG_DIR)" \
  "$(CLAUDE_CONFIG_DIR=/tmp/cfg ccswitch doctor 2>/dev/null | sed -n 's/.*service \(Claude Code[^,]*\).*/\1/p')" \
  "Claude Code-credentials-$(python3 -c 'import hashlib;print(hashlib.sha256(b"/tmp/cfg").hexdigest()[:8])')"
check "account falls back when \$USER is unportable" \
  "$(USER='bad user!' ccswitch doctor 2>/dev/null | sed -n 's/.*account \([^)]*\)).*/\1/p')" \
  "claude-code-user"

seed_login UID-A a@example.com TOK-A
ccswitch add alpha >/dev/null
check "add reads from the keychain" "$(ccswitch current)" "alpha"
check "no credentials file created" \
  "$(test -e "$HOME/.claude/.credentials.json" && echo yes || echo no)" "no"

seed_login UID-B b@example.net TOK-B
# A plaintext fallback left by an older/failed Keychain write must not take
# precedence over the live Keychain login. Exercise automatic selection.
cp "$CCSWITCH_HOME/accounts/alpha/credentials.json" "$HOME/.claude/.credentials.json"
if ! ccswitch add beta >/dev/null; then
  bad "add beta reads the live keychain despite a stale credentials file"
  exit 1
fi
check "add prefers the live keychain over a stale file" \
  "$(j /vault/accounts/beta/credentials.json "['claudeAiOauth']['accessToken']")" "TOK-B"
check "two accounts listed"  "$(ccswitch list | grep -c example)" "2"

ccswitch alpha --force >/dev/null
check "switch writes the keychain" "$(tok)"                  "TOK-A"
check "switch carries identity"    "$(j /.claude.json "['userID']")" "UID-A"

# Switching must not overwrite the stale plaintext fallback either.
check "stale credentials file is untouched" \
  "$(j /.claude/.credentials.json "['claudeAiOauth']['accessToken']")" "TOK-A"

# a token rewritten in the keychain mid-session must survive a round trip
python3 -c "
import json,os,time
cred=json.dumps({'claudeAiOauth':{'accessToken':'TOK-A2','refreshToken':'r2','scopes':['user:inference','user:profile'],'expiresAt':int((time.time()+12*3600)*1000)}})
os.system('security add-generic-password -U -a \"\$USER\" -s \"Claude Code-credentials\" -X '+cred.encode().hex())"
ccswitch beta --force >/dev/null; ccswitch alpha --force >/dev/null
check "keychain refresh persisted" "$(tok)" "TOK-A2"

# MCP server tokens in the keychain item are shared, not swapped with the login
python3 -c "
import json,os,subprocess
cur=json.loads(subprocess.check_output(['security','find-generic-password','-a',os.environ['USER'],'-s','Claude Code-credentials','-w']))
cur['mcpOAuth']={'figma|k':{'serverName':'figma','accessToken':'FIG-KC','note':'设计\\nreview'}}
os.system('security add-generic-password -U -a \"\$USER\" -s \"Claude Code-credentials\" -X '+json.dumps(cur).encode().hex())"
ccswitch beta --force >/dev/null
check "keychain: mcp token follows the switch" \
  "$(kc_get "Claude Code-credentials" | python3 -c 'import json,sys;print(json.load(sys.stdin)["mcpOAuth"]["figma|k"]["accessToken"])' 2>/dev/null || echo MISSING)" "FIG-KC"
check "keychain: claude token still swapped" "$(tok)" "TOK-B"
check "keychain: Unicode and escaped newlines survive" \
  "$(kc_get "Claude Code-credentials" | python3 -c 'import json,sys; print(json.load(sys.stdin)["mcpOAuth"]["figma|k"]["note"] == "设计\nreview")')" "True"
ccswitch alpha --force >/dev/null

# Isolated accounts bypass MCP merging and pass the stored (multi-line) JSON
# straight to cred_write, so normalization must live in the backend itself.
ccswitch mcp isolate alpha >/dev/null
ccswitch beta --force >/dev/null
ccswitch alpha --force >/dev/null
check "isolated account remains readable through security -w" "$(tok)" "TOK-A2"
ccswitch mcp share alpha >/dev/null

# Invalid JSON must fail before replacing a still-usable Keychain item.
cp "$CCSWITCH_HOME/accounts/beta/credentials.json" "$TMP/beta-backup.json"
printf '{invalid JSON\n' > "$CCSWITCH_HOME/accounts/beta/credentials.json"
if ccswitch beta --force > "$TMP/invalid-output" 2>&1; then
  bad "invalid credential JSON is rejected"
else
  ok "invalid credential JSON is rejected"
fi
check "invalid JSON leaves the live credential intact" "$(tok)" "TOK-A2"
cp "$TMP/beta-backup.json" "$CCSWITCH_HOME/accounts/beta/credentials.json"

# Python accepts non-finite numbers by default, but Claude's JSON parser does
# not. These must also be rejected before replacing the live credential.
python3 - "$CCSWITCH_HOME/accounts/beta/credentials.json" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as f:
    data = json.load(f)
data["invalidNumber"] = float("nan")
with open(path, "w") as f:
    json.dump(data, f)
PY
if ccswitch beta --force > "$TMP/nonfinite-output" 2>&1; then
  bad "non-finite JSON number is rejected"
else
  ok "non-finite JSON number is rejected"
fi
check "non-finite JSON leaves the live credential intact" "$(tok)" "TOK-A2"
cp "$TMP/beta-backup.json" "$CCSWITCH_HOME/accounts/beta/credentials.json"

# every account still holds a valid token, so this must skip without needing
# 'claude' and must leave the live item alone
ccswitch refresh --all >/dev/null
check "refresh skips, keychain untouched" "$(tok)" "TOK-A2"
check "refresh left current alone"        "$(ccswitch current)" "alpha"

# Explicit plaintext mode remains available for Macs without Keychain access.
CCSWITCH_BACKEND=file CCSWITCH_HOME="$TMP/file-vault" ccswitch add fallback >/dev/null
check "explicit file backend reads the file" \
  "$(j /file-vault/accounts/fallback/credentials.json "['claudeAiOauth']['accessToken']")" "TOK-A"

# Optional integration check with an installed Claude binary. security(1) is
# still the fixture, and env -i excludes the real user's auth/config settings.
if [ -n "${CCSWITCH_TEST_CLAUDE:-}" ]; then
  printf '{"claudeAiOauth":{}}\n' > "$HOME/.claude/.credentials.json"
  for name in beta alpha; do
    ccswitch "$name" --force >/dev/null
    if status="$(env -i HOME="$HOME" USER="$USER" PATH="$PATH" \
      FAKE_KEYCHAIN="$FAKE_KEYCHAIN" CLAUDE_SECURESTORAGE_CONFIG_DIR='' \
      "$CCSWITCH_TEST_CLAUDE" auth status)"; then
      check "claude auth status after switching to $name" \
        "$(printf '%s' "$status" | python3 -c 'import json,sys; print(json.load(sys.stdin)["loggedIn"])')" "True"
      case "$name" in beta) email=b@example.net ;; alpha) email=a@example.com ;; esac
      check "claude auth status identifies $name" \
        "$(printf '%s' "$status" | python3 -c 'import json,sys; print(json.load(sys.stdin)["email"])')" "$email"
    else
      bad "claude auth status failed after switching to $name"
    fi
  done
fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
