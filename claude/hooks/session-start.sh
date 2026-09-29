#!/usr/bin/env bash
# SessionStart hook: put the information ledger in front of Claude in every
# project, every session. Stdout becomes session context.
#
# Deliberately forgiving — a broken ledger must never stop a session from
# starting, so every failure path exits 0 silently.

IR="${HOME}/.local/bin/ir"
[[ -x "$IR" ]] || exit 0

"$IR" brief --limit 8 2>/dev/null || true
exit 0
