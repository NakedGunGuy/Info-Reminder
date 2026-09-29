#!/usr/bin/env bash
# Install the information ledger: CLI on PATH, bar plugin in the omarchy
# shell, and the Claude Code integration that makes it work in every project.
#
# Everything is symlinked back to this repo, so editing the repo IS editing
# the installed thing — no copy step to forget.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${HOME}/.local/bin"
PLUGIN_DIR="${HOME}/.config/omarchy/plugins/perko.info-reminder"
SKILL_DIR="${HOME}/.claude/skills/info-reminder"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/info-reminder"

say() { printf '  %s\n' "$*"; }

link() { # link <target> <linkname>
  local target="$1" name="$2"
  if [[ -L "$name" ]]; then
    rm "$name"
  elif [[ -e "$name" ]]; then
    say "! $name exists and is not a symlink — moving it aside"
    mv "$name" "$name.bak.$(date +%s)"
  fi
  mkdir -p "$(dirname "$name")"
  ln -s "$target" "$name"
  say "→ $name"
}

echo
echo "Installing the information ledger"
echo

# 1. CLI -----------------------------------------------------------------
mkdir -p "$BIN_DIR"
link "$REPO/bin/ir" "$BIN_DIR/ir"
link "$REPO/bin/ir-mail" "$BIN_DIR/ir-mail"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) say "! $BIN_DIR is not on your PATH — add it to your shell rc" ;;
esac

# 2. Ledger --------------------------------------------------------------
mkdir -p "$DATA_DIR"
if [[ ! -f "$DATA_DIR/ledger.json" ]]; then
  printf '{\n  "version": 1,\n  "items": []\n}\n' > "$DATA_DIR/ledger.json"
  say "→ $DATA_DIR/ledger.json (new, empty)"
else
  say "→ $DATA_DIR/ledger.json (kept)"
fi

# 3. Bar plugin ----------------------------------------------------------
link "$REPO/shell-plugin" "$PLUGIN_DIR"
if command -v omarchy >/dev/null; then
  omarchy plugin validate "$REPO/shell-plugin" >/dev/null 2>&1 \
    && say "  manifest validates" \
    || say "! manifest failed validation"
fi

# 4. Thunderbird prefs ---------------------------------------------------
# These are what make the local mail store actually usable: full offline bodies,
# maildir storage, and ignoring IMAP subscriptions (which otherwise hide Sent).
TB_PROFILE="$(ls -d "$HOME"/.thunderbird/*.default-release 2>/dev/null | head -1)"
if [[ -n "$TB_PROFILE" ]]; then
  cp "$REPO/thunderbird/user.js" "$TB_PROFILE/user.js"
  say "→ $TB_PROFILE/user.js"
else
  say "! no Thunderbird profile yet — run Thunderbird once, then re-run this"
fi

# 5. Claude Code skill ---------------------------------------------------
link "$REPO/claude/skill" "$SKILL_DIR"

# 6. Claude Code session hook -------------------------------------------
say ""
say "Last step is the SessionStart hook, which is what makes Claude aware of"
say "the ledger in every project. Run:"
say ""
say "    $REPO/claude/hooks/install-hook.sh"
say ""

echo "Done. Add the bar pill with:"
echo "    omarchy bar put perko.info-reminder --section right --index 0"
echo
