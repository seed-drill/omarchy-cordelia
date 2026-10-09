import QtQuick
import Quickshell
import Quickshell.Io

// Everything the panel shows comes from `cordelia status --json`, and the
// sizes from `cordelia stats --json` when the panel opens. Everything it
// changes goes through the cordelia CLI. The service holds no state of its own
// beyond the last answers.
//
// What Cordelia does only at a terminal is never run from here: making the
// recovery phrase, adding and accepting a device, clearing a notice. For each
// of those a command is copied, for a person to paste into a terminal.
// Removing a device is not offered: no command for it is copied.
Item {
  id: root

  property var settings: ({})
  // Refresh faster while the panel is open.
  property bool panelOpen: false

  property var status: ({})
  property bool loaded: false
  property string actionStatus: ""
  property string lastError: ""
  // What `cordelia stats --json` printed when the panel last opened; null
  // where it failed.
  property var stats: null
  // This plugin's own version, from its manifest.
  property string pluginVersion: ""

  readonly property string cli: {
    var configured = String(setting("command", "") || "").trim()
    return configured !== "" ? configured : (Quickshell.env("HOME") + "/.cordelia/bin/cordelia")
  }
  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 10, 5, 600)

  readonly property string state: String(status.state || "uninitialised")
  readonly property string summary: String(status.summary || "")
  // The level is the node's: "red" for what to act on now, "amber" for what
  // to know of, "" where none holds. The panel draws it, and works nothing
  // out itself.
  readonly property string level: status.level === "red" || status.level === "amber" ? status.level : ""
  // Everything that holds, red first, each with its level and what it says.
  readonly property var holds: status.holds instanceof Array ? status.holds : []
  readonly property bool installed: loaded && state !== "uninitialised"
  readonly property bool running: status.running === true
  // Asked, and not running. A node that was not asked is neither.
  readonly property bool nodeStopped: status.running === false
  readonly property string role: String(status.role || "")
  // The command's version and the running node's. A node goes on running the
  // version it was started as until it is restarted.
  readonly property string version: String(status.version || "")
  readonly property string nodeVersion: String(status.node_version || "")
  readonly property bool otherVersion: running && version !== "" && nodeVersion !== version

  readonly property var sync: status.sync || ({})
  // Only what is mapped syncs: each folder with the name it syncs under.
  readonly property var mappings: sync.mappings instanceof Array ? sync.mappings : []
  readonly property string homeDir: String(Quickshell.env("HOME") || "")
  // Home memory syncs where the home directory is mapped: as "~", or under a
  // name of its own.
  readonly property var homeMapping: {
    for (var i = 0; i < mappings.length; i++) {
      if (mappings[i].name === "~" || (homeDir !== "" && mappings[i].folder === homeDir)) return mappings[i]
    }
    return null
  }
  readonly property bool home: homeMapping !== null
  readonly property string homeName: home ? String(homeMapping.name) : ""
  // Every folder that syncs, as the last cycle reported it, home memory
  // among them.
  readonly property var syncing: sync.projects instanceof Array ? sync.projects : []
  readonly property var homeEntry: {
    for (var i = 0; home && i < syncing.length; i++) if (syncing[i].project === homeName) return syncing[i]
    return null
  }
  readonly property var projects: {
    var out = []
    for (var i = 0; i < syncing.length; i++) if (!home || syncing[i].project !== homeName) out.push(syncing[i])
    return out
  }
  // Nothing is sent from this device, and what is in its folders stays on
  // it: it follows no recovery phrase yet, or it has stopped.
  readonly property bool staysHere: (typeof sync.publishes_nothing === "string" && sync.publishes_nothing !== "")
    || (typeof sync.stands === "string" && sync.stands !== "" && sync.stands !== "applied")
  readonly property var conflicts: sync.conflicts instanceof Array ? sync.conflicts : []
  // Names this person's other devices sync and this one does not.
  readonly property var available: sync.available instanceof Array ? sync.available : []
  readonly property bool homeAvailable: available.indexOf("~") !== -1
  // Memory found here that does not sync, as rows (see `row`). Home memory
  // has its own switch.
  readonly property var found: {
    var list = sync.unmapped instanceof Array ? sync.unmapped : []
    var out = []
    for (var i = 0; i < list.length; i++) if (list[i].home !== true) out.push(row(list[i], false))
    return out
  }
  // Names synced elsewhere with no folder found for them here.
  readonly property var elsewhere: {
    var out = []
    for (var i = 0; i < available.length; i++) {
      var name = String(available[i])
      if (name === "~") continue
      var here = false
      for (var j = 0; j < found.length; j++) if (found[j].under === name) here = true
      if (!here) out.push(name)
    }
    return out
  }
  // The notice of the folders that stopped syncing when only mapped folders
  // came to sync, while the node carries one; null where it carries none.
  readonly property var notice: record(sync.notice)
  // Each folder it names that no mapping syncs now, as rows (see `row`).
  readonly property var stoppedSyncing: {
    var list = notice !== null && notice.folders instanceof Array ? notice.folders : []
    var out = []
    for (var i = 0; i < list.length; i++) if (list[i].mapped !== true) out.push(row(list[i], true))
    return out
  }
  // One of its records names no folder: what stopped then is not known.
  readonly property bool noticeNotKnown: notice !== null && notice.not_known === true
  // The day its first record was stored.
  readonly property string noticeDay: {
    var first = notice !== null && notice.records instanceof Array ? record(notice.records[0]) : null
    return first !== null && typeof first.at === "string" ? first.at.substring(0, 10) : ""
  }

  // What the node holds of this person's devices, under their recovery
  // phrase; null where it does not say.
  readonly property var person: record(status.person)
  // This device follows no recovery phrase yet: it syncs nothing until it
  // has one.
  readonly property bool noPhrase: person !== null && person.state === "no_phrase"
  // The devices of the last change and those added since, as the node lists
  // them.
  readonly property var devices: person !== null && person.devices instanceof Array ? person.devices : []
  readonly property var added: person !== null && person.added instanceof Array ? person.added : []
  // What this device has to tell its person, until it is cleared at a
  // terminal.
  readonly property var notices: person !== null && person.notices instanceof Array ? person.notices : []
  readonly property bool mayAdd: person !== null && person.may_add === true
  readonly property var relays: relayRows()
  readonly property bool noRelay: {
    for (var i = 0; i < relays.length; i++) if (relays[i].connected) return false
    return true
  }
  readonly property string deviceKey: String(status.device || "")
  readonly property int waiting: Number(status.outbox_waiting || 0)

  // The switch moves the moment it is clicked; the real state follows.
  // -1 follows the node, 0 or 1 is a change still being applied.
  property int _desiredSync: -1
  // The panel has opened, and the sizes are still to be read: after the next
  // status, or after the one that follows it (see `panelOpened`).
  property bool _sizesWanted: false
  property bool _readAgain: false
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

  // `value` where it is a record of the node's answer, and null otherwise.
  function record(value) {
    return value !== undefined && value !== null && typeof value === "object" ? value : null
  }

  function refresh() {
    if (statusProcess.running) return
    statusProcess.command = [cli, "status", "--json"]
    statusProcess.running = true
  }

  // The panel has opened: the status is read again, and the sizes once that
  // answer is in (see `statusRead`). They are not read with every refresh.
  function panelOpened() {
    _sizesWanted = true
    // An answer that was asked for before the panel opened does not count:
    // the status is read once more after it.
    _readAgain = statusProcess.running
    refresh()
  }

  // A status was asked for, and `fresh` says whether its answer was read.
  function statusRead(fresh) {
    if (!_sizesWanted) return
    if (_readAgain) {
      _readAgain = false
      Qt.callLater(function() { root.refresh() })
      return
    }
    _sizesWanted = false
    if (!panelOpen) return
    if (fresh) readStats()
    else stats = null
  }

  // `cordelia stats` does not ask the node. It opens the database itself, and
  // so brings it to the command's own version. So it is run only where the
  // status just read says that the node runs and is the version of the
  // command: never beside a node of another version, or with none running.
  // Where it is not run, no sizes are shown.
  function readStats() {
    var same = status.running === true && typeof status.version === "string" && status.version !== ""
      && status.node_version === status.version
    if (!same) {
      stats = null
      return
    }
    if (statsProcess.running) return
    statsProcess.command = [cli, "stats", "--json"]
    statsProcess.running = true
  }

  // Take the answer of `cordelia status --json`, and say whether it was read.
  function applyStatus(raw) {
    var text = String(raw || "").trim()
    if (text === "") {
      status = ({})
      loaded = true
      return true
    }
    try {
      status = JSON.parse(text)
      loaded = true
      if (_desiredSync !== -1 && (status.sync && status.sync.enabled === true) === (_desiredSync === 1)) _desiredSync = -1
      return true
    } catch (e) {
      lastError = "Could not read cordelia status"
      return false
    }
  }

  // What of a finished command's output to show: its "last" line (the
  // default), its "first", what it "said" before its first empty line, or
  // "none".
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
  // mapped. Only mapped folders sync.
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

  // Home memory is the home directory, mapped: on maps it under the name it
  // last had here, and off unmaps it.
  function setHome(on) { run(["sync", "home", on ? "on" : "off"], "") }
  // Sync a folder the node lists, with what its row says maps it (see `row`).
  function mapFolder(entry) {
    if (!entry || !entry.args) return
    var args = []
    for (var i = 0; i < entry.args.length; i++) args.push(String(entry.args[i]))
    run(args, "", "first")
  }
  // Stop syncing a mapped folder from this device. Its files stay where they
  // are. It is unmapped by its folder, which names one mapping and no other,
  // and by its name where the node lists no folder for it. All that the
  // command says of it is shown: it may say that this device still holds the
  // name.
  function stopSyncing(entry) {
    var name = String(entry.project)
    var folder = ""
    for (var i = 0; i < mappings.length; i++) if (mappings[i].name === name) folder = String(mappings[i].folder || "")
    run(["sync", "unmap", folder !== "" ? folder : name], "", "said")
  }
  // The notice of the folders that stopped syncing has been seen: the node
  // puts it away, and the next status carries none.
  function noticeSeen() { run(["sync", "status", "--seen"], "", "none") }

  // One folder the node lists as found and not syncing, or names in its
  // notice, as the panel shows it.
  //
  // `args` is what the panel maps it with. It is there only where the node
  // says that `cordelia sync map`, given the folder's directory, would sync
  // that folder: a row without it gets no switch. `command` is there where
  // the folder can be mapped only under a name that a person gives it: it is
  // copied, for a terminal. A row with neither says why the node would not
  // map it. `under` is the name it would sync under.
  function row(entry, noticed) {
    var can = entry.mappable === true && !!entry.cwd
    var name = plain(entry.name)
    var says = plain(entry.says)
    var out = { title: "", detail: "", under: name, args: null, command: "" }
    // What the notice names had a name, and what was found would get one.
    var was = !noticed ? "" : (name !== "" ? "Synced as " + label(name) : "Synced under no name that was kept")
    if (!can) {
      var place = entry.why_not === "laid_out_by_hand" ? String(entry.folder || "") + "/memory"
        : String(entry.directory || entry.cwd || entry.folder || "")
      out.title = plain(shortPath(place))
      if (says === "") says = "the node does not say whether it can be mapped"
      out.detail = sentence(joined([was, says], " · "))
      return out
    }
    var cwd = String(entry.cwd)
    out.title = plain(shortPath(cwd))
    if (entry.home === true) {
      out.args = ["sync", "map", cwd].concat(name !== "" && name !== "~" ? [name] : [], ["--home"])
      out.detail = was !== "" ? was : "Home memory"
    } else if (entry.needs_name === true) {
      // A folder that was found is offered under its own name. One that the
      // notice names synced under another, so its name is left to a person.
      var own = noticed ? "" : suggestedName(cwd)
      if (own !== "") {
        out.under = own
        out.args = ["sync", "map", cwd, own]
        out.detail = "Syncs as " + own
          + (available.indexOf(own) !== -1 ? " · your other devices sync it" : (says !== "" ? " · " + says : ""))
      } else {
        // A folder whose name holds a control character goes into no command.
        var safe = copyable(cwd)
        if (safe) out.command = "cordelia sync map " + shellArg(cwd) + " <name>"
        out.detail = sentence(joined([was, says !== "" ? says : "needs a name",
          safe ? "" : "its folder's name cannot be copied safely"], " · "))
      }
    } else {
      // What was found is named by its remote as it is now. What the notice
      // names is mapped under the name it synced under.
      out.args = ["sync", "map", cwd].concat(noticed && name !== "" ? [name] : [])
      out.detail = noticed ? was : name + (available.indexOf(name) !== -1 ? " · your other devices sync it" : "")
    }
    return out
  }

  // What a folder that syncs has to say for itself, where it has anything:
  // why it did not sync, or what of it could not.
  function folderSays(entry) {
    if (entry.error) return "Error: " + plain(entry.error)
    if (entry.waiting === true) return "Waiting for its channel to be fetched from a relay"
    var large = howMany(entry.too_large)
    if (large === 1) return "Too large to sync: " + plain(entry.too_large[0])
    if (large > 1) return large + " files too large to sync"
    var failed = howMany(entry.failed) + Number(entry.failed_more || 0)
    if (failed > 0) return failed === 1 ? "1 file could not be synced" : failed + " files could not be synced"
    return ""
  }

  // How many a list holds, and 0 for what is no list.
  function howMany(list) {
    return list !== undefined && list !== null && typeof list === "object" && typeof list.length === "number"
      ? list.length : 0
  }

  // The relays this device is set up with, connected or not, each with where
  // this device stands at it once it follows a phrase: whether the relay
  // holds the latest change of this person's devices. A relay the node names
  // only there is listed after them.
  function relayRows() {
    var peers = status.peers || ({})
    var configured = peers.relays instanceof Array ? peers.relays : []
    var connected = peers.list instanceof Array ? peers.list : []
    var stands = person !== null && !noPhrase && person.relays instanceof Array ? person.relays : []
    var out = []
    var listed = ({})
    var i, j
    for (i = 0; i < configured.length; i++) {
      var host = String(configured[i].host || "")
      var secs = null
      for (j = 0; j < connected.length; j++) {
        if (configured[i].key && connected[j].key === configured[i].key) secs = seconds(connected[j].connected_secs)
      }
      var at = null
      for (j = 0; j < stands.length; j++) if (stands[j].relay === host) at = stands[j]
      if (secs === null && at !== null) secs = seconds(at.connected_secs)
      out.push(relayRow(host, String(configured[i].state || ""), secs, plain(configured[i].error), at))
      listed[host] = true
    }
    for (j = 0; j < stands.length; j++) {
      var named = String(stands[j].relay || "")
      if (listed[named] !== true) out.push(relayRow(named, "", seconds(stands[j].connected_secs), "", stands[j]))
    }
    return out
  }

  // One relay. `state` is as the node says it of a relay it is set up with
  // ("connected", "connecting", "unreachable", "wrong key"), and "" where it
  // says only where the device stands there. `latest` is "yes", "no",
  // "unknown" (it has not answered), or "" where the node does not say.
  function relayRow(name, state, secs, error, at) {
    var latest = ""
    if (at !== null) latest = at.holds_latest === true ? "yes" : (at.holds_latest === false ? "no" : "unknown")
    return {
      name: name,
      state: state,
      connected: state === "connected" || (state === "" && secs !== null),
      secs: secs,
      error: error,
      latest: latest,
      noRoom: at !== null ? plain(at.no_room) : ""
    }
  }

  function seconds(value) {
    return typeof value === "number" ? value : null
  }

  // The name a folder that is not a git project is offered under: its own
  // name, in the characters a sync name allows. "" if nothing usable is left.
  function suggestedName(cwd) {
    var parts = String(cwd || "").split("/")
    var base = ""
    for (var i = parts.length - 1; i >= 0 && base === ""; i--) base = parts[i]
    var name = base.toLowerCase().replace(/[^a-z0-9._-]+/g, "-").replace(/^-+|-+$/g, "")
    return /[a-z0-9]/.test(name) ? name : ""
  }

  // A sync name as people read it.
  function label(name) {
    return name === "~" ? "home memory" : String(name || "")
  }

  // `path` with the home directory written as ~.
  function shortPath(path) {
    var p = String(path || "")
    var home = String(Quickshell.env("HOME") || "")
    if (home !== "" && (p === home || p.indexOf(home + "/") === 0)) return "~" + p.substring(home.length)
    return p
  }

  // A word as a shell argument, as the node writes one into a command to
  // copy: as it is where that is safe, and quoted otherwise. A name from
  // another device goes into a command, and nothing in it may be read by the
  // shell.
  function shellWord(word) {
    var w = String(word || "")
    if (/^[A-Za-z0-9\/._+@][A-Za-z0-9\/._+@-]*$/.test(w)) return w
    return "'" + w.replace(/'/g, "'\\''") + "'"
  }

  // A path as a shell argument: with the home directory as ~, outside the
  // quotes where it is quoted, so that the shell still expands it.
  function shellArg(path) {
    var p = shortPath(path)
    var safe = /^[A-Za-z0-9\/._+-]+$/
    if (p === "~") return p
    if (p.indexOf("~/") === 0) {
      var rest = p.substring(2)
      return safe.test(rest) ? p : "~/'" + rest.replace(/'/g, "'\\''") + "'"
    }
    return safe.test(p) ? p : "'" + p.replace(/'/g, "'\\''") + "'"
  }

  // Text from the node, or from another device by way of it, as one line
  // that is safe to show. What would break the line becomes a space. What is
  // not seen and turns the direction of the text around, or sits in it with
  // no width, is taken out: a label cannot reorder what is shown beside it.
  function plain(text) {
    return String(text === undefined || text === null ? "" : text)
      .replace(/[\u061c\u200b-\u200f\u202a-\u202e\u2066-\u2069\ufeff]+/g, "")
      .replace(/[\u0000-\u001f\u007f-\u009f\u2028\u2029]+/g, " ").trim()
  }

  // Whether `text` may go into a command to copy: it holds no control
  // character. A shell argument is quoted, and a line break pasted into a
  // terminal is still a line break.
  function copyable(text) {
    return !/[\u0000-\u001f\u007f]/.test(String(text))
  }

  // The same, with a capital to begin with.
  function sentence(text) {
    var value = plain(text)
    return value.charAt(0).toUpperCase() + value.slice(1)
  }

  // The same, as a whole sentence.
  function whole(text) {
    var value = sentence(text)
    return value === "" || /[.!?]$/.test(value) ? value : value + "."
  }

  // The parts that say anything, joined.
  function joined(parts, separator) {
    var out = []
    for (var i = 0; i < parts.length; i++) if (parts[i] !== "") out.push(parts[i])
    return out.join(separator)
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
    copyText(deviceKey, "This device's key is on the clipboard")
  }

  // Adding a device is done at a terminal, where it asks a yes. This puts the
  // command on the clipboard, with the other device's key in it where the
  // clipboard held one, and says which key went in. It runs nothing of
  // Cordelia.
  //
  // What the clipboard holds is a key only as a whole: its two ends are
  // trimmed, and nothing in it is joined across a space or a line. It is
  // matched in the C locale, where a to z are those letters and no others.
  // This device's own key is not taken for the other's.
  function copyAddDevice() {
    if (clipProcess.running) return
    lastError = ""
    clipProcess.command = ["bash", "-c",
      "LC_ALL=C\n" +
      "key=\"$(wl-paste -n 2>/dev/null | tr '\\0' '\\n')\"\n" +
      "key=\"${key#\"${key%%[![:space:]]*}\"}\"\n" +
      "key=\"${key%\"${key##*[![:space:]]}\"}\"\n" +
      "command='cordelia add-device <key> --name <label>'\n" +
      "note='Copied. Put the key of the other device and a name in, and run it in a terminal.'\n" +
      "if [[ \"$key\" =~ ^cordelia_pk1[a-z0-9]+$ && \"$key\" != \"$1\" ]]; then\n" +
      "  command=\"cordelia add-device $key --name <label>\"\n" +
      "  shown=\"$key\"\n" +
      "  [ \"${#key}\" -gt 22 ] && shown=\"${key:0:16}…${key: -6}\"\n" +
      "  note=\"Copied, with the key $shown from the clipboard. Put a name in and run it in a terminal.\"\n" +
      "fi\n" +
      "printf %s \"$command\" | wl-copy 2>/dev/null || exit 1\n" +
      "echo \"$note\"",
      "copy", deviceKey]
    clipProcess.running = true
  }

  // The command that syncs a folder here with a name the other devices sync,
  // for a terminal.
  function copyMapCommand(name) {
    if (!copyable(name)) {
      flash("This name cannot be copied safely")
      return
    }
    copyText("cordelia sync map <folder> " + shellWord(name), "Copied. Put the folder in and run it in a terminal.")
  }

  function openFile(path) {
    if (!path) return
    Quickshell.execDetached(["omarchy-launch-editor", String(path)])
  }

  // Say `text` for a while: for longer where there is more to read.
  function flash(text) {
    actionStatus = plain(text)
    clearStatus.interval = Math.max(4000, actionStatus.length * 60)
    clearStatus.restart()
  }

  function elide(text) {
    return cut(text, 160)
  }

  // `text` as one line that is safe to show, cut at `most` characters.
  function cut(text, most) {
    var value = plain(text).replace(/\s+/g, " ")
    return value.length > most ? value.substring(0, most - 1) + "…" : value
  }

  // What a command printed before its first empty line.
  function firstParagraph(text) {
    var lines = String(text || "").split("\n")
    var out = []
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].trim() !== "") out.push(lines[i])
      else if (out.length > 0) break
    }
    return out.join("\n")
  }

  // The first line of what a command printed that says anything.
  function firstLine(text) {
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) if (lines[i].trim() !== "") return lines[i]
    return ""
  }

  Component.onCompleted: refresh()

  FileView {
    path: Qt.resolvedUrl("manifest.json")
    printErrors: false
    onLoaded: {
      try {
        root.pluginVersion = String(JSON.parse(text()).version || "")
      } catch (e) {
        root.pluginVersion = ""
      }
    }
  }

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
      var fresh = true
      if (exitCode === 0) fresh = root.applyStatus(statusOut.text)
      else {
        // No cordelia on this machine: nothing to show.
        root.status = ({})
        root.loaded = true
      }
      root.statusRead(fresh)
    }
  }

  Process {
    id: statsProcess
    running: false
    command: []
    stdout: StdioCollector { id: statsOut; waitForEnd: true }
    onExited: function(exitCode) {
      var read = null
      if (exitCode === 0) {
        try {
          read = root.record(JSON.parse(String(statsOut.text || "")))
        } catch (e) {
          read = null
        }
      }
      // Nothing is shown where the command failed.
      root.stats = read
    }
  }

  Process {
    id: clipProcess
    running: false
    command: []
    stdout: StdioCollector { id: clipOut; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) root.flash(root.elide(root.firstLine(clipOut.text)))
      else root.lastError = "The command could not be copied"
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
        // A command that was refused says why, and nothing is shown as done.
        root._desiredSync = -1
        root.lastError = root.elide(root.firstLine(err) || root.firstLine(out) || "The command failed")
        root.actionStatus = ""
      } else {
        root.lastError = ""
        var lines = out.trim().split("\n")
        if (root._show === "first") root.flash(root.elide(lines[0]))
        else if (root._show === "said") root.flash(root.cut(root.firstParagraph(out), 300))
        else if (root._show === "last") root.flash(root.elide(lines[lines.length - 1]))
        else root.actionStatus = ""
      }
      root.refresh()
      settle.restart()
    }
  }
}
