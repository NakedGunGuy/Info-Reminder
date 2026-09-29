---
name: info-reminder
description: Track what Klemen asked people for, what he owes, and what came back, using the `ir` CLI. Use whenever he mentions needing something from someone (Tobias, a client, a colleague), owing someone something, chasing a reply, or receiving information — and before suggesting he ask for something, to check whether he already did. Also covers the sweep that scans Outlook, ClickUp and Slack for answers that already arrived.
---

# info-reminder

Klemen juggles support mail, ClickUp tasks and a boss (Tobias) he has to chase.
The costly failures are not forgetting a task — they are:

- asking someone for the same thing twice
- chasing someone who already answered three days ago
- forgetting he owes someone something until they ask again
- not knowing whether a request ever actually left his hands

The ledger exists to answer exactly those. **Keep it current without being
asked.** It is worth nothing if it only gets updated when he remembers to.

## The model

Every item is one piece of information moving between Klemen and one person.

| Field | Meaning |
|---|---|
| `dir` | `in` = they owe him · `out` = he owes them |
| `state` | `open` → `pending` → `answered` → `done` (plus `blocked`, `dropped`) |
| `person` | who the other side is |
| `task` | ClickUp task id, when there is one |
| `thread` | mail message-id, Slack permalink, any URL |
| `due` | a date it is needed by |
| `nudge` | days of silence before it starts asking to be chased (default 3) |

State reads differently by direction, which the CLI prints for you:

| state | `dir: in` | `dir: out` |
|---|---|---|
| `open` | not asked yet | he owes it, not sent |
| `pending` | waiting on them | sent to them |
| `answered` | they answered — review and close | delivered |

An item raises a flag on its own when it is overdue, when it has been silent
past its `nudge` window, when an answer is sitting unreviewed, or when it was
never actually asked. `ir list --hot` is that set.

## Checklists — the important part

Most requests are not one fact. "Server access" is really host, user, password,
database name, database password. People reply with three of the five and the
other two rot silently for a week.

So name the pieces up front:

```bash
ir add "Server access for Lehmhuus staging" --from tobias \
   --need "FTP host" --need "FTP user" --need "FTP password" \
   --need "DB name" --need "DB password" --sent
```

Then tick them as they land, one at a time:

```bash
ir tick <id> "FTP host" --value "ftp.lehmhuus.ch"
ir tick <id> 3 --value "stored in pass"        # by number works too
ir untick <id> "DB name"                       # got it wrong / it was incomplete
```

The item shows `waiting on tobias (2/5)` and flags itself as
`partial — missing 3 of 5`. When the last piece is ticked it flips to
"they answered" by itself — never call `ir got` on an item that has a checklist.

`ir missing` lists every part-delivered item piece by piece. `ir chase-text <id>`
drafts the follow-up:

> Thanks for FTP host and FTP user.
>
> Still outstanding:
>   - FTP password
>   - DB name
>   - DB password

**Add a checklist whenever the ask has more than one part.** It is what turns
"did they answer?" — a guess — into "which of these five did they send?", which
is checkable, and it is what makes the automated sweep safe.

## Commands

```bash
ir add "<what>" --from <person> [--owe] [--task <id>] [--due 3d] [--channel email] [--note "..."]
ir sent <id> [note]      # the request went out / he delivered it
ir chase <id> [note]     # he nudged them again
ir got <id> [note]       # the information came back
ir done <id>             # closed
ir block <id> [why]      # stuck on something else
ir note <id> <text>      # append a note
ir set <id> --due fri --task 86c6xxxxx --person tobias

ir list [--hot] [--from tobias] [--dir in] [--grep topic] [--json]
ir who                   # everything live, grouped by person
ir show <id>             # one item in full, with history
ir sweep [--all]         # JSON of what needs checking — the input to a sweep
```

`--due` takes `3d`, `2w`, `fri`, `tomorrow` or `2026-10-05`. Ids are 3
characters; a unique title fragment works anywhere an id does.

## When to reach for it

**Write to it as a side effect of normal conversation** — do not announce it,
do not ask permission for a plain add or state change, just do it and mention
it in a clause.

| He says something like | Do |
|---|---|
| "I need the API creds from Tobias" | `ir add "API creds" --from tobias` |
| "I asked Tobias for the creds yesterday" | `ir add ... --sent` |
| "I pinged him again" | `ir chase <id>` |
| "Tobias sent the creds" / he pastes them | `ir got <id> "<what arrived>"` |
| "I still owe Dani the specs" | `ir add "specs" --owe --from dani` |
| "that's sorted" | `ir done <id>` |

**Read from it before you give advice.** Before suggesting he ask anyone for
anything, run `ir list --grep <topic>`. If there is already a `pending` item,
say so — "you asked Tobias for that 6 days ago, never chased" is the useful
answer, not "you should ask Tobias."

When he opens a session and something is hot, lead with it in one line.
Do not recite the whole board; he can see it in the bar.

## The sweep

`ir sweep` prints the items that want checking. For each one, look for an
answer that already arrived and that he missed:

1. `ir sweep` for the candidates.
2. For each, search where the answer would have landed:
   - **Support mail** lives in a local Maildir at
     `~/.local/share/info-reminder/mail/support/` — grep it directly. The M365
     connector CANNOT read `support@movepeople.ch`; do not try.
   - `outlook_email_search` for Klemen's own mailbox
   - `clickup_get_task_comments` when the item carries a `task`
   - **BugHerd** notifications arrive in Klemen's own Outlook (not support@):
     `outlook_email_search` with `sender: bugherd.com`. The status in the mail is
     a snapshot from when it was sent, not the current state — good evidence
     something was raised, poor evidence it is still open.
   - `slack_search_public_and_private` / `teams_list_chats` for a DM reply
3. Tick what you can evidence, piece by piece, recording where you saw it:
   `ir tick <id> "<piece>" --value "<what arrived>" --auto "<sender, date, quote>"`
   **A reply is not an answer.** "I'll look tomorrow" is not the password.
   Tick only when the message contains the actual thing.
4. Items genuinely still silent → offer a drafted chase, and record
   `ir chase <id>` only once the nudge is actually sent.

Items where the ball is on him are not sweep material — those are just work.

## Rules

- **Every automated change is auditable.** Anything ticked or marked by the
  hourly sweep carries `[auto]` plus its evidence. `ir audit --since 1d` shows
  them; `ir untick` / `ir reopen` undo one. When you auto-mark, write evidence
  someone could actually go and verify.
- **Never hand-edit `ledger.json`.** Always go through `ir`. The bar plugin
  and the TUI read derived state that the CLI owns; hand edits drift.
- **Never mark `got` on inference.** Only on something he pasted, or a message
  you actually read that carries the information.
- One item per thing needed, not per conversation. If he needs three files
  from one person, that is one item unless they arrive separately.
- Record the evidence: `ir got <id> "creds in CU comment 2026-09-29"` is worth
  far more later than a bare state change.
- When you add an item during work in a repo, the project is captured
  automatically from the working directory — do not pass `--project` by hand.
