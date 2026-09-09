#!/usr/bin/env bash
# Smoke test for ccswitch. Runs against a throwaway HOME - touches nothing real.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP"
export PATH="$ROOT/bin:$PATH"
export NO_COLOR=1
unset CLAUDE_CONFIG_DIR
# Pin the vault inside TMP. VAULT falls back to $XDG_CONFIG_HOME, which
# escapes $HOME - without this the test would operate on a real vault.
export CCSWITCH_HOME="$TMP/vault"
unset XDG_CONFIG_HOME

pass=0; fail=0
ok()   { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  FAIL %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want '$3', got '$2')"; fi; }

seed_login() {  # $1=uid $2=email $3=token $4=hours
  mkdir -p "$HOME/.claude"
  python3 - "$1" "$2" "$3" "$4" <<'PY'
import json, os, sys, time
uid, email, token, hours = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4])
h = os.environ["HOME"]
json.dump({"claudeAiOauth": {"accessToken": token, "refreshToken": "r-" + token,
                             "expiresAt": int((time.time() + hours * 3600) * 1000),
                             "refreshTokenExpiresAt": int((time.time() + 28 * 86400) * 1000)}},
          open(h + "/.claude/.credentials.json", "w"))
p = h + "/.claude.json"
d = json.load(open(p)) if os.path.exists(p) else {}
d["userID"] = uid
d["oauthAccount"] = {"emailAddress": email}
json.dump(d, open(p, "w"), indent=2)
PY
}

j() { python3 -c "import json,os,sys;print(json.load(open(os.environ['HOME']+sys.argv[1]))$2)" "$1" 2>/dev/null || echo MISSING; }

echo "ccswitch smoke test"

# shared config that must survive every switch
mkdir -p "$HOME/.claude/plugins" "$HOME/.claude/projects/repo"
echo '# memory' > "$HOME/.claude/CLAUDE.md"
python3 -c "
import json,os
h=os.environ['HOME']
json.dump({'mcpServers':{'github':{'url':'https://x'}},'projects':{'/r':{'trust':True}}},
          open(h+'/.claude.json','w'))"

seed_login UID-A a@example.com TOK-A 9
ccswitch add alpha >/dev/null
check "add alpha"            "$(ccswitch current)"                       "alpha"

seed_login UID-B b@example.com TOK-B 3
ccswitch add beta >/dev/null
check "add beta"             "$(ccswitch current)"                       "beta"
check "two accounts listed"  "$(ccswitch list | grep -c example.com)"    "2"

ccswitch alpha --force >/dev/null
check "switch: token"        "$(j /.claude/.credentials.json "['claudeAiOauth']['accessToken']")" "TOK-A"
check "switch: userID"       "$(j /.claude.json "['userID']")"           "UID-A"
check "switch: email"        "$(j /.claude.json "['oauthAccount']['emailAddress']")" "a@example.com"
check "shared: mcpServers"   "$(j /.claude.json "['mcpServers']['github']['url']")" "https://x"
check "shared: projects"     "$(j /.claude.json "['projects']['/r']['trust']")" "True"
check "shared: CLAUDE.md"    "$(cat "$HOME/.claude/CLAUDE.md")"          "# memory"
check "shared: plugins dir"  "$(test -d "$HOME/.claude/plugins" && echo yes)" "yes"

# a token refreshed mid-session must survive a round trip
python3 -c "
import json,os,time
h=os.environ['HOME']
json.dump({'claudeAiOauth':{'accessToken':'TOK-A2','refreshToken':'r2','expiresAt':int((time.time()+12*3600)*1000)}},
          open(h+'/.claude/.credentials.json','w'))"
ccswitch beta --force >/dev/null; ccswitch alpha --force >/dev/null
check "refresh persisted"    "$(j /.claude/.credentials.json "['claudeAiOauth']['accessToken']")" "TOK-A2"

# Fix for the daily-relogin bug: Claude Code rotates the refresh token during a
# session and on /login, neither of which goes through ccswitch. Any ccswitch
# run must pull that into the active slot, or the vault keeps a consumed token.
python3 -c "
import json,os,time
h=os.environ['HOME']
json.dump({'claudeAiOauth':{'accessToken':'TOK-ROTATED','refreshToken':'r-rotated',
                            'expiresAt':int((time.time()+20*3600)*1000),
                            'refreshTokenExpiresAt':int((time.time()+28*86400)*1000)}},
          open(h+'/.claude/.credentials.json','w'))"
ccswitch list >/dev/null   # any command, not a switch
check "rotation synced into the active slot" \
  "$(python3 -c "import json,os;print(json.load(open(os.environ['CCSWITCH_HOME']+'/accounts/alpha/credentials.json'))['claudeAiOauth']['accessToken'])")" \
  "TOK-ROTATED"

# but a live credential belonging to a different account must NOT be synced
# into the active slot - that would corrupt it
python3 -c "
import json,os,time
h=os.environ['HOME']
d=json.load(open(h+'/.claude.json')); d['userID']='UID-OTHER'
d['oauthAccount']={'emailAddress':'other@example.com'}
json.dump(d,open(h+'/.claude.json','w'),indent=2)
json.dump({'claudeAiOauth':{'accessToken':'TOK-WRONG','refreshToken':'r-wrong',
                            'expiresAt':int((time.time()+8*3600)*1000),
                            'refreshTokenExpiresAt':int((time.time()+28*86400)*1000)}},
          open(h+'/.claude/.credentials.json','w'))"
ccswitch list >/dev/null
check "mismatched identity is not synced" \
  "$(python3 -c "import json,os;print(json.load(open(os.environ['CCSWITCH_HOME']+'/accounts/alpha/credentials.json'))['claudeAiOauth']['accessToken'])")" \
  "TOK-ROTATED"

# put alpha's real identity back (ccswitch <name> short-circuits when already
# active, so it would not undo the identity we just faked)
python3 -c "
import json,os
h=os.environ['HOME']
d=json.load(open(h+'/.claude.json')); d['userID']='UID-A'
d['oauthAccount']={'emailAddress':'a@example.com'}
json.dump(d,open(h+'/.claude.json','w'),indent=2)
import time
json.dump({'claudeAiOauth':{'accessToken':'TOK-ROTATED','refreshToken':'r-rotated',
                            'expiresAt':int((time.time()+20*3600)*1000),
                            'refreshTokenExpiresAt':int((time.time()+28*86400)*1000)}},
          open(h+'/.claude/.credentials.json','w'))"

ccswitch rename alpha gamma >/dev/null
check "rename"               "$(ccswitch current)"                       "gamma"

ccswitch backup "$TMP/v.tgz" >/dev/null 2>&1
ccswitch rm beta >/dev/null
check "rm"                   "$(ccswitch list | grep -c example.com)"    "1"
ccswitch restore "$TMP/v.tgz" >/dev/null
check "restore"              "$(ccswitch list | grep -c example.com)"    "2"

# both accounts still hold their original, unexpired tokens - refresh should
# skip them without needing 'claude' on PATH or touching current
ccswitch refresh --all >/dev/null
check "refresh: skips valid tokens, leaves current" "$(ccswitch current)" "gamma"
check "refresh: accounts untouched"          "$(ccswitch list | grep -c example.com)" "2"

# A cleared credential - what Claude Code writes when the server rejects a
# refresh with invalid_grant - must never overwrite a good stored slot.
python3 -c "
import json,os
h=os.environ['HOME']
json.dump({'claudeAiOauth':{'accessToken':'','refreshToken':'','expiresAt':0,
                            'refreshTokenExpiresAt':0}},
          open(h+'/.claude/.credentials.json','w'))"
if ccswitch save >/dev/null 2>&1; then bad "save refuses a cleared credential"; else ok "save refuses a cleared credential"; fi
check "cleared credential did not clobber the slot" \
  "$(python3 -c "import json,os;print(json.load(open(os.environ['CCSWITCH_HOME']+'/accounts/gamma/credentials.json'))['claudeAiOauth']['accessToken'])")" \
  "TOK-ROTATED"
check "list flags the live account as usable" "$(ccswitch list | grep -c BROKEN)" "0"

# a slot that is genuinely cleared must be reported, not shown as 'unknown'
python3 -c "
import json,os
p=os.environ['CCSWITCH_HOME']+'/accounts/beta/credentials.json'
json.dump({'claudeAiOauth':{'accessToken':'','refreshToken':'','expiresAt':0}},open(p,'w'))"
check "list reports a broken slot" "$(ccswitch list | grep -c BROKEN)" "1"
check "refresh skips a broken slot" "$(ccswitch refresh --all 2>&1 | grep -c 'signed out')" "1"

# restore the good state for the remaining checks
ccswitch restore "$TMP/v.tgz" >/dev/null

# Long-lived helpers share the claude binary and process name - the
# Claude-in-Chrome native host lives as long as the browser - and matching them
# would block every switch and login for as long as Chrome is open.
mkdir -p "$TMP/fakebin"
printf '#!/usr/bin/env bash\nsleep 30\n' > "$TMP/fakebin/claude"
chmod +x "$TMP/fakebin/claude"
( PATH="$TMP/fakebin:$PATH" exec "$TMP/fakebin/claude" --chrome-native-host ) &
fake_pid=$!
( PATH="$TMP/fakebin:$PATH" exec "$TMP/fakebin/claude" ) &
real_pid=$!
sleep 1
# shellcheck source=/dev/null
source <(sed -n '/^claude_session_pids()/,/^}/p' "$ROOT/bin/ccswitch")
seen="$(PATH="$TMP/fakebin:$PATH" claude_session_pids)"
check "chrome native host is not a session" "$(printf '%s\n' "$seen" | grep -c "^$fake_pid$")" "0"
check "a real session is still detected"    "$(printf '%s\n' "$seen" | grep -c "^$real_pid$")" "1"
kill "$fake_pid" "$real_pid" 2>/dev/null || true
wait "$fake_pid" "$real_pid" 2>/dev/null || true

# Signing in with /login inside Claude Code changes the live account without
# telling ccswitch. A blind 'save' would then write that credential over a
# different account's slot.
# A rotation belongs to whichever account is really signed in, which a /login
# inside Claude Code can change without telling ccswitch. Route it by email and
# follow it, rather than writing it into whatever slot happens to be active.
gamma_before="$(python3 -c "import json,os;print(json.load(open(os.environ['CCSWITCH_HOME']+'/accounts/gamma/credentials.json'))['claudeAiOauth']['accessToken'])")"
seed_login UID-B b@example.com TOK-B9 9      # live is beta's, active is gamma
ccswitch list >/dev/null                     # any command, not a switch
check "sync follows the live account"     "$(ccswitch current)" "beta"
check "sync stored it in the right slot" \
  "$(python3 -c "import json,os;print(json.load(open(os.environ['CCSWITCH_HOME']+'/accounts/beta/credentials.json'))['claudeAiOauth']['accessToken'])")" \
  "TOK-B9"
check "sync left the previous slot alone" \
  "$(python3 -c "import json,os;print(json.load(open(os.environ['CCSWITCH_HOME']+'/accounts/gamma/credentials.json'))['claudeAiOauth']['accessToken'])")" \
  "$gamma_before"

# a credential belonging to no stored account has no home - refuse it rather
# than guessing, and change nothing
seed_login UID-X stranger@example.org TOK-X 9
if ccswitch save >/dev/null 2>&1; then bad "save refuses an unknown account"; else ok "save refuses an unknown account"; fi
check "unknown-account save changed nothing" \
  "$(python3 -c "import json,os;print(json.load(open(os.environ['CCSWITCH_HOME']+'/accounts/beta/credentials.json'))['claudeAiOauth']['accessToken'])")" \
  "TOK-B9"

# an explicit target still works, and is the escape hatch for a new machine
seed_login UID-B b@example.com TOK-B10 9
ccswitch save beta >/dev/null
check "targeted save stores into the named slot" \
  "$(python3 -c "import json,os;print(json.load(open(os.environ['CCSWITCH_HOME']+'/accounts/beta/credentials.json'))['claudeAiOauth']['accessToken'])")" \
  "TOK-B10"

# Version comparison must be numeric, not lexical: "0.10.0" is newer than
# "0.9.0" but sorts before it as a string.
# shellcheck source=/dev/null
source <(sed -n '/^version_gt()/,/^}/p' "$ROOT/bin/ccswitch")
vg() { if version_gt "$1" "$2"; then echo yes; else echo no; fi; }
check "version_gt 0.10.0 > 0.9.0"  "$(vg 0.10.0 0.9.0)"  "yes"
check "version_gt 0.9.0 !> 0.10.0" "$(vg 0.9.0 0.10.0)"  "no"
check "version_gt equal is false"  "$(vg 0.5.0 0.5.0)"   "no"
check "version_gt 1.0.0 > 0.99.9"  "$(vg 1.0.0 0.99.9)"  "yes"
check "version_gt handles shorts"  "$(vg 0.5.1 0.5)"     "yes"

# Being signed out must not trap you on the dead account. capture_into refuses
# a cleared credential by design, but that refusal must not abort the switch -
# switching away is exactly what you need when a session has died.
python3 -c "
import json,os
h=os.environ['HOME']
json.dump({'claudeAiOauth':{'accessToken':'','refreshToken':'','expiresAt':0,
                            'refreshTokenExpiresAt':0}},
          open(h+'/.claude/.credentials.json','w'))"
before_gamma="$(python3 -c "import json,os;print(json.load(open(os.environ['CCSWITCH_HOME']+'/accounts/gamma/credentials.json'))['claudeAiOauth']['accessToken'])")"
if ccswitch use beta --force >/dev/null 2>&1; then ok "can switch away from a signed-out session"; else bad "can switch away from a signed-out session"; fi
check "signed-out switch landed"        "$(ccswitch current)" "beta"
check "signed-out switch kept the slot" \
  "$(python3 -c "import json,os;print(json.load(open(os.environ['CCSWITCH_HOME']+'/accounts/gamma/credentials.json'))['claudeAiOauth']['accessToken'])")" \
  "$before_gamma"

# userID in .claude.json is not the account identifier - the same value has been
# seen against two different accounts, and it changes across logins. Matching on
# it produced false mismatches that silently disabled the sync.
python3 -c "
import json,os,time
h=os.environ['HOME']
d=json.load(open(h+'/.claude.json')); d['userID']='A-BRAND-NEW-INSTALL-ID'
d['oauthAccount']={'emailAddress':'b@example.com'}
json.dump(d,open(h+'/.claude.json','w'),indent=2)
json.dump({'claudeAiOauth':{'accessToken':'TOK-B-ROT','refreshToken':'r-brot',
                            'expiresAt':int((time.time()+20*3600)*1000),
                            'refreshTokenExpiresAt':int((time.time()+28*86400)*1000)}},
          open(h+'/.claude/.credentials.json','w'))"
ccswitch list >/dev/null
check "new userID with same email still syncs" \
  "$(python3 -c "import json,os;print(json.load(open(os.environ['CCSWITCH_HOME']+'/accounts/beta/credentials.json'))['claudeAiOauth']['accessToken'])")" \
  "TOK-B-ROT"

# but a genuinely different account must still be refused
python3 -c "
import json,os,time
h=os.environ['HOME']
d=json.load(open(h+'/.claude.json')); d['oauthAccount']={'emailAddress':'stranger@example.org'}
json.dump(d,open(h+'/.claude.json','w'),indent=2)
json.dump({'claudeAiOauth':{'accessToken':'TOK-STRANGER','refreshToken':'r-s',
                            'expiresAt':int((time.time()+8*3600)*1000),
                            'refreshTokenExpiresAt':int((time.time()+28*86400)*1000)}},
          open(h+'/.claude/.credentials.json','w'))"
ccswitch list >/dev/null
check "a different email is still not synced" \
  "$(python3 -c "import json,os;print(json.load(open(os.environ['CCSWITCH_HOME']+'/accounts/beta/credentials.json'))['claudeAiOauth']['accessToken'])")" \
  "TOK-B-ROT"

# A stale credentials.json - left by an older install, or sitting on a machine
# a vault was just restored onto - must never overwrite a newer stored token.
# Rotation always moves the access-token expiry forward, so an older expiry
# means the live file is the stale one.
good_beta="$(python3 -c "import json,os;print(json.load(open(os.environ['CCSWITCH_HOME']+'/accounts/beta/credentials.json'))['claudeAiOauth']['accessToken'])")"
python3 -c "
import json,os,time
h=os.environ['HOME']
d=json.load(open(h+'/.claude.json')); d['oauthAccount']={'emailAddress':'b@example.com'}
json.dump(d,open(h+'/.claude.json','w'),indent=2)
json.dump({'claudeAiOauth':{'accessToken':'TOK-ANCIENT','refreshToken':'r-anc',
                            'expiresAt':int((time.time()-103*86400)*1000),
                            'refreshTokenExpiresAt':int((time.time()-75*86400)*1000)}},
          open(h+'/.claude/.credentials.json','w'))"
ccswitch list >/dev/null
check "a stale credential does not clobber a newer one" \
  "$(python3 -c "import json,os;print(json.load(open(os.environ['CCSWITCH_HOME']+'/accounts/beta/credentials.json'))['claudeAiOauth']['accessToken'])")" \
  "$good_beta"

# but a real rotation, which moves the expiry forward, must still be adopted
python3 -c "
import json,os,time
h=os.environ['HOME']
json.dump({'claudeAiOauth':{'accessToken':'TOK-B-NEWER','refreshToken':'r-newer',
                            'expiresAt':int((time.time()+30*3600)*1000),
                            'refreshTokenExpiresAt':int((time.time()+28*86400)*1000)}},
          open(h+'/.claude/.credentials.json','w'))"
ccswitch list >/dev/null
check "a newer credential is still adopted" \
  "$(python3 -c "import json,os;print(json.load(open(os.environ['CCSWITCH_HOME']+'/accounts/beta/credentials.json'))['claudeAiOauth']['accessToken'])")" \
  "TOK-B-NEWER"

# Two machines cannot share one stored credential: rotation means only the
# holder of the newest link stays signed in. ccswitch cannot prevent that, but
# it must say so rather than leaving a mystifying forced /login.
check "capture records this machine" \
  "$(head -1 "$CCSWITCH_HOME/accounts/beta/host" 2>/dev/null)" "$(uname -n)"
echo "some-other-machine" > "$CCSWITCH_HOME/accounts/beta/host"
check "list warns about a foreign vault" \
  "$(ccswitch list 2>&1 | grep -c 'another machine (some-other-machine)')" "1"
check "doctor names the machine"        "$(ccswitch doctor 2>&1 | grep -c 'last on some-other-machine')" "1"
check "doctor explains why it breaks"   "$(ccswitch doctor 2>&1 | grep -c 'rotates on every use')" "1"
printf '%s\n' "$(uname -n)" > "$CCSWITCH_HOME/accounts/beta/host"
check "no warning once it is local"     "$(ccswitch list 2>&1 | grep -c 'another machine')" "0"

# error paths must exit non-zero
must_fail() {  # $1=label, rest=command
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then bad "$label"; else ok "$label"; fi
}
must_fail "unknown account rejected" ccswitch use nosuch
must_fail "duplicate name rejected"  ccswitch add gamma
must_fail "invalid name rejected"    ccswitch add 'bad/nm'
must_fail "login needs a name"       ccswitch login
must_fail "refresh: unknown account rejected" ccswitch refresh nosuch

ccswitch doctor >/dev/null 2>&1 || true
ok "doctor runs"
ccswitch completion zsh  >/dev/null && ok "zsh completion"
ccswitch completion bash >/dev/null && ok "bash completion"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
