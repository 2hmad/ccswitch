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
export PATH="$ROOT/test/fixtures:$ROOT/bin:$PATH"
export NO_COLOR=1
# Pin the vault inside TMP. VAULT falls back to $XDG_CONFIG_HOME, which
# escapes $HOME - without this the test would operate on a real vault.
export CCSWITCH_HOME="$TMP/vault"
unset XDG_CONFIG_HOME
export CCSWITCH_BACKEND=keychain
export FAKE_KEYCHAIN="$TMP/keychain"
export USER=testuser
unset CLAUDE_CONFIG_DIR

pass=0; fail=0
ok()   { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  FAIL %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want '$3', got '$2')"; fi; }

kc_get() { security find-generic-password -a "$USER" -s "$1" -w 2>/dev/null || echo MISSING; }

seed_login() {  # $1=uid $2=email $3=token
  mkdir -p "$HOME/.claude"
  python3 - "$1" "$2" "$3" <<'PY'
import json, os, sys, time
uid, email, tok = sys.argv[1], sys.argv[2], sys.argv[3]
h = os.environ["HOME"]
p = h + "/.claude.json"
d = json.load(open(p)) if os.path.exists(p) else {}
d["userID"] = uid
d["oauthAccount"] = {"emailAddress": email}
json.dump(d, open(p, "w"), indent=2)
cred = json.dumps({"claudeAiOauth": {"accessToken": tok, "refreshToken": "r-" + tok,
                                     "expiresAt": int((time.time() + 9 * 3600) * 1000),
                                     "refreshTokenExpiresAt": int((time.time() + 28 * 86400) * 1000)}})
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

seed_login UID-B b@example.net TOK-B
ccswitch add beta >/dev/null
check "two accounts listed"  "$(ccswitch list | grep -c example)" "2"

ccswitch alpha --force >/dev/null
check "switch writes the keychain" "$(tok)"                  "TOK-A"
check "switch carries identity"    "$(j /.claude.json "['userID']")" "UID-A"

# the whole point of the backend: no credentials file is ever created
check "no credentials file written" "$(test -e "$HOME/.claude/.credentials.json" && echo yes || echo no)" "no"

# a token rewritten in the keychain mid-session must survive a round trip
python3 -c "
import json,os,time
cred=json.dumps({'claudeAiOauth':{'accessToken':'TOK-A2','refreshToken':'r2','expiresAt':int((time.time()+12*3600)*1000)}})
os.system('security add-generic-password -U -a \"\$USER\" -s \"Claude Code-credentials\" -X '+cred.encode().hex())"
ccswitch beta --force >/dev/null; ccswitch alpha --force >/dev/null
check "keychain refresh persisted" "$(tok)" "TOK-A2"

# every account still holds a valid token, so this must skip without needing
# 'claude' and must leave the live item alone
ccswitch refresh --all >/dev/null
check "refresh skips, keychain untouched" "$(tok)" "TOK-A2"
check "refresh left current alone"        "$(ccswitch current)" "alpha"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
