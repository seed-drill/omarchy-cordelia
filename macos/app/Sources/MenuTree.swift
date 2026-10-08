// The menu as data: the same sections as Panel.qml, with its words, laid out
// the way a Mac menu is. StatusItem.swift draws it; `--dump-menu` prints it,
// which is what the tests compare.
//
// What Cordelia does only at a terminal is never run from here: making the
// recovery phrase, adding, accepting and removing a device, clearing a
// notice. For each of those a command is copied, for a person to paste into
// a terminal.

import Foundation

/// What a row does when clicked. Actions.swift carries each one out.
enum Act {
    /// The switch: on or off, as the row showed it when it was clicked.
    case setSync(on: Bool)
    case startNode
    case home(on: Bool)
    /// Sync a folder the node lists, with what its row says maps it.
    case map(args: [String], cwd: String, under: String, title: String)
    /// Stop syncing a mapped folder from this device: by its folder, which
    /// names one mapping and no other, or by its name where the node lists no
    /// folder for it.
    case stop(target: String, title: String)
    /// The notice of the folders that stopped syncing has been seen.
    case noticeSeen
    case copyKey
    /// Put a command on the clipboard and say `note`. Runs nothing.
    case copyText(String, note: String)
    /// The command that adds a device, with the other device's key in it
    /// where the clipboard holds one. `own` is this device's key, which is
    /// not taken for the other's. Runs nothing.
    case copyAddDevice(own: String)
    case open(String)
    case openURL(String)
    case openLoginItems
    case about
    case quit

    /// A short name for the log and the dump. Never a key or a clipboard value.
    var name: String {
        switch self {
        case .setSync(let on): return "sync " + (on ? "on" : "off")
        case .startNode: return "start-node"
        case .home(let on): return "home " + (on ? "on" : "off")
        case .map(_, _, let under, let title): return "map \(title)" + (under.isEmpty ? "" : " as \(under)")
        case .stop(_, let title): return "stop \(title)"
        case .noticeSeen: return "notice-seen"
        case .copyKey: return "copy-key"
        case .copyText: return "copy"
        case .copyAddDevice: return "copy-add-device"
        case .open(let path): return "open \(path)"
        case .openURL(let url): return "open-url \(url)"
        case .openLoginItems: return "open-login-items"
        case .about: return "about"
        case .quit: return "quit"
        }
    }
}

/// The cordelia command a row runs, for the rows that run exactly one. Actions
/// runs what this returns and the dump prints it, so the tests cover what a
/// click would execute.
func command(for act: Act) -> [String]? {
    switch act {
    // Turning sync on again keeps what was set before: the folders that are mapped.
    case .setSync(let on): return on ? ["sync", "claude"] : ["sync", "off"]
    // Home memory is the home directory, mapped: on maps it under the name it
    // last had here, and off unmaps it.
    case .home(let on): return ["sync", "home", on ? "on" : "off"]
    case .map(let args, _, _, _): return args
    case .stop(let target, _): return ["sync", "unmap", target]
    case .noticeSeen: return ["sync", "status", "--seen"]
    default: return nil
    }
}

/// The add-device command for what the clipboard holds, and what to say of it.
///
/// What the clipboard holds is a key only as a whole: its two ends are
/// trimmed, and nothing in it is joined across a space or a line. This
/// device's own key is not taken for the other's.
func addDeviceCommand(clipboard: String, own: String) -> (command: String, note: String) {
    let key = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
    if isKey(key) && key != own {
        let shown = key.count > 22 ? String(key.prefix(16)) + "…" + String(key.suffix(6)) : key
        return ("cordelia add-device \(key) --name <label>",
                "Copied, with the key \(shown) from the clipboard. Put a name in and run it in a terminal.")
    }
    return ("cordelia add-device <key> --name <label>",
            "Copied. Put the key of the other device and a name in, and run it in a terminal.")
}

/// Whether macOS will start the node at the next login (see Login.swift).
enum NodeAgent: String {
    case ok
    case needsApproval = "needs-approval"
    case absent
}

enum Tone: String {
    case normal
    /// A line that only informs, greyed as a Mac menu greys it.
    case info
    /// What to know of: the node's amber.
    case amber
    /// What to act on now: the node's red, and what only this menu knows.
    case urgent
}

struct Row {
    var title: String
    var subtitle: String? = nil
    /// nil for a row with no tick column.
    var checked: Bool? = nil
    var act: Act? = nil
    var tip: String? = nil
    var tone: Tone = .normal
    var children: [Row] = []
    var separator = false

    static let line = Row(title: "", separator: true)
    var enabled: Bool { act != nil || !children.isEmpty }
}

/// A row that says something and does nothing. A Mac menu does not wrap, so a
/// long line is cut and the whole of it is the tip.
private func note(_ text: String, _ tone: Tone = .info) -> Row {
    let most = 96
    let value = cut(text, 100_000)
    return Row(title: cut(value, most), tip: value.count > most ? value : nil, tone: tone)
}

struct MenuTree {
    var symbol: String
    /// Red: drawn in red, as the menu bar draws what needs a person.
    var urgent: Bool
    /// Amber: the alert in outline, and not highlighted.
    var amber: Bool
    /// Drawn dimmed, as an inactive menu bar item is: nothing is being passed on.
    var dimmed: Bool
    var tooltip: String
    var rows: [Row]
}

/// The image the icon is drawn from: the level where one holds, and the
/// state the node reports where none does. Cordelia's own mark (Mark.swift)
/// where the panel shows its brain, and an SF Symbol for a level and for the
/// passing states. The panel uses Nerd Font glyphs; these are their
/// equivalents.
let SYMBOLS: [String: String] = [
    "red": "exclamationmark.triangle.fill",
    "amber": "exclamationmark.triangle",
    "syncing": "arrow.triangle.2.circlepath",
    "offline": "icloud.slash",
]

// ── What the rows say, as Panel.qml says it ──────────────────────────────

/// What a folder that syncs has to say for itself, where it has anything:
/// why it did not sync, or what of it could not.
func folderSays(_ p: Project) -> String {
    if let error = p.error { return "Error: " + plain(error) }
    if p.waiting { return "Waiting for its channel to be fetched from a relay" }
    if p.tooLarge.count == 1 { return "Too large to sync: " + plain(p.tooLarge[0]) }
    if p.tooLarge.count > 1 { return "\(p.tooLarge.count) files too large to sync" }
    if p.failed > 0 { return p.failed == 1 ? "1 file could not be synced" : "\(p.failed) files could not be synced" }
    return ""
}

func homeSays(_ m: Model) -> String {
    let about = "What Claude remembers outside any project"
    if !m.home { return m.homeAvailable ? "Your other devices sync it" : about }
    let says = m.homeEntry.map(folderSays) ?? ""
    if !says.isEmpty { return says }
    if m.staysHere { return "Stays on this machine" }
    return m.homeName != "~" ? "Syncs as " + plain(m.homeName) : about
}

/// Where a relay stands: whether it is connected, whether it holds the latest
/// change of this person's devices, and what it last refused for room.
func relaySays(_ r: Relay) -> String {
    var says: [String] = []
    if r.connected {
        says.append(r.secs.map { "Connected " + duration($0) } ?? "Connected")
    } else if r.state.isEmpty {
        says.append("Not connected")
    } else {
        says.append(sentence(r.state) + (r.error.isEmpty ? "" : ": " + r.error))
    }
    if r.latest == "yes" { says.append("holds the latest change") }
    else if r.latest == "no" { says.append("does not hold the latest change yet") }
    else if r.latest == "unknown" { says.append("has not said whether it holds the latest change") }
    if !r.noRoom.isEmpty { says.append(r.noRoom) }
    return says.joined(separator: " · ")
}

/// A node goes on running the version it was started as until it is restarted.
func versionSays(_ m: Model) -> String {
    let node = m.nodeVersion.isEmpty ? "The node is from before nodes said their version, and"
        : "The node is version " + plain(m.nodeVersion) + " and"
    return node + " the command is version " + plain(m.version) + ". Restart the node."
}

/// The command's version, the running node's, and this menu's.
func versions(_ m: Model, cliVersion: String) -> String {
    let version = m.version.isEmpty ? cliVersion : m.version
    var parts: [String] = []
    if !version.isEmpty { parts.append("cordelia " + plain(version)) }
    if !m.nodeVersion.isEmpty { parts.append("node " + plain(m.nodeVersion)) }
    parts.append("menu " + APP_VERSION)
    return parts.joined(separator: " · ")
}

func buildMenu(_ m: Model, config: Config, home: String, cliVersion: String = "",
               nodeAgent: NodeAgent = .ok) -> MenuTree {
    let never = config.never
    let bad = violations(m, never: never, home: home)
    // The node runs now and will not be started at the next login.
    let blocked = m.installed && nodeAgent == .needsApproval
    // The level is the node's. Red is what to act on now: so is its state
    // "attention" where it gives no level, and so is what only this menu
    // knows. Amber is what to know of.
    let red = m.level == "red" || (m.level.isEmpty && m.state == "attention") || !bad.isEmpty || blocked
    let amber = !red && m.level == "amber"
    let sign = red ? "red" : (amber ? "amber" : m.state)
    var rows: [Row] = []

    var tail: [Row] = [.line]
    if m.installed { tail.append(Row(title: versions(m, cliVersion: cliVersion), tone: .info)) }
    tail.append(Row(title: "About Cordelia", act: .about))
    tail.append(Row(title: "Quit Cordelia Menu", act: .quit, tip: "The node keeps running and memory keeps syncing"))
    func tree(_ rows: [Row]) -> MenuTree {
        MenuTree(symbol: SYMBOLS[sign] ?? MARK,
                 urgent: red,
                 amber: amber,
                 dimmed: !red && !amber && ["off", "stopped", "offline", "uninitialised"].contains(m.state),
                 tooltip: m.summary.isEmpty ? "Cordelia" : "Cordelia: " + plain(m.summary),
                 rows: rows + tail)
    }

    if !m.installed {
        rows.append(Row(title: "Status: Not installed", tone: .info))
        rows.append(.line)
        rows.append(Row(title: "Install Cordelia…", act: .openURL("https://seeddrill.ai/install")))
        return tree(rows)
    }

    // The status line, as the panel's header shows it. Where anything holds,
    // each is listed in its place, red first, as the node says it.
    if m.holds.isEmpty {
        rows.append(note("Status: " + sentence(m.summary.isEmpty ? m.state : m.summary)))
    } else {
        for h in m.holds { rows.append(note(sentence(h.says), h.level == "red" ? .urgent : .amber)) }
    }
    // The node is not the version of the command: it is to be restarted.
    if m.otherVersion {
        rows.append(note(versionSays(m), .urgent))
        rows.append(note("Until then changes are refused. Turning sync off still works."))
    }
    for v in bad {
        rows.append(Row(title: "Never-sync, but syncing: \(v)", tone: .urgent))
    }
    if config.broken {
        rows.append(Row(title: "menubar.json can't be read: everything counts as never-sync", tone: .urgent))
    }
    if blocked {
        rows.append(Row(title: "Allow Cordelia to Start at Login…", act: .openLoginItems,
                        tip: "macOS has the node's background item switched off, so memory stops syncing at the next login. "
                           + "Click to open Login Items, then switch “cordelia” on.",
                        tone: .urgent))
    }
    if !m.running {
        rows.append(.line)
        rows.append(Row(title: "Start Cordelia", act: .startNode,
                        tip: "It runs in the background and keeps memory in step"))
        return tree(rows)
    }

    // The switch, as the panel's header switch.
    rows.append(Row(title: "Sync Memory on This Mac", checked: m.syncOn, act: .setSync(on: !m.syncOn),
                    tip: m.syncOn ? "Click to stop syncing memory on this device"
                                  : "Click to sync Claude Code's memory"))

    if !m.conflicts.isEmpty {
        let n = m.conflicts.count
        rows.append(Row(title: n == 1 ? "1 Conflict to Merge" : "\(n) Conflicts to Merge", tone: .urgent,
                        children: m.conflicts.map {
                            Row(title: plain(fileName($0)), act: .open($0),
                                tip: "Two machines edited this at once. Merge it, then delete this file.")
                        }))
    }

    /// A folder that does not sync, as the node lists it. It can be turned on
    /// only where the node says `cordelia sync map` would sync that folder.
    /// Where it needs a name from a person, a click copies the command.
    /// Otherwise it shows the node's reason, and nothing to click.
    func folderItem(_ f: FolderRow) -> Row {
        let detail = f.detail.isEmpty ? nil : f.detail
        // A long path is cut in the middle, and the whole of it is in the tip.
        let long = f.title.count > 56
        let title = long ? String(f.title.prefix(26)) + "…" + String(f.title.suffix(28)) : f.title
        let whole = long ? " " + f.title : ""
        if onNever(never, name: f.under, cwd: f.cwd, home: home) {
            return Row(title: title, subtitle: "On your never-sync list", tip: long ? f.title : nil, tone: .info)
        }
        if let args = f.args, m.syncOn {
            return Row(title: title, subtitle: detail,
                       act: .map(args: args, cwd: f.cwd, under: f.under, title: f.title), tip: "Asks first." + whole)
        }
        if !f.command.isEmpty {
            return Row(title: title, subtitle: detail,
                       act: .copyText(f.command, note: "Copied. Put a name in and run it in a terminal."),
                       tip: "Click to copy the command, for a terminal." + whole)
        }
        return Row(title: title, subtitle: detail, tip: long ? f.title : nil, tone: .info)
    }

    // ── Folders that stopped syncing ──
    if m.noticed {
        var stopped: [Row] = []
        if !m.stoppedSyncing.isEmpty {
            stopped.append(note((m.noticeDay.isEmpty ? "Only" : "Since " + plain(m.noticeDay) + " only") + " mapped folders sync."))
            stopped.append(note("These synced because everything found did: turn on the ones to keep."))
        } else if m.noticeNotKnown {
            stopped.append(note("Folders stopped syncing: only mapped folders sync now."))
        } else {
            stopped.append(note("Every folder that stopped syncing is mapped again."))
        }
        if m.noticeNotKnown { stopped.append(note("Not all that stopped is known.")) }
        if !m.stoppedSyncing.isEmpty && !m.syncOn { stopped.append(note("Turn sync on to map one.")) }
        stopped += m.stoppedSyncing.map(folderItem)
        stopped.append(.line)
        stopped.append(Row(title: "I Have Seen This", act: .noticeSeen, tip: "Puts this notice away"))
        rows.append(Row(title: "Folders Stopped Syncing", children: stopped))
    }

    if m.syncOn {
        // ── What syncs ──
        rows.append(.line)
        if m.staysHere && (m.home || !m.projects.isEmpty) {
            rows.append(note("Nothing is sent from this device. These stay on this machine."))
        }
        if m.projects.isEmpty && !m.home {
            rows.append(Row(title: "Nothing syncs yet", tone: .info))
        }
        if m.home {
            rows.append(Row(title: "Home Memory", checked: true, act: .home(on: false),
                            tip: whole(homeSays(m)) + " Click to stop syncing it here.",
                            tone: m.homeEntry?.error == nil ? .normal : .urgent))
        }
        for p in m.projects {
            let title = plain(p.cwd.map { shortPath($0, home: home) } ?? p.name)
            let says = folderSays(p)
            let how = !says.isEmpty ? says : (m.staysHere ? "Mapped as " : "Syncs as ") + plain(p.name)
            let folder = m.mappings.last { $0.name == p.name }?.folder ?? ""
            rows.append(Row(title: title, checked: true,
                            act: .stop(target: folder.isEmpty ? p.name : folder, title: title),
                            tip: whole(how) + " Click to stop syncing it here.",
                            tone: p.error == nil ? .normal : .urgent))
        }
        if m.waiting > 0 {
            rows.append(Row(title: "Waiting to send: \(m.waiting)", tone: .info))
        }

        // ── Turning more on ──
        // What is on the never-sync list is not offered, and not named.
        let visible = m.found.filter { !onNever(never, name: $0.under, cwd: $0.cwd, home: home) }
        let hidden = m.found.count - visible.count
        let listed = visible.map(folderItem)
        let offer = listed.filter { $0.act != nil }
        let reasons = listed.filter { $0.act == nil }
        let homeOffer = !m.home && !onNever(never, name: "~", home: home)
        if !listed.isEmpty || !m.elsewhere.isEmpty || homeOffer {
            var more: [Row] = offer
            if homeOffer {
                more.append(Row(title: "Home Memory", act: .home(on: true), tip: homeSays(m)))
            }
            if !m.elsewhere.isEmpty {
                more.append(.line)
                more.append(Row(title: "On Your Other Devices", tone: .info))
                for n in m.elsewhere {
                    guard copyable(n) else {
                        more.append(Row(title: plain(n), subtitle: "This name cannot be copied safely", tone: .info))
                        continue
                    }
                    more.append(Row(title: plain(n),
                                    act: .copyText("cordelia sync map <folder> " + shellWord(n),
                                                   note: "Copied. Put the folder in and run it in a terminal."),
                                    tip: "Click to copy the command that syncs a folder with it"))
                }
            }
            // Found here, each with the node's reason why it cannot be mapped.
            if !reasons.isEmpty {
                more.append(.line)
                more.append(Row(title: "Found Here, Cannot Be Mapped: \(reasons.count)", children: reasons))
            }
            if hidden > 0 {
                more.append(.line)
                more.append(Row(title: "\(hidden) on your never-sync list, not shown", tone: .info))
            }
            rows.append(Row(title: "Sync Another Folder", children: more))
        }
    }

    // ── Your devices and the relays, one row each ──
    rows.append(.line)
    if m.hasPerson || !m.deviceKey.isEmpty {
        var devices: [Row] = []
        // No recovery phrase yet: nothing syncs, and there are two ways on.
        // Each is run at a terminal, so each is a command to copy.
        if m.noPhrase {
            devices.append(note(sentence(m.personShort.isEmpty ? m.summary : m.personShort) + ". Memory stays on this machine."))
            devices.append(note("Two ways on, each run in a terminal:"))
            devices.append(Row(title: "cordelia phrase", subtitle: "On the machine whose memory is the most up to date",
                               act: .copyText("cordelia phrase", note: "Copied. Run it in a terminal."),
                               tip: "Click to copy the command"))
            devices.append(Row(title: "cordelia accept <key>", subtitle: "After add-device on a machine that has the phrase",
                               act: .copyText("cordelia accept <key>",
                                              note: "Copied. Put in the key that add-device printed, and run it in a terminal."),
                               tip: "Click to copy the command"))
        }
        if !m.deviceKey.isEmpty && (m.noPhrase || !m.hasPerson) {
            devices.append(Row(title: "This Device's Key",
                               subtitle: shortKey(m.deviceKey) + (m.noPhrase ? " · for add-device there" : ""),
                               act: .copyKey, tip: "Click to copy this device's key"))
        }
        // Under a phrase: the devices of the last change, those added since
        // and the removed keys, as the node lists them.
        if !m.cannotGoOn.isEmpty { devices.append(note(m.cannotGoOn, .urgent)) }
        func deviceItem(_ d: PersonDevice) -> Row {
            let name = d.label.isEmpty ? shortKey(d.key) : d.label
            let detail = joined([d.words, d.left ? "has left" : "", d.note], " · ")
            if d.thisDevice {
                return Row(title: name + "  (this device)", subtitle: detail.isEmpty ? nil : detail,
                           act: .copyKey, tip: "Click to copy this device's key")
            }
            // Removing a device asks for the recovery phrase, at a terminal:
            // the command is copied, and not run.
            guard isKey(d.key) else { return Row(title: name, subtitle: detail.isEmpty ? nil : detail, tone: .info) }
            return Row(title: name, subtitle: detail.isEmpty ? nil : detail,
                       children: [Row(title: "Copy the Command That Removes It",
                                      act: .copyText("cordelia remove-device " + d.key,
                                                     note: "Copied. Run it in a terminal: it asks for the phrase."),
                                      tip: "Runs nothing: the command is for a terminal, and asks for the recovery phrase")])
        }
        devices += m.devices.map(deviceItem)
        if !m.added.isEmpty {
            devices.append(Row(title: "Added Since the Last Change", tone: .info))
            for d in m.added {
                devices.append(deviceItem(d))
                if !d.counted { devices.append(note(whole(joined(["Not counted", d.whyNot], ": ")))) }
            }
        }
        for r in m.removed {
            devices.append(Row(title: joined([r.label, r.words], " · "), subtitle: "removed", tone: .info))
        }
        // What this device has to tell its person. It is cleared at a
        // terminal, which asks of each.
        if !m.notices.isEmpty {
            devices.append(.line)
            devices += m.notices.map { note(whole($0), .amber) }
            devices.append(Row(title: "Clear These Notices", subtitle: "Copies cordelia devices --clear, for a terminal",
                               act: .copyText("cordelia devices --clear", note: "Copied. Run it in a terminal."),
                               tip: "Runs nothing: the command asks of each, at a terminal"))
        }
        if m.mayAdd {
            devices.append(.line)
            devices.append(Row(title: "Add a Device", subtitle: "Copies the command, with a key from the clipboard",
                               act: .copyAddDevice(own: m.deviceKey),
                               tip: "Copy the other device's key (cordelia id) first. Runs nothing: the command is for a terminal."))
        }
        let count = m.devices.count + m.added.count
        rows.append(Row(title: m.noPhrase || count == 0 ? "Your Devices" : "Your Devices: \(count)", children: devices))
    }

    let up = m.relays.filter { $0.connected }.count
    let relayTitle: String
    if up == 0 {
        relayTitle = "Relays: none connected"
    } else if up < m.relays.count {
        relayTitle = "Relays: \(up) of \(m.relays.count) connected"
    } else {
        relayTitle = "Relays: \(up) connected"
    }
    var relays: [Row] = m.relays.map {
        let name = plain($0.name)
        return Row(title: name.isEmpty ? "A relay" : name, subtitle: relaySays($0), tone: $0.connected ? .info : .urgent)
    }
    if m.noRelay {
        relays.insert(note("No relay connected. Changes wait here until one is."), at: 0)
    }
    rows.append(Row(title: relayTitle, tone: up < m.relays.count || up == 0 ? .urgent : .normal, children: relays))

    return tree(rows)
}

// ── The dump ─────────────────────────────────────────────────────────────

/// A command as the dump prints it: a key in it is shortened, as a row shows one.
private func shown(_ command: String) -> String {
    command.split(separator: " ", omittingEmptySubsequences: false)
        .map { isKey(String($0)) ? shortKey(String($0)) : String($0) }
        .joined(separator: " ")
}

func dump(_ tree: MenuTree) -> String {
    var out = ["icon: \(tree.symbol)" + (tree.urgent ? " urgent" : "") + (tree.amber ? " amber" : "")
                   + (tree.dimmed ? " dimmed" : ""),
               "tooltip: \(tree.tooltip)",
               ""]
    func walk(_ rows: [Row], _ depth: Int) {
        let pad = String(repeating: "    ", count: depth)
        for r in rows {
            if r.separator {
                out.append(pad + "────")
                continue
            }
            var line = pad
            switch r.checked {
            case .some(true): line += "[x] "
            case .some(false): line += "[ ] "
            case .none: line += "    "
            }
            line += r.title
            if let s = r.subtitle { line += "  |  " + s }
            var tags: [String] = []
            if r.tone != .normal { tags.append(r.tone.rawValue) }
            if !r.enabled { tags.append("disabled") }
            if let a = r.act { tags.append("-> " + a.name) }
            if !r.children.isEmpty { tags.append("submenu") }
            if !tags.isEmpty { line += "   {" + tags.joined(separator: ", ") + "}" }
            out.append(line)
            if let a = r.act, let c = command(for: a) {
                out.append(pad + "        runs: cordelia " + c.joined(separator: " "))
            }
            if let a = r.act, case .copyText(let text, let note) = a {
                out.append(pad + "        copies: " + shown(text))
                out.append(pad + "        says: " + note)
            }
            if let t = r.tip { out.append(pad + "        tip: " + t) }
            walk(r.children, depth + 1)
        }
    }
    walk(tree.rows, 0)
    return out.joined(separator: "\n") + "\n"
}
