#!/usr/bin/env bash
# Hourly: pull the support mailbox, let Claude reconcile the ledger against
# reality, and notify only if something actually changed.
#
# Designed to be boring when there is nothing to do: no ledger items means no
# Claude invocation at all, and a quiet run says nothing.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IR="${HOME}/.local/bin/ir"
PROMPT="$REPO/claude/sweep/sweep-prompt.md"
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/info-reminder"
LOG="$LOG_DIR/sweep.log"
mkdir -p "$LOG_DIR"

log() { printf '%s  %s\n' "$(date -Is)" "$*" >> "$LOG"; }

[[ -x "$IR" ]] || { log "no ir binary; giving up"; exit 0; }

# 1. Mail comes from Thunderbird's local store, which it keeps synced in the
#    background. Nothing to pull here — but if Thunderbird is not running the
#    store goes stale, and a stale store silently produces "no reply found",
#    which is the worst possible failure. So say so loudly in the log.
if pgrep -x thunderbird >/dev/null 2>&1; then
  log "thunderbird running; local mail store is live"
else
  log "WARNING: thunderbird is NOT running — mail evidence will be stale"
  if command -v thunderbird >/dev/null; then
    if command -v uwsm >/dev/null; then
      uwsm app -- thunderbird >/dev/null 2>&1 &
    else
      thunderbird >/dev/null 2>&1 &
    fi
    # Claim nothing until it is actually up; a false "started" line in the log
    # is worse than no line, because it hides the reason evidence went missing.
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      sleep 1
      pgrep -x thunderbird >/dev/null 2>&1 && break
    done
    if pgrep -x thunderbird >/dev/null 2>&1; then
      log "started thunderbird; giving it a moment to sync"
      sleep 20
    else
      log "ERROR: could not start thunderbird"
    fi
  else
    log "ERROR: thunderbird is not installed — support mail cannot be read"
  fi
fi

# 2. Nothing outstanding means nothing to sweep. Skip the API call entirely.
LIVE="$("$IR" bar --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["live"])' 2>/dev/null || echo 0)"
if [[ "$LIVE" == "0" ]]; then
  log "ledger empty; skipped"
  exit 0
fi

START="$(date -Is)"
log "sweep start ($LIVE live items)"

timeout 900 claude -p "$(cat "$PROMPT")" \
  --allowedTools \
    "Bash(ir:*)" \
    "Bash(ir-mail:*)" \
    "Bash(grep:*)" \
    "Bash(ls:*)" \
    "Read" \
    "mcp__claude_ai_Microsoft_365__outlook_email_search" \
    "mcp__claude_ai_Microsoft_365__read_resource" \
    "mcp__claude_ai_ClickUp__clickup_get_task_comments" \
    "mcp__claude_ai_ClickUp__clickup_get_task" \
    "mcp__claude_ai_Slack__slack_search_public_and_private" \
    "mcp__claude_ai_Microsoft_365__teams_list_chats" \
  >>"$LOG" 2>&1
log "sweep done (exit $?)"

# 3. Notify only about decisions actually taken this run.
CHANGES="$("$IR" audit --since "$START" --json 2>/dev/null \
  | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))' 2>/dev/null || echo 0)"

if [[ "$CHANGES" -gt 0 ]]; then
  SUMMARY="$("$IR" audit --since "$START" --json \
    | python3 -c '
import json, sys
rows = json.load(sys.stdin)
for r in rows[:4]:
    print(f"• {r[\"title\"]}")
if len(rows) > 4:
    print(f"… and {len(rows) - 4} more")
')"
  notify-send --app-name="Information ledger" --icon=mail-message-new \
    "Ledger: $CHANGES auto-updated" \
    "$SUMMARY

Check with: ir audit"
  log "notified: $CHANGES change(s)"
else
  log "no changes"
fi

exit 0
