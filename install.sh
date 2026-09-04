#!/usr/bin/env bash
# ccswitch installer
#   curl -fsSL https://raw.githubusercontent.com/YOURNAME/ccswitch/main/install.sh | bash
set -euo pipefail

REPO="${CCSWITCH_REPO:-YOURNAME/ccswitch}"
REF="${CCSWITCH_REF:-main}"
PREFIX="${PREFIX:-$HOME/.local/bin}"
URL="https://raw.githubusercontent.com/$REPO/$REF/bin/ccswitch"

command -v python3 >/dev/null 2>&1 || { echo "python3 is required"; exit 1; }

mkdir -p "$PREFIX"

if [ -f "./bin/ccswitch" ]; then
  install -m 755 ./bin/ccswitch "$PREFIX/ccswitch"      # local checkout
else
  curl -fsSL "$URL" -o "$PREFIX/ccswitch"
  chmod 755 "$PREFIX/ccswitch"
fi

echo "installed -> $PREFIX/ccswitch"

case ":$PATH:" in
  *":$PREFIX:"*) ;;
  *)
    echo
    echo "$PREFIX is not on your PATH. Add it:"
    echo "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc"
    ;;
esac

cat <<'EOF'

Optional shell completion:
  # zsh
  mkdir -p ~/.zfunc && ccswitch completion zsh > ~/.zfunc/_ccswitch
  echo 'fpath=(~/.zfunc $fpath); autoload -Uz compinit && compinit' >> ~/.zshrc
  # bash
  ccswitch completion bash >> ~/.bashrc

Get started:
  ccswitch login work
  ccswitch login personal
  ccswitch list
EOF
