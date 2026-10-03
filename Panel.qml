import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Cordelia in the bar: one icon that says whether your agent's memory is in
// step, and a panel with the switch, what syncs, relays, devices and conflicts.
Panel {
  id: root
  moduleName: "seeddrill.cordelia"
  ipcTarget: "seeddrill.cordelia"
  manageIpc: false

  // A device row asks twice before removing: the key waiting for the second
  // click, or "".
  property string armedRemoval: ""

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool attention: cordelia.state === "attention"
  readonly property bool quiet: cordelia.state === "off" || cordelia.state === "stopped"
    || cordelia.state === "offline" || cordelia.state === "uninitialised"
  readonly property color barIconColor: quiet ? Qt.darker(barForeground, 1.55) : barForeground
  readonly property color iconColor: attention ? urgent : (quiet ? dim : foreground)

  // Cordelia's own mark (Mark.qml) while memory is in step, and, dimmed,
  // where nothing is being passed on: off, stopped, not set up. The passing
  // states have a Nerd Font glyph each, the same ones `cordelia status
  // --waybar` prints. The Mac menu bar app draws the same.
  readonly property bool showsMark: cordelia.state !== "syncing"
    && cordelia.state !== "offline" && cordelia.state !== "attention"

  function glyph(state) {
    if (state === "syncing") return String.fromCodePoint(0xF04E6)   // sync
    if (state === "offline") return String.fromCodePoint(0xF0164)   // cloud off
    if (state === "attention") return String.fromCodePoint(0xF0026) // alert
    return ""                                                        // the mark
  }

  function headline() {
    if (!cordelia.loaded) return "Checking…"
    if (!cordelia.installed) return "Not set up on this machine"
    var text = cordelia.summary
    return text.charAt(0).toUpperCase() + text.slice(1)
  }

  function shortKey(key) {
    var k = String(key || "")
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

  function projectLabel(project) {
    return project === "~" ? "Home memory" : String(project || "")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    armedRemoval = ""
    if (panelFlick) panelFlick.contentY = 0
    cordelia.refresh()
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
    text: root.glyph(cordelia.state)
    iconComponent: root.showsMark ? barMark : null
    foreground: root.barIconColor
    active: root.attention
    tooltipText: cordelia.installed ? "Cordelia: " + cordelia.summary : "Cordelia"
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
            meta: root.headline()
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
                  text: root.glyph(cordelia.state)
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

          Text {
            textFormat: Text.PlainText
            visible: cordelia.actionStatus !== "" || cordelia.lastError !== ""
            width: parent.width
            text: cordelia.lastError !== "" ? cordelia.lastError : cordelia.actionStatus
            color: cordelia.lastError !== "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          // Not set up, or set up and stopped: say what to do.
          Text {
            textFormat: Text.PlainText
            visible: cordelia.loaded && !cordelia.installed
            width: parent.width
            text: "Install Cordelia to keep your agent's memory in step across your machines: seeddrill.ai/install"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          ActionRow {
            visible: cordelia.installed && !cordelia.running
            width: parent.width
            icon: String.fromCodePoint(0xF040A) // play
            title: "Start the node"
            detail: "It runs in the background and keeps memory in step"
            onActivated: cordelia.startNode()
          }

          // ── Sync ────────────────────────────────────────────────
          Column {
            visible: cordelia.running && cordelia.syncOn
            width: parent.width
            spacing: Style.space(8)

            SwitchRow {
              width: parent.width
              title: "Home memory"
              detail: cordelia.home
                ? (cordelia.homeEntry.waiting === true ? "Waiting for one of your other devices to let this one in"
                  : "What Claude remembers outside any project")
                : (cordelia.homeAvailable ? "Your other devices sync it" : "What Claude remembers outside any project")
              checked: cordelia.home
              onToggled: cordelia.setHome(!cordelia.home)
            }

            SwitchRow {
              visible: cordelia.knowsMappings
              width: parent.width
              title: "Everything found"
              detail: cordelia.all ? "Home memory and every git project, now and later"
                : "Off: only the folders you turn on below"
              checked: cordelia.all
              onToggled: cordelia.setAll(!cordelia.all)
            }

            InfoPair {
              visible: cordelia.waiting > 0
              label: "Waiting to send"
              value: String(cordelia.waiting)
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
                title: root.fileName(modelData)
                detail: "Two machines edited this at once. Merge it, then delete this file."
                onActivated: cordelia.openFile(modelData)
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
            Text {
              textFormat: Text.PlainText
              visible: cordelia.relays.length === 0
              width: parent.width
              text: "No relay connected. Changes wait here until one is."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }
            Repeater {
              model: cordelia.relays
              InfoPair {
                required property var modelData
                label: root.shortKey(modelData.key)
                value: "connected " + root.duration(modelData.connected_secs)
              }
            }
          }

          // ── Devices ─────────────────────────────────────────────
          Column {
            visible: cordelia.running
            width: parent.width
            spacing: Style.space(6)

            PanelSeparator { foreground: root.foreground }
            PanelSectionHeader {
              text: "YOUR DEVICES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }
            Repeater {
              model: cordelia.devices
              ActionRow {
                id: deviceRow
                required property var modelData
                readonly property bool mine: modelData.this_device === true
                readonly property bool armed: root.armedRemoval === String(modelData.key)
                width: column.width
                icon: mine ? String.fromCodePoint(0xF0379) : String.fromCodePoint(0xF0322) // monitor / laptop
                title: (modelData.name ? String(modelData.name) : root.shortKey(modelData.key)) + (mine ? "  (this device)" : "")
                detail: mine ? "Click to copy this device's key"
                  : (armed ? "Click again to remove it and change the keys"
                    : (modelData.in_personal_channel === true ? root.shortKey(modelData.key) : "Trusted, waiting for it to join"))
                danger: armed
                actionIcon: mine ? String.fromCodePoint(0xF018F) : String.fromCodePoint(0xF0A7A) // copy / trash
                onActivated: {
                  if (mine) cordelia.copyKey()
                  else if (armed) { root.armedRemoval = ""; cordelia.removeDevice(String(modelData.key)) }
                  else root.armedRemoval = String(modelData.key)
                }
              }
            }
            ActionRow {
              width: parent.width
              icon: String.fromCodePoint(0xF0415) // plus
              title: "Add a device from the clipboard"
              detail: "Copy the other device's key (cordelia id), then click"
              onActivated: cordelia.addDeviceFromClipboard()
            }
          }

          // ── What syncs ──────────────────────────────────────────
          Column {
            visible: cordelia.running && cordelia.syncOn
              && (cordelia.projects.length > 0 || cordelia.excluded.length > 0)
            width: parent.width
            spacing: Style.space(6)

            PanelSeparator { foreground: root.foreground }
            PanelSectionHeader {
              text: "SYNCING"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }
            Repeater {
              model: cordelia.projects
              SwitchRow {
                required property var modelData
                width: column.width
                title: modelData.cwd ? cordelia.shortPath(modelData.cwd) : String(modelData.project)
                detail: modelData.error ? "Error: " + String(modelData.error)
                  : (modelData.waiting === true ? "Waiting for one of your other devices to let this one in"
                    : (modelData.cwd ? String(modelData.project) : "Syncing"))
                checked: true
                onToggled: cordelia.stopSyncing(modelData)
              }
            }
            Repeater {
              model: cordelia.excluded
              SwitchRow {
                required property var modelData
                width: column.width
                title: String(modelData)
                detail: "Kept off this device"
                checked: false
                onToggled: cordelia.include(String(modelData))
              }
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
              SwitchRow {
                required property var modelData
                width: column.width
                title: cordelia.shortPath(modelData.cwd)
                detail: (modelData.named ? modelData.name : "Syncs as " + modelData.name)
                  + (modelData.elsewhere ? " · your other devices sync it" : "")
                checked: false
                onToggled: cordelia.mapFolder(modelData.cwd, modelData.named ? "" : modelData.name)
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
                title: String(modelData)
                detail: "Click to copy the command that syncs a folder with it"
                actionIcon: String.fromCodePoint(0xF018F) // copy
                onActivated: cordelia.copyText("cordelia sync map <folder> " + String(modelData),
                  "Copied. Put the folder in and run it in a terminal.")
              }
            }
          }
        }
      }
    }
  }

  // A row that does one thing when clicked.
  component ActionRow: CursorSurface {
    id: actionRow
    property string icon: ""
    property string title: ""
    property string detail: ""
    property string actionIcon: ""
    property bool danger: false
    signal activated()

    hasCursor: rowMouse.containsMouse
    foreground: root.foreground
    implicitHeight: rowContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      id: rowMouse
      anchors.fill: parent
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
        color: actionRow.danger ? root.urgent : root.foreground
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
          color: actionRow.danger ? root.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Text {
        textFormat: Text.PlainText
        visible: actionRow.actionIcon !== ""
        text: actionRow.actionIcon
        color: actionRow.danger ? root.urgent : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }
    }
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
