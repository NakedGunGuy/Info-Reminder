import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar pill + popup for the information ledger.
//
// The pill reads "<waiting on them>/<on you>" with a "!n" tail when something
// needs action. State lives in one JSON file written by the `ir` CLI; this
// widget watches that file, so a change Claude makes in any terminal shows up
// here immediately without a poll.
Panel {
  id: root
  moduleName: "perko.info-reminder"
  ipcTarget: "perko.info-reminder"

  readonly property string ledgerPath: Quickshell.env("HOME") + "/.local/share/info-reminder/ledger.json"
  readonly property string irBin: Quickshell.env("HOME") + "/.local/bin/ir"

  property var items: []
  readonly property var stats: Model.counts(root.items)
  readonly property var rows: Model.flatten(Model.groups(root.items))
  readonly property string pill: Model.pillText(root.items)
  readonly property bool needsAction: root.stats.hot > 0

  // Applying a change shells out to the same CLI everything else uses, so the
  // popup can never drift from the CLI's idea of a state transition.
  //
  // execArgv, not bar.run: ids come out of a JSON file a human can edit, and
  // bar.run would hand them to `bash -lc` where a stray `$(...)` would run.
  function apply(action, id) {
    if (!id) return
    Util.execArgv([root.irBin, action, id])
  }

  function openBoard() {
    Util.execArgv(["omarchy-launch-terminal", "--app-id=info-ledger",
                   "--title=Information ledger", "--", root.irBin, "tui"])
    root.close()
  }

  property FileView ledgerFile: FileView {
    path: root.ledgerPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.items = Model.parseLedger(text())
    onLoadFailed: root.items = []
  }

  // The first read can race shell startup; one delayed reload self-corrects
  // and is a no-op when the first read already succeeded.
  Timer {
    interval: 1500
    running: true
    onTriggered: ledgerFile.reload()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Glyph is nf-fa-tasks; the pill text follows it when there is anything live.
    text: root.pill === "" ? "\uf0ae" : "\uf0ae " + root.pill
    slotSize: root.pill === "" ? Style.bar.iconSlot : Style.bar.iconSlot * 2.2
    active: root.needsAction
    tooltipText: root.pill === ""
      ? "Information ledger — all clear"
      : root.stats.theirs + " waiting on them, " + root.stats.mine + " on you"
        + (root.needsAction ? ", " + root.stats.hot + " need action" : "")

    onPressed: function (b) {
      if (b === Qt.RightButton) root.openBoard()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(430))
    contentHeight: panel.fittedContentHeight(header.implicitHeight + list.contentHeight + footer.implicitHeight + Style.space(28))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }

      Column {
        anchors.fill: parent
        spacing: Style.space(10)

        // ---------- header ----------
        Item {
          id: header
          width: parent.width
          implicitHeight: Math.max(title.implicitHeight, summary.implicitHeight)

          Text {
            id: title
            text: "Information ledger"
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            id: summary
            text: root.stats.live === 0
              ? "all clear"
              : root.stats.theirs + " on them  ·  " + root.stats.mine + " on you"
                + (root.needsAction ? "  ·  " + root.stats.hot + " hot" : "")
            color: root.needsAction ? root.bar.urgent : Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        PanelSeparator { width: parent.width }

        // ---------- rows ----------
        ListView {
          id: list
          width: parent.width
          height: Math.min(contentHeight, Style.space(420))
          clip: true
          spacing: Style.space(2)
          boundsBehavior: Flickable.StopAtBounds
          model: root.rows

          delegate: Loader {
            required property var modelData
            width: list.width
            sourceComponent: modelData.kind === "header" ? headerRow : itemRow
            onLoaded: item.entry = modelData
          }
        }

        Text {
          visible: root.rows.length === 0
          width: parent.width
          text: "Nothing outstanding. Nobody owes you anything."
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          horizontalAlignment: Text.AlignHCenter
        }

        PanelSeparator { width: parent.width }

        // ---------- footer ----------
        Item {
          id: footer
          width: parent.width
          implicitHeight: Style.space(24)

          Text {
            text: "right-click the pill, or click here, for the full board"
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.openBoard()
            }
          }
        }
      }
    }
  }

  // ---------- delegates ----------

  Component {
    id: headerRow

    Item {
      property var entry: ({})
      width: ListView.view ? ListView.view.width : 0
      implicitHeight: Style.space(26)

      Text {
        text: (entry.title || "") + "  " + (entry.count || 0)
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(4)
      }
    }
  }

  Component {
    id: itemRow

    CursorSurface {
      id: rowSurface
      property var entry: ({})
      readonly property var rowActions: entry.id ? Model.actions(entry) : []

      width: ListView.view ? ListView.view.width : 0
      implicitHeight: rowColumn.implicitHeight + Style.space(10)

      Column {
        id: rowColumn
        anchors.left: parent.left
        anchors.right: actionRow.left
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(4)
        spacing: Style.space(2)

        Text {
          width: parent.width
          text: (entry.mark || "") + "  " + (entry.title || "")
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          text: {
            var bits = [entry.label || ""]
            if (entry.chases) bits.push("chased " + entry.chases + "x")
            if (entry.state === "pending" && entry.quiet !== null && entry.quiet !== undefined)
              bits.push("quiet " + entry.quiet + "d")
            if (entry.due) bits.push("due " + entry.due)
            if (entry.task) bits.push("CU-" + entry.task)
            return bits.join("  ·  ")
          }
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }

        // The named pieces still outstanding — this is what you paste into a
        // chase, so it earns a line of its own rather than hiding behind a count.
        Text {
          visible: (entry.missing || []).length > 0 && (entry.progress || "") !== ""
          width: parent.width
          text: "still need: " + (entry.missing || []).join(", ")
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }

        Text {
          visible: !!entry.attention
          width: parent.width
          text: "→ " + (entry.attention || "")
          color: root.bar ? root.bar.urgent : Color.urgent
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }
      }

      Row {
        id: actionRow
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.rightMargin: Style.space(4)
        spacing: Style.space(4)

        Repeater {
          model: rowSurface.rowActions

          PanelActionButton {
            required property var modelData
            iconText: modelData.icon
            tooltipText: modelData.tip
            foreground: Color.popups.text
            onClicked: root.apply(modelData.key, rowSurface.entry.id)
          }
        }
      }
    }
  }
}
