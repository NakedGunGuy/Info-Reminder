#!/usr/bin/env bash
# Register (or remove) the SessionStart hook in ~/.claude/settings.json.
# Idempotent, backs up first, and leaves any other hooks untouched.
#
#   install-hook.sh            add the hook
#   install-hook.sh --remove   take it out again

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$REPO/claude/hooks/session-start.sh"
SETTINGS="${HOME}/.claude/settings.json"
MODE="${1:-add}"

python3 - "$SETTINGS" "$HOOK" "$MODE" <<'PY'
import json, os, shutil, sys, time

settings_path, hook_cmd, mode = sys.argv[1], sys.argv[2], sys.argv[3]

if os.path.exists(settings_path):
    with open(settings_path, encoding="utf-8") as fh:
        settings = json.load(fh)
    shutil.copy2(settings_path, f"{settings_path}.bak.{int(time.time())}")
else:
    settings = {}
    os.makedirs(os.path.dirname(settings_path), exist_ok=True)

hooks = settings.setdefault("hooks", {})
groups = hooks.setdefault("SessionStart", [])

def has_hook(group):
    return any(h.get("command") == hook_cmd for h in group.get("hooks", []))

present = any(has_hook(g) for g in groups)

if mode == "--remove":
    for g in groups:
        g["hooks"] = [h for h in g.get("hooks", []) if h.get("command") != hook_cmd]
    hooks["SessionStart"] = [g for g in groups if g.get("hooks")]
    if not hooks["SessionStart"]:
        del hooks["SessionStart"]
    print("removed" if present else "was not installed")
elif present:
    print("already installed")
else:
    # Its own group, so it is independent of whatever else runs at session start.
    groups.append({"hooks": [{"type": "command", "command": hook_cmd}]})
    print("installed")

with open(settings_path, "w", encoding="utf-8") as fh:
    json.dump(settings, fh, indent=2)
    fh.write("\n")
PY

echo "Hook: $HOOK"
echo "Settings: $SETTINGS"
echo
echo "Takes effect in NEW Claude Code sessions. Check with:  ir brief"
