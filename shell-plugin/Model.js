// Derived state for the information ledger, mirroring bin/ir's Python model.
// Keep the two in step: the pill, the CLI and the TUI must never disagree
// about what "silent 6d" or "needs action" means.
.pragma library

var DEFAULT_NUDGE = 3
var CLOSED = ["done", "dropped"]

function parseLedger(text) {
  if (!text) return []
  try {
    var data = JSON.parse(text)
    return (data && data.items) ? data.items : []
  } catch (e) {
    return []
  }
}

// ---- checklist ---------------------------------------------------------
// An item is often several named pieces, not one fact. Partial delivery is the
// common case and the one that rots silently, so it gets its own visible state.

function needsOf(item) { return item.needs || [] }
function needsGot(item) { return needsOf(item).filter(function (n) { return n.got }) }
function needsMissing(item) { return needsOf(item).filter(function (n) { return !n.got }) }

function progress(item) {
  var total = needsOf(item).length
  return total ? (needsGot(item).length + "/" + total) : ""
}

function isClosed(item) {
  return CLOSED.indexOf(item.state) !== -1
}

function toDate(iso) {
  if (!iso) return null
  var d = new Date(iso)
  return isNaN(d.getTime()) ? null : d
}

function daysSince(iso) {
  var d = toDate(iso)
  if (!d) return null
  return Math.floor((Date.now() - d.getTime()) / 86400000)
}

// Whole days from today to a YYYY-MM-DD due date; negative once overdue.
function daysUntilDue(due) {
  if (!due) return null
  var parts = due.split("-")
  if (parts.length !== 3) return null
  var target = new Date(+parts[0], +parts[1] - 1, +parts[2])
  var today = new Date()
  today = new Date(today.getFullYear(), today.getMonth(), today.getDate())
  return Math.round((target.getTime() - today.getTime()) / 86400000)
}

function lastContact(item) {
  var stamps = []
  if (item.sent_at) stamps.push(toDate(item.sent_at))
  var chases = item.chases || []
  for (var i = 0; i < chases.length; i++) {
    var c = toDate(chases[i])
    if (c) stamps.push(c)
  }
  stamps = stamps.filter(function (s) { return !!s })
  if (!stamps.length) return null
  return stamps.reduce(function (a, b) { return a > b ? a : b })
}

function quietDays(item) {
  var lc = lastContact(item)
  if (!lc) return null
  return Math.floor((Date.now() - lc.getTime()) / 86400000)
}

// Why this item wants a human right now — or "" if it can wait.
function attention(item) {
  if (isClosed(item)) return ""

  var due = daysUntilDue(item.due)
  if (due !== null) {
    if (due < 0) return "overdue " + (-due) + "d"
    if (due === 0) return "due today"
  }

  if (item.state === "answered") return "answer in — close it out"

  var missing = needsMissing(item)
  if (missing.length && needsGot(item).length)
    return "partial — missing " + missing.length + " of " + needsOf(item).length

  if (item.state === "open") {
    var age = daysSince(item.created)
    if (age !== null && age >= 1) return item.dir === "out" ? "you owe this" : "never asked"
    return ""
  }

  if (item.state === "pending") {
    var quiet = quietDays(item)
    var nudge = item.nudge || DEFAULT_NUDGE
    if (quiet !== null && quiet >= nudge) return "silent " + quiet + "d"
  }

  return ""
}

function label(item) {
  var who = item.person || "someone"
  var prog = progress(item)
  var suffix = prog ? (" (" + prog + ")") : ""
  if (item.state === "done") return "done"
  if (item.state === "dropped") return "dropped"
  if (item.state === "blocked") return "blocked"
  if (item.dir === "in") {
    if (item.state === "open") return "not asked yet" + suffix
    if (item.state === "pending") return "waiting on " + who + suffix
    if (item.state === "answered") return "they answered" + suffix
  } else {
    if (item.state === "open") return "you owe " + who + suffix
    if (item.state === "pending") return "sent to " + who + suffix
    if (item.state === "answered") return "delivered" + suffix
  }
  return item.state
}

function mark(item) {
  return ({
    open: "[ ]", pending: "[~]", answered: "[!]",
    done: "[x]", blocked: "[/]", dropped: "[-]"
  })[item.state] || "[ ]"
}

// The ball is in my court: nothing asked yet, an answer to review, or
// something I still owe someone.
function onMe(item) {
  if (isClosed(item)) return false
  if (item.dir === "in") return item.state === "open" || item.state === "answered"
  return item.state === "open" || item.state === "pending"
}

function onThem(item) {
  return !isClosed(item) && item.dir === "in" && item.state === "pending"
}

function counts(items) {
  var n = { theirs: 0, mine: 0, hot: 0, blocked: 0, live: 0 }
  for (var i = 0; i < items.length; i++) {
    var it = items[i]
    if (isClosed(it)) continue
    n.live++
    if (onThem(it)) n.theirs++
    if (onMe(it)) n.mine++
    if (attention(it)) n.hot++
    if (it.state === "blocked") n.blocked++
  }
  return n
}

// Short text for the bar pill: "themCount/mineCount" plus a bang for hot.
function pillText(items) {
  var n = counts(items)
  if (!n.live) return ""
  var s = n.theirs + "/" + n.mine
  if (n.hot) s += " !" + n.hot
  return s
}

function decorate(item) {
  return {
    id: item.id,
    title: item.title || "(untitled)",
    dir: item.dir,
    person: item.person || "",
    channel: item.channel || "",
    state: item.state,
    task: item.task || "",
    due: item.due || "",
    project: item.project || "",
    mark: mark(item),
    label: label(item),
    attention: attention(item),
    quiet: quietDays(item),
    chases: (item.chases || []).length,
    progress: progress(item),
    missing: needsMissing(item).map(function (n) { return n.label })
  }
}

// Sorted so the things shouting loudest sit at the top of the popup.
function sortRows(rows) {
  return rows.sort(function (a, b) {
    var ah = a.attention ? 0 : 1, bh = b.attention ? 0 : 1
    if (ah !== bh) return ah - bh
    var aq = a.quiet === null ? -1 : a.quiet
    var bq = b.quiet === null ? -1 : b.quiet
    if (aq !== bq) return bq - aq
    return a.title.toLowerCase() < b.title.toLowerCase() ? -1 : 1
  })
}

// Grouped for the popup: what I have to move first, then what I am waiting on.
function groups(items) {
  var mine = [], theirs = [], blocked = []
  for (var i = 0; i < items.length; i++) {
    var it = items[i]
    if (isClosed(it)) continue
    if (it.state === "blocked") blocked.push(decorate(it))
    else if (onMe(it)) mine.push(decorate(it))
    else if (onThem(it)) theirs.push(decorate(it))
  }
  var out = []
  if (mine.length) out.push({ title: "ON YOU", rows: sortRows(mine) })
  if (theirs.length) out.push({ title: "WAITING ON THEM", rows: sortRows(theirs) })
  if (blocked.length) out.push({ title: "BLOCKED", rows: sortRows(blocked) })
  return out
}

// Inline actions offered per row, in the order they make sense.
// Glyphs are written as escapes so the file stays plain ASCII.
function actions(row) {
  var SEND = "\uf1d8"     // paper-plane
  var BELL = "\uf0f3"     // bell
  var CHECK = "\uf00c"    // check
  var CLOSE = "\uf058"    // check-circle
  var REDO = "\uf021"     // refresh

  if (row.state === "blocked") return [{ key: "reopen", icon: REDO, tip: "Unblock" }]
  if (row.dir === "in") {
    if (row.state === "open") return [{ key: "sent", icon: SEND, tip: "Mark asked" }]
    if (row.state === "pending") return [
      { key: "chase", icon: BELL, tip: "Record a nudge" },
      { key: "got", icon: CHECK, tip: "Answer received" }
    ]
    if (row.state === "answered") return [{ key: "done", icon: CLOSE, tip: "Close it" }]
  } else {
    if (row.state === "open") return [{ key: "sent", icon: SEND, tip: "Mark sent" }]
    return [{ key: "done", icon: CLOSE, tip: "Close it" }]
  }
  return []
}

// Groups flattened into one list so the popup can scroll a single ListView.
function flatten(groupList) {
  var out = []
  for (var g = 0; g < groupList.length; g++) {
    out.push({ kind: "header", title: groupList[g].title, count: groupList[g].rows.length })
    var rows = groupList[g].rows
    for (var r = 0; r < rows.length; r++) {
      var row = rows[r]
      row.kind = "row"
      out.push(row)
    }
  }
  return out
}
