import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Cordelia in the bar: one icon that says whether your agent's memory is in
// step, and a panel with the switch, what syncs, relays, your devices and
// conflicts. What Cordelia does only at a terminal (the recovery phrase,
// adding and removing a device, clearing a notice) is shown as a command to
// copy, and is never run from here.
Panel {
  id: root
  moduleName: "seeddrill.cordelia"
  ipcTarget: "seeddrill.cordelia"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // The level is the node's. Red is what to act on now: it is drawn as
  // attention always was, and so is the state "attention" where the node
  // gives no level. Amber is what to know of.
  readonly property bool attention: cordelia.level === "red"
    || (cordelia.level === "" && cordelia.state === "attention")
  readonly property bool amber: cordelia.level === "amber"
  // A theme has a colour for what is urgent and none for amber. Amber is that
  // colour brought halfway to the text around it: milder than red, and not
  // the colour of memory in step. It has a glyph of its own as well.
  readonly property color amberColor: mix(urgent, foreground)
  readonly property color barAmberColor: mix(urgent, barForeground)
  readonly property bool quiet: !attention && !amber && (cordelia.state === "off" || cordelia.state === "stopped"
    || cordelia.state === "offline" || cordelia.state === "uninitialised")
  readonly property color barIconColor: amber ? barAmberColor
    : (quiet ? Qt.darker(barForeground, 1.55) : barForeground)
  readonly property color iconColor: attention ? urgent : (amber ? amberColor : (quiet ? dim : foreground))

  // What the icon is drawn from: the level where one holds, and the state
  // where none does.
  readonly property string sign: attention ? "red" : (amber ? "amber" : cordelia.state)

  // Cordelia's own mark (Mark.qml) while memory is in step, and, dimmed,
  // where nothing is being passed on: off, stopped, not set up. A level and
  // the passing states have a Nerd Font glyph each, the same ones `cordelia
  // status --waybar` prints. The Mac menu bar app draws the same.
  readonly property bool showsMark: glyph(sign) === ""

  function glyph(of) {
    if (of === "red") return String.fromCodePoint(0xF0026)     // alert
    if (of === "amber") return String.fromCodePoint(0xF002A)   // alert, in outline
    if (of === "syncing") return String.fromCodePoint(0xF04E6) // sync
    if (of === "offline") return String.fromCodePoint(0xF0164) // cloud off
    return ""                                                   // the mark
  }

  // The colour halfway between two.
  function mix(a, b) {
    return Qt.rgba((a.r + b.r) / 2, (a.g + b.g) / 2, (a.b + b.b) / 2, 1)
  }

  function headline() {
    if (!cordelia.loaded) return "Checking…"
    if (!cordelia.installed) return "Not set up on this machine"
    return cordelia.sentence(cordelia.summary)
  }

  function shortKey(key) {
    var k = cordelia.plain(key)
    return k.length > 26 ? k.substring(0, 18) + "…" + k.substring(k.length - 6) : k
  }

  function duration(secs) {
    var s = Number(secs || 0)
    if (s < 60) return s + "s"
    if (s < 3600) return Math.floor(s / 60) + "m"
    if (s < 86400) return Math.floor(s / 3600) + "h " + Math.floor((s % 3600) / 60) + "m"
    return Math.floor(s / 86400) + "d"
  }

  function fileName(path) {
    var parts = String(path || "").split("/")
    return parts[parts.length - 1]
  }

  // `1.5 MB`, `12.0 KB`, as `cordelia stats` writes a size.
  function bytes(n) {
    var b = Number(n || 0)
    return b > 1048576 ? (b / 1048576).toFixed(1) + " MB" : (b / 1024).toFixed(1) + " KB"
  }

  // How much memory this device stores: the size of its encrypted content.
  // "" where `cordelia stats` was not run or did not say (it is run only
  // beside a running node of the command's own version), or says it of
  // something other than a person's device.
  function stored() {
    var s = cordelia.stats
    if (s === null || cordelia.role !== "personal" || !cordelia.running || cordelia.otherVersion) return ""
    if (typeof s.content_bytes_stored !== "number") return ""
    return bytes(s.content_bytes_stored) + " of memory stored"
  }

  // The version of Cordelia and of this panel. The command's version and the
  // running node's are both said only where they differ: the head of the
  // panel then says to restart the node.
  function versions() {
    var parts = []
    var command = cordelia.plain(cordelia.version)
    var node = cordelia.plain(cordelia.nodeVersion)
    if (command !== "" && (node === "" || node === command)) {
      parts.push("Cordelia " + command)
    } else {
      if (command !== "") parts.push("command " + command)
      if (node !== "") parts.push("node " + node)
    }
    if (cordelia.pluginVersion !== "") parts.push("panel " + cordelia.plain(cordelia.pluginVersion))
    return parts.join(" · ")
  }

  // The foot of the panel, in one line.
  function foot() {
    return cordelia.joined([versions(), stored()], " · ")
  }

  // A node goes on running the version it was started as until it is
  // restarted.
  function versionSays() {
    var node = cordelia.nodeVersion === "" ? "The node is older than the command, and"
      : "The node is version " + cordelia.plain(cordelia.nodeVersion) + " and"
    return node + " the command is version " + cordelia.plain(cordelia.version) + ". Restart the node."
  }

  function homeSays() {
    var about = "What Claude remembers outside any project"
    if (!cordelia.home) return cordelia.homeAvailable ? "Your other devices sync it" : about
    var says = cordelia.homeEntry !== null ? cordelia.folderSays(cordelia.homeEntry) : ""
    if (says !== "") return says
    if (cordelia.staysHere) return "Stays on this machine"
    return cordelia.homeName !== "~" ? "Syncs as " + cordelia.plain(cordelia.homeName) : about
  }

  function folderDetail(entry) {
    var says = cordelia.folderSays(entry)
    if (says !== "") return says
    return entry.cwd ? cordelia.plain(entry.project) : (cordelia.staysHere ? "Mapped" : "Syncing")
  }

  // The notice of the folders that stopped syncing when only mapped folders
  // came to sync, in a few words. The folders are the node's, each as a row.
  function noticeSays() {
    var says = []
    if (cordelia.stoppedSyncing.length > 0) {
      says.push((cordelia.noticeDay !== "" ? "Since " + cordelia.plain(cordelia.noticeDay) + " only" : "Only")
        + " mapped folders sync. These synced before. Turn on the ones you want to keep.")
    } else if (cordelia.noticeNotKnown) {
      says.push("Folders stopped syncing: only mapped folders sync now.")
    } else {
      says.push("Every folder that stopped syncing is mapped again.")
    }
    if (cordelia.noticeNotKnown) says.push("Not all that stopped is known.")
    if (cordelia.stoppedSyncing.length > 0 && !cordelia.syncOn) says.push("Turn sync on to map one.")
    return says.join(" ")
  }

  // Where a relay stands: whether it is connected, whether it holds the
  // latest change of this person's devices, and what it last refused for room.
  function relaySays(relay) {
    var says = []
    if (relay.connected) says.push(typeof relay.secs === "number" ? "Connected " + duration(relay.secs) : "Connected")
    else if (relay.state === "") says.push("Not connected")
    else says.push(cordelia.sentence(relay.state) + (relay.error !== "" ? ": " + relay.error : ""))
    if (relay.latest === "yes") says.push("holds the latest change")
    else if (relay.latest === "no") says.push("does not hold the latest change yet")
    else if (relay.latest === "unknown") says.push("has not said whether it holds the latest change")
    if (relay.noRoom !== "") says.push(relay.noRoom)
    return says.join(" · ")
  }

  // What a device with no recovery phrase says of itself, in the node's own
  // few words: "not added yet" after an upgrade, "no recovery phrase yet" on
  // a new install.
  function noPhraseSays() {
    var few = cordelia.person !== null && cordelia.person.short ? cordelia.person.short : cordelia.summary
    return cordelia.sentence(few) + ". Memory stays on this machine. To go on, run one of these in a terminal:"
  }

  // Why this device cannot go on, where it cannot, as the node says it.
  function cannotGoOn() {
    return cordelia.person !== null && !cordelia.noPhrase ? cordelia.whole(cordelia.person.cannot_go_on) : ""
  }

  function deviceName(device) {
    var label = cordelia.plain(device.label)
    return label !== "" ? label : shortKey(device.key)
  }

  function addedFrom(device) {
    var by = cordelia.record(device.by)
    var from = by !== null ? cordelia.plain(by.label) : ""
    return from !== "" ? "added from " + from : ""
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    if (panelFlick) panelFlick.contentY = 0
    cordelia.panelOpened()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Service {
    id: cordelia
    settings: root.settings
    panelOpen: root.opened
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { cordelia.refresh(); return "ok" }
    function status(): string { return cordelia.state + ": " + cordelia.summary }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.glyph(root.sign)
    iconComponent: root.showsMark ? barMark : null
    foreground: root.barIconColor
    // The bar highlights red, and never amber.
    active: root.attention
    tooltipText: cordelia.installed ? "Cordelia: " + cordelia.plain(cordelia.summary) : "Cordelia"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) cordelia.refresh()
      else root.toggle()
    }
  }

  Component {
    id: barMark
    Mark { color: root.barIconColor }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") cordelia.refresh()
        else if (t === "s" || t === "S") cordelia.toggleSync()
        else if (t === "c" || t === "C") cordelia.copyKey()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            id: hero
            width: parent.width
            title: "Cordelia"
            // Where anything holds, it is listed beneath, and its first line
            // is what the summary says.
            meta: cordelia.holds.length > 0 ? "" : root.headline()
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: root.quiet ? 0.6 : 1.0
            iconComponent: Component {
              Item {
                width: Style.font.display * 1.15
                height: Style.font.display * 1.15
                Mark {
                  anchors.fill: parent
                  visible: root.showsMark
                  color: root.iconColor
                }
                Text {
                  anchors.centerIn: parent
                  visible: !root.showsMark
                  textFormat: Text.PlainText
                  text: root.glyph(root.sign)
                  color: root.iconColor
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                }
              }
            }
            // The switch is memory sync itself: on, or off.
            trailingControl: Component {
              ToggleSwitch {
                id: syncSwitch
                visible: cordelia.running
                checked: cordelia.syncOn
                busy: cordelia.busy
                foreground: hero.foreground
                onToggled: cordelia.toggleSync()

                PanelToolTip {
                  visible: syncSwitch.containsMouse
                  text: cordelia.syncOn ? "Stop syncing memory on this device" : "Sync Claude Code's memory"
                  fontFamily: hero.fontFamily
                }
              }
            }
          }

          // Everything that holds, red first, each as the node says it.
          Column {
            visible: cordelia.holds.length > 0
            width: parent.width
            spacing: Style.space(4)

            Repeater {
              model: cordelia.holds
              Note {
                required property var modelData
                readonly property bool red: modelData.level === "red"
                width: column.width
                text: root.glyph(red ? "red" : "amber") + "  " + cordelia.sentence(modelData.says)
                color: red ? root.urgent : root.amberColor
              }
            }
          }

          // The node is not the version of the command: it is to be restarted.
          Note {
            visible: cordelia.otherVersion
            text: root.versionSays()
            color: root.urgent
          }
          // What a switch will do meanwhile, said before it is clicked.
          Note {
            visible: cordelia.otherVersion
            text: "Until then, the node refuses changes. You can still turn sync off."
          }

          Note {
            visible: cordelia.actionStatus !== "" || cordelia.lastError !== ""
            text: cordelia.lastError !== "" ? cordelia.lastError : cordelia.actionStatus
            color: cordelia.lastError !== "" ? root.urgent : root.dim
          }

          // Not set up, or set up and stopped: say what to do.
          Note {
            visible: cordelia.loaded && !cordelia.installed
            text: "Install Cordelia to keep your agent's memory in step across your machines: seeddrill.ai/install"
            font.pixelSize: Style.font.body
          }

          ActionRow {
            visible: cordelia.installed && cordelia.nodeStopped
            width: parent.width
            icon: String.fromCodePoint(0xF040A) // play
            title: "Start the node"
            detail: "It runs in the background and keeps memory in step"
            onActivated: cordelia.startNode()
          }

          // ── Folders that stopped syncing ────────────────────────
          Column {
            visible: cordelia.running && cordelia.notice !== null
            width: parent.width
            spacing: Style.space(6)

            PanelSeparator { foreground: root.foreground }
            PanelSectionHeader {
              text: "STOPPED SYNCING"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }
            Note { text: root.noticeSays() }
            Repeater {
              model: cordelia.stoppedSyncing
              FolderRow {
                required property var modelData
                width: column.width
                entry: modelData
              }
            }
            ActionRow {
              width: parent.width
              icon: String.fromCodePoint(0xF012C) // check
              title: "I have seen this"
              detail: "Puts this notice away"
              onActivated: cordelia.noticeSeen()
            }
          }

          // ── Conflicts ───────────────────────────────────────────
          Column {
            visible: cordelia.conflicts.length > 0
            width: parent.width
            spacing: Style.space(6)

            PanelSeparator { foreground: root.foreground }
            PanelSectionHeader {
              text: "CONFLICTS TO MERGE"
              foreground: root.urgent
              fontFamily: root.fontFamily
            }
            Repeater {
              model: cordelia.conflicts
              ActionRow {
                required property var modelData
                width: column.width
                icon: String.fromCodePoint(0xF0026)
                title: cordelia.plain(root.fileName(modelData))
                detail: "Two machines edited this at once. Merge it, then delete this file."
                onActivated: cordelia.openFile(modelData)
              }
            }
          }

          // ── Your devices ────────────────────────────────────────
          Column {
            visible: cordelia.running && (cordelia.person !== null || cordelia.deviceKey !== "")
            width: parent.width
            spacing: Style.space(6)

            PanelSeparator { foreground: root.foreground }
            PanelSectionHeader {
              text: "YOUR DEVICES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            // No recovery phrase yet: nothing syncs, and there are three
            // ways on, as the node names them. Each is run at a terminal, so
            // each is a command to copy. The third is for a person who has
            // lost every device: a new phrase made first would be in the way
            // of the recovery.
            Note {
              visible: cordelia.noPhrase
              text: root.noPhraseSays()
              color: root.foreground
            }
            ActionRow {
              visible: cordelia.noPhrase
              width: parent.width
              icon: String.fromCodePoint(0xF018D) // console
              title: "cordelia phrase"
              detail: "No phrase yet: on your most up to date machine"
              actionIcon: String.fromCodePoint(0xF018F) // copy
              onActivated: cordelia.copyText("cordelia phrase", "Copied. Run it in a terminal.")
            }
            ActionRow {
              visible: cordelia.noPhrase
              width: parent.width
              icon: String.fromCodePoint(0xF018D) // console
              title: "cordelia accept <key>"
              detail: "After add-device on a machine that has the phrase"
              actionIcon: String.fromCodePoint(0xF018F) // copy
              onActivated: cordelia.copyText("cordelia accept <key>",
                "Copied. Put in the key that add-device printed, and run it in a terminal.")
            }
            ActionRow {
              visible: cordelia.noPhrase
              width: parent.width
              icon: String.fromCodePoint(0xF018D) // console
              title: "cordelia recover"
              detail: "You lost every device: do not make a new phrase"
              actionIcon: String.fromCodePoint(0xF018F) // copy
              onActivated: cordelia.copyText("cordelia recover",
                "Copied. Run it in a terminal. It asks for your twelve words.")
            }
            ActionRow {
              visible: cordelia.deviceKey !== "" && (cordelia.noPhrase || cordelia.person === null)
              width: parent.width
              icon: String.fromCodePoint(0xF0379) // monitor
              title: "This device's key"
              detail: root.shortKey(cordelia.deviceKey) + (cordelia.noPhrase ? " · for add-device there" : "")
              actionIcon: String.fromCodePoint(0xF018F) // copy
              onActivated: cordelia.copyKey()
            }

            // Under a phrase: the devices of the last change and those added
            // since, as the node lists them. A removed key is not listed: a
            // removal that has not reached every device holds in amber at the
            // head of the panel, and `cordelia devices` lists the removed keys.
            Note {
              visible: text !== ""
              text: root.cannotGoOn()
              color: root.urgent
            }
            Repeater {
              model: cordelia.devices
              DeviceRow {
                required property var modelData
                width: column.width
                device: modelData
              }
            }
            Note {
              visible: cordelia.added.length > 0
              text: "Added since the last change:"
            }
            Repeater {
              model: cordelia.added
              Column {
                id: addedRow
                required property var modelData
                width: column.width

                DeviceRow {
                  width: parent.width
                  device: addedRow.modelData
                  note: root.addedFrom(addedRow.modelData)
                }
                Note {
                  visible: addedRow.modelData.counted === false
                  text: cordelia.whole(cordelia.joined(["Not counted",
                    cordelia.plain(addedRow.modelData.why_not)], ": "))
                }
              }
            }

            // What this device has to tell its person. It is cleared at a
            // terminal, which asks of each.
            Repeater {
              model: cordelia.notices
              Note {
                required property var modelData
                width: column.width
                text: cordelia.whole(modelData.says)
                color: root.foreground
              }
            }
            ActionRow {
              visible: cordelia.notices.length > 0
              width: parent.width
              icon: String.fromCodePoint(0xF018D) // console
              title: "Clear these notices"
              detail: "Click to copy the command. Run it in a terminal."
              actionIcon: String.fromCodePoint(0xF018F) // copy
              onActivated: cordelia.copyText("cordelia devices --clear", "Copied. Run it in a terminal.")
            }

            ActionRow {
              visible: cordelia.mayAdd
              width: parent.width
              icon: String.fromCodePoint(0xF0415) // plus
              title: "Add a device"
              detail: "Copy the new machine's key first, then click here"
              actionIcon: String.fromCodePoint(0xF018F) // copy
              onActivated: cordelia.copyAddDevice()
            }
          }

          // ── What syncs ──────────────────────────────────────────
          // Home memory first, then each folder, then what waits to be sent.
          Column {
            visible: cordelia.running && cordelia.syncOn
            width: parent.width
            spacing: Style.space(6)

            PanelSeparator { foreground: root.foreground }
            PanelSectionHeader {
              text: cordelia.staysHere ? "MAPPED" : "SYNCING"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }
            Note {
              visible: cordelia.staysHere
              text: "This device sends nothing. These stay on this machine."
            }
            SwitchRow {
              width: parent.width
              title: "Home memory"
              detail: root.homeSays()
              checked: cordelia.home
              onToggled: cordelia.setHome(!cordelia.home)
            }
            Repeater {
              model: cordelia.projects
              SwitchRow {
                required property var modelData
                width: column.width
                title: cordelia.plain(modelData.cwd ? cordelia.shortPath(modelData.cwd) : modelData.project)
                detail: root.folderDetail(modelData)
                checked: true
                onToggled: cordelia.stopSyncing(modelData)
              }
            }
            InfoPair {
              visible: cordelia.waiting > 0
              label: "Waiting to send"
              value: String(cordelia.waiting)
            }
          }

          // ── Found here, not syncing ─────────────────────────────
          Column {
            visible: cordelia.running && cordelia.syncOn && cordelia.found.length > 0
            width: parent.width
            spacing: Style.space(6)

            PanelSeparator { foreground: root.foreground }
            PanelSectionHeader {
              text: "FOUND ON THIS MACHINE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }
            Repeater {
              model: cordelia.found
              FolderRow {
                required property var modelData
                width: column.width
                entry: modelData
              }
            }
          }

          // ── On the other devices, with no folder here ───────────
          Column {
            visible: cordelia.running && cordelia.syncOn && cordelia.elsewhere.length > 0
            width: parent.width
            spacing: Style.space(6)

            PanelSeparator { foreground: root.foreground }
            PanelSectionHeader {
              text: "ON YOUR OTHER DEVICES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }
            Repeater {
              model: cordelia.elsewhere
              ActionRow {
                required property var modelData
                width: column.width
                icon: String.fromCodePoint(0xF0322) // laptop
                title: cordelia.plain(modelData)
                detail: "Click to copy the command to sync it to a folder here"
                actionIcon: String.fromCodePoint(0xF018F) // copy
                onActivated: cordelia.copyMapCommand(String(modelData))
              }
            }
          }

          // ── Relays ──────────────────────────────────────────────
          Column {
            visible: cordelia.running
            width: parent.width
            spacing: Style.space(6)

            PanelSeparator { foreground: root.foreground }
            PanelSectionHeader {
              text: "RELAYS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }
            Note {
              visible: cordelia.noRelay
              text: "No relay connected. Changes wait here until one is."
            }
            Repeater {
              model: cordelia.relays
              NoteRow {
                required property var modelData
                width: column.width
                title: cordelia.plain(modelData.name)
                detail: root.relaySays(modelData)
              }
            }
          }

          // ── The foot: versions, and how much is stored ──────────
          Column {
            visible: footNote.text !== ""
            width: parent.width
            spacing: Style.space(4)

            PanelSeparator { foreground: root.foreground }
            Note {
              id: footNote
              text: root.foot()
              font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }
  }

  // A line or two of plain words, wrapped: quiet, unless it is given a colour.
  component Note: Text {
    textFormat: Text.PlainText
    width: parent ? parent.width : implicitWidth
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    wrapMode: Text.WordWrap
  }

  // A row that does one thing when clicked. One that is given `acts: false`
  // does nothing: it has no highlight, no pointing hand and no icon at its
  // end, so that it does not look as if a click did something.
  component ActionRow: CursorSurface {
    id: actionRow
    property string icon: ""
    property string title: ""
    property string detail: ""
    property string actionIcon: ""
    property bool acts: true
    signal activated()

    hasCursor: actionRow.acts && rowMouse.containsMouse
    foreground: root.foreground
    implicitHeight: rowContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      enabled: actionRow.acts
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: actionRow.activated()
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: actionRow.icon
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: rowContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: actionRow.title
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          visible: actionRow.detail !== ""
          text: actionRow.detail
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Text {
        textFormat: Text.PlainText
        visible: actionRow.acts && actionRow.actionIcon !== ""
        text: actionRow.actionIcon
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }
    }
  }

  // One of this person's devices, by its label and the first words of its
  // key's fingerprint. A click on this device's own row copies its key, which
  // another machine needs to add it or to be added from it. Another device's
  // row does nothing: a device is removed only at a terminal, and the panel
  // offers no row that looks as if it removed one.
  component DeviceRow: ActionRow {
    id: deviceRow
    property var device: ({})
    property string note: ""
    readonly property bool mine: deviceRow.device.this_device === true

    icon: deviceRow.mine ? String.fromCodePoint(0xF0379) : String.fromCodePoint(0xF0322) // monitor / laptop
    title: root.deviceName(deviceRow.device) + (deviceRow.mine ? "  (this device)" : "")
    detail: cordelia.joined([cordelia.plain(deviceRow.device.words), deviceRow.device.left === true ? "has left" : "",
      deviceRow.note], " · ")
    acts: deviceRow.mine
    actionIcon: String.fromCodePoint(0xF018F) // copy
    onActivated: cordelia.copyKey()
  }

  // A labelled switch.
  component SwitchRow: Item {
    id: switchRow
    property string title: ""
    property string detail: ""
    property bool checked: false
    signal toggled()

    implicitHeight: Math.max(switchLabels.implicitHeight, rowSwitch.implicitHeight) + Style.space(4)

    ColumnLayout {
      id: switchLabels
      anchors.left: parent.left
      anchors.right: rowSwitch.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(1)

      Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        text: switchRow.title
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideMiddle
      }
      Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        visible: switchRow.detail !== ""
        text: switchRow.detail
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    ToggleSwitch {
      id: rowSwitch
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      checked: switchRow.checked
      busy: cordelia.busy
      foreground: root.foreground
      onToggled: switchRow.toggled()
    }
  }

  // A row that says something and does nothing: a title, and beneath it what
  // the node says of it, in full.
  component NoteRow: Column {
    id: noteRow
    property string title: ""
    property string detail: ""

    width: parent ? parent.width : implicitWidth
    spacing: Style.space(1)
    topPadding: Style.space(2)
    bottomPadding: Style.space(2)

    Text {
      textFormat: Text.PlainText
      width: noteRow.width
      text: noteRow.title
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideMiddle
    }
    Text {
      textFormat: Text.PlainText
      width: noteRow.width
      visible: noteRow.detail !== ""
      text: noteRow.detail
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }

  // A folder that does not sync, as the node lists it (Service.row). It has a
  // switch only where the node says `cordelia sync map` would sync that
  // folder. Where it needs a name from a person, a click copies the command.
  // Otherwise it shows the node's reason, and nothing to click.
  component FolderRow: Column {
    id: folderRow
    property var entry: ({})
    readonly property bool switched: !!folderRow.entry.args && cordelia.syncOn
    readonly property bool copied: !folderRow.switched && !!folderRow.entry.command

    width: parent ? parent.width : implicitWidth

    SwitchRow {
      visible: folderRow.switched
      width: folderRow.width
      title: String(folderRow.entry.title || "")
      detail: String(folderRow.entry.detail || "")
      checked: false
      onToggled: cordelia.mapFolder(folderRow.entry)
    }
    ActionRow {
      visible: folderRow.copied
      width: folderRow.width
      icon: String.fromCodePoint(0xF018D) // console
      title: String(folderRow.entry.title || "")
      detail: String(folderRow.entry.detail || "")
      actionIcon: String.fromCodePoint(0xF018F) // copy
      onActivated: cordelia.copyText(String(folderRow.entry.command || ""),
        "Copied. Put a name in and run it in a terminal.")
    }
    NoteRow {
      visible: !folderRow.switched && !folderRow.copied
      width: folderRow.width
      title: String(folderRow.entry.title || "")
      detail: String(folderRow.entry.detail || "")
    }
  }

  component InfoPair: RowLayout {
    property string label: ""
    property string value: ""

    width: parent ? parent.width : implicitWidth
    spacing: Style.space(8)

    Text {
      textFormat: Text.PlainText
      text: label
      color: root.foreground
      opacity: 0.7
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
      Layout.fillWidth: true
    }
    Text {
      textFormat: Text.PlainText
      text: value
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }
}
