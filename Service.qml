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
  // Every folder that syncs, home memory among them (its name is "~").
  readonly property var syncing: sync.projects instanceof Array ? sync.projects : []
  readonly property var homeEntry: {
    for (var i = 0; i < syncing.length; i++) if (syncing[i].project === "~") return syncing[i]
    return null
  }
  readonly property bool home: homeEntry !== null
  readonly property var projects: {
    var out = []
    for (var i = 0; i < syncing.length; i++) if (syncing[i].project !== "~") out.push(syncing[i])
    return out
  }
  // Whether everything found syncs, or only what is mapped. A node from
  // before mappings does not say: it syncs everything found.
  readonly property bool knowsMappings: sync.all !== undefined
  readonly property bool all: sync.all === true
  // Project names kept off this device. Folders in the list are ones that
  // were unmapped; they show under "found" instead, where they can be
  // turned back on.
  readonly property var excluded: {
    var list = sync.exclude instanceof Array ? sync.exclude : []
    var out = []
    for (var i = 0; i < list.length; i++) if (String(list[i]).charAt(0) !== "/") out.push(list[i])
    return out
  }
  readonly property var conflicts: sync.conflicts instanceof Array ? sync.conflicts : []
  // Names this person's other devices sync and this one does not.
  readonly property var available: sync.available instanceof Array ? sync.available : []
  readonly property bool homeAvailable: available.indexOf("~") !== -1
  // Memory found here that does not sync, each with the name it would get.
  // A folder that is not a git project is offered under its own name.
  readonly property var found: {
    var list = sync.unmapped instanceof Array ? sync.unmapped : []
    var out = []
    for (var i = 0; i < list.length; i++) {
      var entry = list[i]
      if (!entry.cwd || entry.name === "~") continue
      var name = entry.name ? String(entry.name) : suggestedName(entry.cwd)
      if (name === "") continue
      out.push({ cwd: String(entry.cwd), name: name, named: !!entry.name, elsewhere: available.indexOf(name) !== -1 })
    }
    return out
  }
  // Names synced elsewhere with no folder found for them here.
  readonly property var elsewhere: {
    var out = []
    for (var i = 0; i < available.length; i++) {
      var name = String(available[i])
      if (name === "~") continue
      var here = false
      for (var j = 0; j < found.length; j++) if (found[j].name === name) here = true
      if (!here) out.push(name)
    }
    return out
  }
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

  // Which line of a finished command's output to show: "last" (the
  // default), "first", or "none".
  property string _show: "last"

  // Run a cordelia command; `note` shows while it runs.
  function run(args, note, show) {
    if (actionProcess.running) return
    lastError = ""
    actionStatus = note || ""
    _show = show || "last"
    actionProcess.command = [cli].concat(args)
    actionProcess.running = true
  }

  function runShell(script, note) {
    if (actionProcess.running) return
    lastError = ""
    actionStatus = note || ""
    _show = "last"
    actionProcess.command = ["bash", "-c", script, cli]
    actionProcess.running = true
  }

  // Turning sync on again keeps what was set before: the folders that are
  // mapped, and whether everything found syncs.
  function toggleSync() {
    if (!running) return
    if (syncOn) {
      _desiredSync = 0
      run(["sync", "off"], "")
    } else {
      _desiredSync = 1
      run(["sync", "claude"], "", "none")
    }
  }

  function setHome(on) { run(["sync", "home", on ? "on" : "off"], "") }
  function setAll(on) { run(["sync", "claude", on ? "--all" : "--mapped-only"], "", "none") }
  // A git project is named by its remote; any other folder is given `name`.
  function mapFolder(cwd, name) { run(["sync", "map", cwd].concat(name ? [name] : []), "", "first") }
  // A mapped folder is unmapped; one found because everything syncs is
  // excluded on this device.
  function stopSyncing(entry) {
    if (entry.mapped === true) run(["sync", "unmap", String(entry.project)], "", "first")
    else run(["sync", "exclude", String(entry.project)], "")
  }
  function include(project) { run(["sync", "include", project], "") }
  function removeDevice(key) { run(["remove-device", key], "Removing the device and changing keys…") }

  // The name a folder that is not a git project is offered under: its own
  // name, in the characters a sync name allows. "" if nothing usable is left.
  function suggestedName(cwd) {
    var parts = String(cwd || "").split("/")
    var base = ""
    for (var i = parts.length - 1; i >= 0 && base === ""; i--) base = parts[i]
    var name = base.toLowerCase().replace(/[^a-z0-9._-]+/g, "-").replace(/^-+|-+$/g, "")
    return /[a-z0-9]/.test(name) ? name : ""
  }

  // `path` with the home directory written as ~.
  function shortPath(path) {
    var p = String(path || "")
    var home = String(Quickshell.env("HOME") || "")
    if (home !== "" && (p === home || p.indexOf(home + "/") === 0)) return "~" + p.substring(home.length)
    return p
  }

  function copyText(text, note) {
    Quickshell.execDetached(["bash", "-c", "printf %s \"$1\" | wl-copy", "copy", String(text)])
    flash(note)
  }

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
        if (root._show === "first") root.flash(root.elide(lines[0]))
        else if (root._show === "last") root.flash(root.elide(lines[lines.length - 1]))
        else root.actionStatus = ""
      }
      root.refresh()
      settle.restart()
    }
  }
}
