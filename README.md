# info-reminder

A ledger for the two questions that cost the most time in a support/agency week:

> **Did I already ask for this?**
> **Did they already give it to me?**

It is not a task list. Each entry is one piece of information moving between
you and one person, and it tracks *whose hands it is in right now*.

```
ON YOU  (2)
  [!] v2v  API credentials for KMU staging
      they answered · CU-86c6ckp74 · clickup
      → answer in — close it out
  [ ] xh3  Send specs to Dani
      you owe dani · due 2026-09-27
      → overdue 2d

WAITING ON THEM  (1)
  [~] 0hw  Logo files from client
      waiting on client x · chased 1x · quiet 6d
```

## Three faces, one file

Everything reads and writes `~/.local/share/info-reminder/ledger.json`.

| Face | What it is for |
|---|---|
| `ir` CLI | What Claude Code drives, and quick edits from any terminal |
| omarchy bar pill | The glance: `<on them>/<on you>` plus `!n` when something needs action. Click for the popup, right-click for the board |
| `ir tui` | The full board when you want to sit in it |

The bar plugin watches the file, so a change made anywhere appears on the bar
immediately — no polling, no refresh.

## Install

```bash
./install.sh
./claude/hooks/install-hook.sh
omarchy bar put perko.info-reminder --section right --index 0

# the hourly sweep
sudo pacman -S thunderbird
./claude/sweep/install-sweep.sh
```

`install.sh` symlinks everything back to this repo, so editing the repo *is*
editing the installed thing. The QML hot-reloads on save; the CLI has no build
step.

**Editing the bar plugin:** `install.sh` symlinks `shell-plugin/` into
`~/.config/omarchy/plugins/`, and the shell's file watcher does not follow the
symlink — so QML edits do **not** hot-reload the way they do for a real
directory there. Run `omarchy restart shell` after changing `Panel.qml` or
`Model.js`; `omarchy-shell shell rescanPlugins` is not enough.

## The model

| Field | Meaning |
|---|---|
| `dir` | `in` = they owe you · `out` = you owe them |
| `state` | `open` → `pending` → `answered` → `done` (plus `blocked`, `dropped`) |
| `nudge` | days of silence before it starts asking to be chased (default 3) |

State reads differently by direction, and the UI prints the plain-English form:

| state | `dir: in` | `dir: out` |
|---|---|---|
| `open` | not asked yet | you owe it, not sent |
| `pending` | waiting on them | sent to them |
| `answered` | they answered — review and close | delivered |

An item raises a flag on its own when it is overdue, has gone silent past its
`nudge` window, has an answer sitting unreviewed, or was never actually asked.
`ir list --hot` is that set; it is also what drives the `!n` on the pill.

## Commands

```bash
ir add "<what>" --from <person> [--owe] [--task <id>] [--due 3d] [--channel email]
ir sent <id>       # the request went out / you delivered it
ir chase <id>      # you nudged them again
ir got <id> "..."  # the information came back
ir done <id>

ir list [--hot] [--from tobias] [--grep topic] [--json]
ir who             # everything live, grouped by person
ir show <id>       # one item with its full history
ir sweep           # JSON of what needs checking
ir brief           # the context block injected into Claude sessions
ir tui             # full-screen board
```

`--due` takes `3d`, `2w`, `fri`, `tomorrow` or `2026-10-05`. Ids are three
characters; a unique title fragment works anywhere an id does.

### TUI keys

`j`/`k` move · `s` sent · `c` chase · `g` got · `d` done · `b` block ·
`r` reopen · `n` note · `tab` cycle filter · `/` search · `q` quit

## Support mail

`support@movepeople.ch` is reachable only through Thunderbird, and that is a
conclusion from testing, not a preference:

- The Microsoft 365 connector returns FORBIDDEN for it — Klemen's account has no
  delegate access, and no mail addressed to `support@` has reached his own
  mailbox since April 2026.
- `mail.movepeople.ch` runs Dovecot and looks syncable, but it is only the
  priority-10 backup MX. The real MX is `movepeople-ch.mail.protection.outlook.com`,
  so the mailbox lives on Microsoft 365.
- Microsoft 365 answers an IMAP password login with *"Basic authentication is
  disabled"*, so `mbsync`/`offlineimap` cannot log in without an Azure app
  registration.

Thunderbird ships its own Microsoft OAuth client, so it logs in with no admin
grant and no app registration. It runs on a hidden Hyprland workspace, syncing
in the background; `ir-mail` reads what it has downloaded.

```bash
ir-mail search lehmhuus --since 7d       # all terms must appear
ir-mail search creds --from tobias       # narrow by sender
ir-mail search specs --folder sent       # did I actually reply?
ir-mail folders                          # what is available locally
ir-mail status                           # is the store there and fresh
```

`--folder sent` is what makes auto-marking "sent" safe: it is evidence, not
inference.

**`thunderbird/user.js` matters.** IMAP normally keeps headers locally and
fetches bodies on demand — which would leave `ir-mail` reading subject lines and
reporting "no reply found" while the answer sat in the body. The prefs force full
offline download, and switch the store to maildir so messages are one file each
(safe to read while Thunderbird writes). The maildir pref only applies to
accounts created after it is set.

## Claude Code integration

Two pieces, both installed globally so they work in **every** project:

- **`~/.claude/skills/info-reminder`** — how to use the ledger, when to write
  to it unprompted, and the sweep procedure for finding answers that already
  arrived in Outlook, ClickUp or Slack.
- **A `SessionStart` hook** — runs `ir brief` and injects the current state
  plus the usage rules into every session, in every directory. This is what
  stops the ledger going stale.

The hook is deliberately forgiving: if the ledger is missing or corrupt it
prints nothing and exits 0, so a broken file can never stop a session starting.

## Layout

```
bin/ir                      CLI + model (single source of truth)
bin/ir_tui.py               curses board, imports the model from bin/ir
bin/ir-mail                 reads Thunderbird's local store (mbox and maildir)
thunderbird/user.js         forces offline bodies + maildir storage
claude/sweep/               hourly systemd timer, runner and sweep prompt
shell-plugin/               omarchy quickshell bar widget
  Panel.qml                 pill + popup
  Model.js                  derived state, mirrors bin/ir
claude/skill/SKILL.md       global Claude Code skill
claude/hooks/               SessionStart hook and its installer
install.sh
```

`bin/ir` and `shell-plugin/Model.js` implement the same derivation twice, in
two languages. They must agree — if you change what "silent 6d" or "needs
action" means, change both. `ir bar --json` and `Model.counts()` are the
cheapest way to check they still match.
