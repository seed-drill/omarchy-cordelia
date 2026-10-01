import QtQuick
import Quickshell
import Quickshell.Io

// Everything the panel shows comes from one call, `cordelia status --json`,
// and everything it changes goes through the cordelia CLI. The service holds
// no state of its own beyond the last answer.
Item {
  id: root

  property var settings: ({})
  // Refresh faster while the panel is open.
  property bool panelOpen: false

  property var status: ({})
  property bool loaded: false
  property string actionStatus: ""
  property string lastError: ""

  readonly property string cli: {
    var configured = String(setting("command", "") || "").trim()
    return configured !== "" ? configured : (Quickshell.env("HOME") + "/.cordelia/bin/cordelia")
  }
  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 10, 5, 600)

  readonly property string state: String(status.state || "uninitialised")
  readonly property string summary: String(status.summary || "")
  readonly property bool installed: loaded && state !== "uninitialised"
  readonly property bool running: status.running === true
  readonly property var sync: status.sync || ({})
  readonly property bool home: sync.home !== false
  readonly property var projects: sync.projects instanceof Array ? sync.projects : []
  readonly property var excluded: sync.exclude instanceof Array ? sync.exclude : []
  readonly property var conflicts: sync.conflicts instanceof Array ? sync.conflicts : []
  readonly property var unsynced: sync.unsynced instanceof Array ? sync.unsynced : []
  readonly property var devices: status.devices instanceof Array ? status.devices : []
  readonly property var relays: {
    var list = status.peers && status.peers.list instanceof Array ? status.peers.list : []
    var out = []
    for (var i = 0; i < list.length; i++) if (list[i].role === "relay") out.push(list[i])
    return out
  }
  readonly property string deviceKey: String(status.device || "")
  readonly property int waiting: Number(status.outbox_waiting || 0)

  // The switch moves the moment it is clicked; the real state follows.
  // -1 follows the node, 0 or 1 is a change still being applied.
  property int _desiredSync: -1
  readonly property bool syncOn: _desiredSync === -1 ? sync.enabled === true : _desiredSync === 1
  readonly property bool busy: actionProcess.running

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    return Math.max(min, Math.min(max, n))
  }

  function refresh() {
    if (statusProcess.running) return
    statusProcess.command = [cli, "status", "--json"]
    statusProcess.running = true
  }

  function applyStatus(raw) {
    var text = String(raw || "").trim()
    if (text === "") {
      status = ({})
      loaded = true
      return
    }
    try {
      status = JSON.parse(text)
      loaded = true
      if (_desiredSync !== -1 && (status.sync && status.sync.enabled === true) === (_desiredSync === 1)) _desiredSync = -1
    } catch (e) {
      lastError = "Could not read cordelia status"
    }
  }

  // Run a cordelia command; `note` shows while it runs.
  function run(args, note) {
    if (actionProcess.running) return
    lastError = ""
    actionStatus = note || ""
    actionProcess.command = [cli].concat(args)
    actionProcess.running = true
  }

  function runShell(script, note) {
    if (actionProcess.running) return
    lastError = ""
    actionStatus = note || ""
    actionProcess.command = ["bash", "-c", script, cli]
    actionProcess.running = true
  }

  function toggleSync() {
    if (!running) return
    if (syncOn) {
      _desiredSync = 0
      run(["sync", "off"], "")
    } else {
      _desiredSync = 1
      run(home ? ["sync", "claude"] : ["sync", "claude", "--no-home"], "")
    }
  }

  function setHome(on) { run(["sync", "home", on ? "on" : "off"], "") }
  function setProject(project, on) { run(["sync", on ? "include" : "exclude", project], "") }
  function removeDevice(key) { run(["remove-device", key], "Removing the device and changing keys…") }

  function startNode() {
    runShell("systemctl --user start cordelia", "Starting the node…")
  }

  function copyKey() {
    if (deviceKey === "") return
    Quickshell.execDetached(["bash", "-c", "printf %s \"$1\" | wl-copy", "copy", deviceKey])
    flash("This device's key is on the clipboard")
  }

  // Pairing takes one key copied in each direction. The other device's key
  // comes from the clipboard; the command it must run goes back onto it.
  function addDeviceFromClipboard() {
    runShell(
      "key=\"$(wl-paste -n 2>/dev/null | tr -d '[:space:]')\"\n" +
      "case \"$key\" in cordelia_pk1*) ;; *) echo 'The clipboard does not hold a device key (cordelia_pk1…)' >&2; exit 2 ;; esac\n" +
      "out=\"$(\"$0\" add-device \"$key\" 2>&1)\" || { echo \"$out\" >&2; exit 1; }\n" +
      "accept=\"$(printf '%s\\n' \"$out\" | sed -n 's/^ *\\(cordelia accept .*\\)$/\\1/p' | head -1)\"\n" +
      "[ -n \"$accept\" ] && printf %s \"$accept\" | wl-copy\n" +
      "echo 'Added. The command for the other device is on the clipboard.'",
      "Adding the device from the clipboard…")
  }

  function openFile(path) {
    if (!path) return
    Quickshell.execDetached(["omarchy-launch-editor", String(path)])
  }

  function flash(text) {
    actionStatus = text
    clearStatus.restart()
  }

  function elide(text) {
    var value = String(text || "").replace(/\s+/g, " ").trim()
    return value.length > 160 ? value.substring(0, 157) + "…" : value
  }

  Component.onCompleted: refresh()

  Timer {
    interval: (root.panelOpen ? 3 : root.refreshIntervalSec) * 1000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Timer {
    id: clearStatus
    interval: 4000
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Timer {
    id: settle
    interval: 1200
    repeat: false
    onTriggered: {
      root.refresh()
      root._desiredSync = -1
    }
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector { id: statusOut; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) root.applyStatus(statusOut.text)
      else {
        // No cordelia on this machine: nothing to show.
        root.status = ({})
        root.loaded = true
      }
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: StdioCollector { id: actionOut; waitForEnd: true }
    stderr: StdioCollector { id: actionErr; waitForEnd: true }
    onExited: function(exitCode) {
      var out = String(actionOut.text || "")
      var err = String(actionErr.text || "")
      if (exitCode !== 0) {
        root._desiredSync = -1
        root.lastError = root.elide(err || out || "The command failed")
        root.actionStatus = ""
      } else {
        root.lastError = ""
        var lines = out.trim().split("\n")
        root.flash(root.elide(lines[lines.length - 1]))
      }
      root.refresh()
      settle.restart()
    }
  }
}
