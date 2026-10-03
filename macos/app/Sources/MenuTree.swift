// The menu as data: the same sections as Panel.qml, with its words, laid out
// the way a Mac menu is. StatusItem.swift draws it; `--dump-menu` prints it,
// which is what the tests compare.

import Foundation

/// What a row does when clicked. Actions.swift carries each one out.
enum Act {
    /// The switch: on or off, as the row showed it when it was clicked.
    case setSync(on: Bool)
    case startNode
    case home(on: Bool)
    case all(on: Bool)
    case map(cwd: String, name: String, named: Bool)
    case stop(project: String, mapped: Bool, title: String)
    case include(String)
    case copyKey
    case copyText(String, note: String)
    case addDevice
    case removeDevice(String)
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
        case .all(let on): return "all " + (on ? "on" : "off")
        case .map(let cwd, let name, let named): return "map \(cwd) \(name) " + (named ? "named" : "unnamed")
        case .stop(let project, let mapped, _): return "stop \(project) " + (mapped ? "mapped" : "found")
        case .include(let name): return "include \(name)"
        case .copyKey: return "copy-key"
        case .copyText(_, let note): return "copy (\(note))"
        case .addDevice: return "add-device"
        case .removeDevice(let key): return "remove-device \(shortKey(key))"
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
    // Turning sync on again keeps the mappings and the scope set before.
    case .setSync(let on): return on ? ["sync", "claude"] : ["sync", "off"]
    case .home(let on): return ["sync", "home", on ? "on" : "off"]
    case .all(let on): return ["sync", "claude", on ? "--all" : "--mapped-only"]
    // A git project is named by its remote; any other folder is given its name.
    case .map(let cwd, let name, let named): return ["sync", "map", cwd] + (named ? [] : [name])
    // A mapped folder is unmapped; one found because everything syncs is excluded here.
    case .stop(let project, let mapped, _): return ["sync", mapped ? "unmap" : "exclude", project]
    case .include(let name): return ["sync", "include", name]
    case .removeDevice(let key): return ["remove-device", key]
    default: return nil
    }
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

struct MenuTree {
    var symbol: String
    var urgent: Bool
    /// Drawn dimmed, as an inactive menu bar item is: sync off, or no node.
    var dimmed: Bool
    var tooltip: String
    var rows: [Row]
}

/// The image for each state the node reports (status.state): Cordelia's own
/// mark (Mark.swift) where the panel shows its brain, and an SF Symbol for the
/// passing states. The panel uses Nerd Font glyphs; these are their equivalents.
let SYMBOLS: [String: String] = [
    "synced": MARK,
    "syncing": "arrow.triangle.2.circlepath",
    "offline": "icloud.slash",
    "attention": "exclamationmark.triangle.fill",
    "off": MARK,
    "stopped": MARK,
    "uninitialised": MARK,
]

func buildMenu(_ m: Model, config: Config, home: String, cliVersion: String = "",
               nodeAgent: NodeAgent = .ok) -> MenuTree {
    let never = config.never
    let bad = violations(m, never: never, home: home)
    // The node runs now and will not be started at the next login.
    let blocked = m.installed && nodeAgent == .needsApproval
    let state = bad.isEmpty && !blocked ? m.state : "attention"
    var rows: [Row] = []

    let tail: [Row] = [
        .line,
        Row(title: "About Cordelia", act: .about),
        Row(title: "Quit Cordelia Menu", act: .quit, tip: "The node keeps running and memory keeps syncing"),
    ]
    func tree(_ rows: [Row]) -> MenuTree {
        MenuTree(symbol: SYMBOLS[state] ?? MARK,
                 urgent: state == "attention",
                 dimmed: ["off", "stopped", "uninitialised"].contains(state),
                 tooltip: m.summary.isEmpty ? "Cordelia" : "Cordelia: " + m.summary,
                 rows: rows + tail)
    }

    if !m.installed {
        rows.append(Row(title: "Status: Not installed", tone: .info))
        rows.append(.line)
        rows.append(Row(title: "Install Cordelia…", act: .openURL("https://seeddrill.ai/install")))
        return tree(rows)
    }

    // The status line, as the panel's header shows it.
    let version = m.version.isEmpty ? cliVersion : m.version
    let about = "cordelia \(version.isEmpty ? "?" : version) · panel \(TRACKS)"
    var summary = m.summary.isEmpty ? m.state : m.summary
    if m.waiting > 0 { summary += " · \(m.waiting) waiting to send" }
    rows.append(Row(title: "Status: " + capitalised(summary), tip: about, tone: .info))
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
                            Row(title: fileName($0), act: .open($0),
                                tip: "Two machines edited this at once. Merge it, then delete this file.")
                        }))
    }

    if m.syncOn {
        // ── What syncs ──
        rows.append(.line)
        if m.projects.isEmpty && !m.home {
            rows.append(Row(title: "Nothing syncs yet", tone: .info))
        }
        if m.home {
            rows.append(Row(title: "Home Memory", checked: true, act: .home(on: false),
                            tip: "What Claude remembers outside any project. Click to stop syncing it here."))
        }
        for p in m.projects {
            let title = p.cwd.map { shortPath($0, home: home) } ?? projectLabel(p.name)
            let tip: String
            if let error = p.error {
                tip = "Error: \(error)"
            } else if p.waiting {
                tip = "Waiting for one of your other devices to let this one in"
            } else {
                tip = "Syncs as \(p.name). Click to stop syncing it here."
            }
            rows.append(Row(title: title, checked: true,
                            act: .stop(project: p.name, mapped: p.mapped, title: title),
                            tip: tip, tone: p.error == nil ? .normal : .urgent))
        }
        for x in m.excluded where !onNever(never, name: x, home: home) {
            rows.append(Row(title: x, checked: false, act: .include(x),
                            tip: "Kept off this device. Click to sync it again."))
        }

        // ── Turning more on: only what can be turned on ──
        let offer = m.found.filter { !onNever(never, name: $0.name, cwd: $0.cwd, home: home) }
        let hidden = m.found.count - offer.count
        let homeOffer = !m.home && !onNever(never, name: "~", home: home)
        let allOffer = m.knowsMappings && never.isEmpty
        if !offer.isEmpty || !m.elsewhere.isEmpty || homeOffer || allOffer {
            var more: [Row] = offer.map {
                Row(title: shortPath($0.cwd, home: home),
                    subtitle: $0.named ? $0.name : "Syncs as \($0.name)",
                    act: .map(cwd: $0.cwd, name: $0.name, named: $0.named),
                    tip: "Asks first.")
            }
            if homeOffer {
                more.append(Row(title: "Home Memory", act: .home(on: true),
                                tip: m.homeAvailable ? "Your other devices sync it"
                                                     : "What Claude remembers outside any project"))
            }
            if !m.elsewhere.isEmpty {
                more.append(.line)
                more.append(Row(title: "On Your Other Devices", tone: .info))
                for n in m.elsewhere {
                    let command = "cordelia sync map <folder> \(n)"
                    more.append(Row(title: n, act: .copyText(command, note: command),
                                    tip: "Click to copy the command that syncs a folder with it"))
                }
            }
            if allOffer {
                more.append(.line)
                more.append(Row(title: "Everything Found", checked: m.all, act: .all(on: !m.all),
                                tip: m.all ? "Home memory and every git project, now and later"
                                           : "Off: only the folders you turn on"))
            }
            if hidden > 0 {
                more.append(.line)
                more.append(Row(title: "\(hidden) on your never-sync list, not shown", tone: .info))
            }
            rows.append(Row(title: "Sync Another Folder", children: more))
        }
    }

    // ── Devices and relays, one row each ──
    rows.append(.line)
    var devices: [Row] = []
    for d in m.devices {
        let name = d.name ?? shortKey(d.key)
        if d.thisDevice {
            devices.append(Row(title: name + "  (this device)",
                               subtitle: d.name == nil ? nil : shortKey(d.key),
                               act: .copyKey, tip: "Click to copy this device's key"))
        } else {
            devices.append(Row(title: name + (d.inPersonalChannel ? "" : "  (waiting to join)"),
                               subtitle: d.name == nil ? nil : shortKey(d.key),
                               tip: d.key,
                               children: [Row(title: "Remove This Device…", act: .removeDevice(d.key),
                                              tip: "Asks twice, then changes the keys on every channel")]))
        }
    }
    devices.append(.line)
    devices.append(Row(title: "Add a Device from the Clipboard…", act: .addDevice,
                       tip: "Copy the other device's key (cordelia id), then click"))
    rows.append(Row(title: "Devices: \(m.devices.count)", children: devices))

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
        let how = $0.connected ? "connected \(duration($0.connectedSecs))" : ($0.state.isEmpty ? "not connected" : $0.state)
        return Row(title: shortKey($0.key),
                   subtitle: $0.address.isEmpty ? how : "\($0.address) · \(how)",
                   act: .copyText($0.key, note: "relay key"),
                   tip: "Click to copy this relay's key",
                   tone: $0.connected ? .normal : .urgent)
    }
    if up == 0 {
        relays.insert(Row(title: "Changes wait here until one is", tone: .info), at: 0)
    }
    rows.append(Row(title: relayTitle, tone: up < m.relays.count || up == 0 ? .urgent : .normal, children: relays))

    return tree(rows)
}

// ── The dump ─────────────────────────────────────────────────────────────

func dump(_ tree: MenuTree) -> String {
    var out = ["icon: \(tree.symbol)" + (tree.urgent ? " urgent" : "") + (tree.dimmed ? " dimmed" : ""),
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
            if let t = r.tip { out.append(pad + "        tip: " + t) }
            walk(r.children, depth + 1)
        }
    }
    walk(tree.rows, 0)
    return out.joined(separator: "\n") + "\n"
}
