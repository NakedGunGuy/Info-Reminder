#!/usr/bin/env bash
# Install (or remove) the hourly sweep timer.
#   install-sweep.sh            enable it
#   install-sweep.sh --remove   disable it
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
MODE="${1:-add}"

if [[ "$MODE" == "--remove" ]]; then
  systemctl --user disable --now info-reminder-sweep.timer 2>/dev/null || true
  rm -f "$UNIT_DIR/info-reminder-sweep."{service,timer}
  systemctl --user daemon-reload
  echo "Sweep timer removed."
  exit 0
fi

mkdir -p "$UNIT_DIR"
install -m644 "$REPO/claude/sweep/info-reminder-sweep.service" "$UNIT_DIR/"
install -m644 "$REPO/claude/sweep/info-reminder-sweep.timer" "$UNIT_DIR/"
systemctl --user daemon-reload
systemctl --user enable --now info-reminder-sweep.timer

echo
systemctl --user list-timers info-reminder-sweep.timer --no-pager
echo
echo "Run it once by hand:   systemctl --user start info-reminder-sweep.service"
echo "Watch what it does:    tail -f ~/.local/state/info-reminder/sweep.log"
