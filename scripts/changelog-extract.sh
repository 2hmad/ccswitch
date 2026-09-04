#!/usr/bin/env bash
# Print the CHANGELOG.md body for one version.
#
#   scripts/changelog-extract.sh 0.2.0
#   scripts/changelog-extract.sh v0.2.0 CHANGELOG.md
#
# Exits 1 if the version has no section, so CI fails loudly instead of
# publishing a release with empty notes.
set -euo pipefail

ver="${1:-}"
file="${2:-CHANGELOG.md}"

[ -n "$ver" ] || { echo "usage: $0 <version> [changelog]" >&2; exit 2; }
[ -f "$file" ] || { echo "no such file: $file" >&2; exit 2; }

ver="${ver#v}"

body="$(awk -v v="$ver" '
  # start of the requested section
  $0 ~ "^## \\[" v "\\]" { grab = 1; next }
  # any later section heading ends it
  grab && /^## / { exit }
  grab { print }
' "$file")"

# drop leading and trailing blank lines
body="$(printf '%s\n' "$body" | sed -e '/./,$!d' -e ':a' -e '/^\n*$/{$d;N;ba' -e '}')"

if [ -z "$body" ]; then
  echo "no '## [$ver]' section in $file (or it is empty)" >&2
  exit 1
fi

printf '%s\n' "$body"
