"""Full-screen board for the information ledger.

Loads the model straight out of the `ir` script next to this file, so the
board, the CLI and the bar can never disagree about what "silent 6d" means.
"""

from __future__ import annotations

import curses
import importlib.machinery
import importlib.util
import os

_HERE = os.path.dirname(os.path.realpath(__file__))
_loader = importlib.machinery.SourceFileLoader("irlib", os.path.join(_HERE, "ir"))
_spec = importlib.util.spec_from_loader("irlib", _loader)
ir = importlib.util.module_from_spec(_spec)
_loader.exec_module(ir)

FILTERS = [
    ("live", "open items", lambda e: e["live"]),
    ("hot", "needs action", lambda e: bool(e["attention"])),
    ("them", "waiting on them", lambda e: e["live"] and e["dir"] == "in" and e["state"] == "pending"),
    ("you", "on you", lambda e: e["live"] and (
        (e["dir"] == "in" and e["state"] in ("open", "answered"))
        or (e["dir"] == "out" and e["state"] in ("open", "pending")))),
    ("all", "everything", lambda e: True),
]

MARK = {
    "open": "[ ]", "pending": "[~]", "answered": "[!]",
    "done": "[x]", "blocked": "[/]", "dropped": "[-]",
}

HELP = "j/k move  s sent  c chase  g got  d done  b block  r reopen  n note  tab filter  / search  q quit"


class Board:
    def __init__(self, path):
        self.path = path
        self.filter = 0
        self.cursor = 0
        self.search = ""
        self.msg = ""
        self.mtime = 0.0
        self.rows: list[dict] = []
        self.reload()

    # -- data ------------------------------------------------------------
    def reload(self):
        data = ir.load()
        rows = [ir.enrich(i) for i in ir.select(data, _AllArgs())]
        pred = FILTERS[self.filter][2]
        rows = [r for r in rows if pred(r)]
        if self.search:
            q = self.search.lower()
            rows = [r for r in rows if q in r["title"].lower() or q in (r["person"] or "").lower()]
        self.rows = rows
        self.cursor = max(0, min(self.cursor, len(rows) - 1))
        try:
            self.mtime = os.path.getmtime(self.path)
        except OSError:
            self.mtime = 0.0

    def changed_on_disk(self) -> bool:
        try:
            return os.path.getmtime(self.path) != self.mtime
        except OSError:
            return False

    def current(self):
        return self.rows[self.cursor] if self.rows else None

    def act(self, fn_name, note=""):
        """Apply a state change through the same code path the CLI uses."""
        cur = self.current()
        if not cur:
            return
        data = ir.load()
        item = ir.find(data, cur["id"])
        if fn_name == "chase":
            if item["state"] == "open":
                item["sent_at"] = ir.iso(ir.now())
            item["state"] = "pending"
            item.setdefault("chases", []).append(ir.iso(ir.now()))
            ir.note(item, note)
        elif fn_name == "sent":
            ir._touch(item, "pending", "sent_at", note)
        elif fn_name == "got":
            ir._touch(item, "answered", "got_at", note)
        elif fn_name == "done":
            ir._touch(item, "done", None, note)
        elif fn_name == "block":
            ir._touch(item, "blocked", None, note)
        elif fn_name == "drop":
            ir._touch(item, "dropped", None, note)
        elif fn_name == "reopen":
            item["state"] = "pending" if item.get("sent_at") else "open"
            item["closed_at"] = None
            ir.note(item, note)
        elif fn_name == "note":
            ir.note(item, note)
        ir.save(data)
        self.msg = f"{fn_name} → {item['id']}"
        self.reload()


class _AllArgs:
    """Selects everything; the board does its own filtering."""
    all = True
    state = person = dir = tag = project = task = grep = None
    hot = False


# -- drawing -------------------------------------------------------------

def draw(stdscr, board: Board):
    stdscr.erase()
    h, w = stdscr.getmaxyx()

    key, desc, _ = FILTERS[board.filter]
    counts = ir.counts(ir.load()["items"])
    title = " INFORMATION LEDGER "
    stdscr.addstr(0, 0, title[: w - 1], curses.A_REVERSE | curses.A_BOLD)
    status = f"{counts['theirs']} on them · {counts['mine']} on you · {counts['hot']} need action"
    if len(title) + len(status) + 2 < w:
        stdscr.addstr(0, w - len(status) - 1, status, curses.A_REVERSE)

    sub = f" view: {desc}"
    if board.search:
        sub += f"   search: {board.search!r}"
    if board.msg:
        sub += f"   {board.msg}"
    stdscr.addstr(1, 0, sub[: w - 1], curses.A_DIM)

    top = 3
    body = h - top - 2
    per_row = 2
    visible = max(1, body // per_row)
    start = max(0, board.cursor - visible + 1) if board.cursor >= visible else 0

    if not board.rows:
        stdscr.addstr(top, 2, "nothing here.", curses.A_DIM)

    for idx, row in enumerate(board.rows[start : start + visible]):
        y = top + idx * per_row
        if y + 1 >= h - 1:
            break
        selected = (start + idx) == board.cursor
        attr = curses.A_REVERSE if selected else curses.A_NORMAL

        colour = curses.color_pair({
            "open": 3, "pending": 4, "answered": 2,
            "blocked": 1, "done": 5, "dropped": 5,
        }[row["state"]])

        badge = f"[{row['project']}] " if row.get("project") else ""
        head = f" {MARK[row['state']]} {row['id']}  {badge}{row['title']}"
        stdscr.addstr(y, 0, head[: w - 1].ljust(w - 1) if selected else head[: w - 1],
                      attr | (0 if selected else colour))

        bits = [row["label"]]
        if row["chase_count"]:
            bits.append(f"chased {row['chase_count']}x")
        if row["state"] == "pending" and row["quiet_days"] is not None:
            bits.append(f"quiet {row['quiet_days']}d")
        if row["due"]:
            bits.append(f"due {row['due']}")
        if row["task"]:
            bits.append(f"CU-{row['task']}")
        if row["channel"]:
            bits.append(row["channel"])
        line = "      " + " · ".join(bits)
        stdscr.addstr(y + 1, 0, line[: w - 1], curses.A_DIM)

        # Always drawn, selected or not: the reason an item is shouting is the
        # single most useful thing on the row. The meta line sits outside the
        # selection highlight, so it stays legible either way.
        if row["attention"]:
            tail = f"  → {row['attention']}"
            x = min(len(line) + 2, w - len(tail) - 2)
            if x > 0:
                stdscr.addstr(y + 1, x, tail[: w - x - 1], curses.color_pair(1) | curses.A_BOLD)

    stdscr.addstr(h - 1, 0, HELP[: w - 1], curses.A_DIM)
    stdscr.refresh()


def prompt(stdscr, label: str) -> str:
    h, w = stdscr.getmaxyx()
    curses.echo()
    curses.curs_set(1)
    stdscr.addstr(h - 1, 0, " " * (w - 1))
    stdscr.addstr(h - 1, 0, label)
    stdscr.refresh()
    try:
        out = stdscr.getstr(h - 1, len(label), w - len(label) - 2).decode("utf-8", "replace")
    except Exception:
        out = ""
    curses.noecho()
    curses.curs_set(0)
    return out.strip()


def loop(stdscr, path):
    curses.curs_set(0)
    curses.use_default_colors()
    for i, fg in enumerate([curses.COLOR_RED, curses.COLOR_GREEN, curses.COLOR_YELLOW,
                            curses.COLOR_BLUE, curses.COLOR_WHITE], start=1):
        curses.init_pair(i, fg, -1)
    stdscr.timeout(1000)  # so an edit from Claude shows up within a second

    board = Board(path)
    while True:
        draw(stdscr, board)
        try:
            ch = stdscr.getch()
        except KeyboardInterrupt:
            return
        if ch == -1:
            if board.changed_on_disk():
                board.msg = "reloaded"
                board.reload()
            continue

        board.msg = ""
        if ch in (ord("q"), 27):
            return
        elif ch in (ord("j"), curses.KEY_DOWN):
            board.cursor = min(board.cursor + 1, max(0, len(board.rows) - 1))
        elif ch in (ord("k"), curses.KEY_UP):
            board.cursor = max(board.cursor - 1, 0)
        elif ch == ord("g"):
            board.act("got", prompt(stdscr, "got it — note: "))
        elif ch == ord("s"):
            board.act("sent", prompt(stdscr, "sent — note: "))
        elif ch == ord("c"):
            board.act("chase", prompt(stdscr, "chase — note: "))
        elif ch == ord("d"):
            board.act("done")
        elif ch == ord("b"):
            board.act("block", prompt(stdscr, "blocked by: "))
        elif ch == ord("x"):
            board.act("drop")
        elif ch == ord("r"):
            board.act("reopen")
        elif ch == ord("n"):
            text = prompt(stdscr, "note: ")
            if text:
                board.act("note", text)
        elif ch == ord("\t"):
            board.filter = (board.filter + 1) % len(FILTERS)
            board.cursor = 0
            board.reload()
        elif ch == ord("/"):
            board.search = prompt(stdscr, "search: ")
            board.cursor = 0
            board.reload()
        elif ch in (curses.KEY_RESIZE, ord("R")):
            board.reload()


def run(path):
    curses.wrapper(loop, path)
    return 0
