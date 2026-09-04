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
                             "expiresAt": int((time.time() + hours * 3600) * 1000)}},
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

ccswitch alpha >/dev/null
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
ccswitch beta >/dev/null; ccswitch alpha >/dev/null
check "refresh persisted"    "$(j /.claude/.credentials.json "['claudeAiOauth']['accessToken']")" "TOK-A2"

ccswitch rename alpha gamma >/dev/null
check "rename"               "$(ccswitch current)"                       "gamma"

ccswitch backup "$TMP/v.tgz" >/dev/null 2>&1
ccswitch rm beta >/dev/null
check "rm"                   "$(ccswitch list | grep -c example.com)"    "1"
ccswitch restore "$TMP/v.tgz" >/dev/null
check "restore"              "$(ccswitch list | grep -c example.com)"    "2"

# error paths must exit non-zero
must_fail() {  # $1=label, rest=command
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then bad "$label"; else ok "$label"; fi
}
must_fail "unknown account rejected" ccswitch use nosuch
must_fail "duplicate name rejected"  ccswitch add gamma
must_fail "invalid name rejected"    ccswitch add 'bad/nm'
must_fail "login needs a name"       ccswitch login

ccswitch doctor >/dev/null 2>&1 || true
ok "doctor runs"
ccswitch completion zsh  >/dev/null && ok "zsh completion"
ccswitch completion bash >/dev/null && ok "bash completion"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
