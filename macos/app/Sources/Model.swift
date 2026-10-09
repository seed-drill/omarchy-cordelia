// What the menu shows, derived from `cordelia status --json` as Service.qml
// derives it. Nothing here touches AppKit, so it runs headless in the tests.

import Foundation

/// The Omarchy panel commit this app matches. See the README, "Keeping in step".
let TRACKS = "c50867a"
let APP_VERSION = "0.3.0"

// ── About ────────────────────────────────────────────────────────────────

let ABOUT_TAGLINE = "Your AI agent's memory, in step across your machines."

/// What the About window says under the name. To the person reading, Cordelia is
/// one thing and its version is the node's, so that goes at the top; this menu's
/// own number is small print. With no `cordelia` to ask, the menu's is all there is.
struct AboutText {
    let version: String
    let detail: String
}

func aboutText(cliVersion: String) -> AboutText {
    if cliVersion.isEmpty {
        return AboutText(version: APP_VERSION, detail: "cordelia not found · panel \(TRACKS)")
    }
    return AboutText(version: cliVersion, detail: "menu \(APP_VERSION) · panel \(TRACKS)")
}

typealias JSON = [String: Any]

// ── Settings ─────────────────────────────────────────────────────────────

struct Config {
    var command: String
    var never: [String]
    var broken: Bool

    /// The settings file, or the defaults if there is none. A file that can't
    /// be read counts as a never-sync list that matches everything, so a
    /// broken file never lets anything widen.
    static func load(path: String, home: String) -> Config {
        let fallback = home + "/.cordelia/bin/cordelia"
        guard FileManager.default.fileExists(atPath: path) else {
            return Config(command: fallback, never: [], broken: false)
        }
        let closed = Config(command: fallback, never: ["*"], broken: true)
        guard let data = FileManager.default.contents(atPath: path),
              let cfg = (try? JSONSerialization.jsonObject(with: data)) as? JSON else {
            return closed
        }
        var never: [String] = []
        if let raw = cfg["never"], !(raw is NSNull) {
            guard let list = raw as? [Any] else { return closed }
            never = list.map { "\($0)".trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        let command = (cfg["command"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? fallback
        return Config(command: expandTilde(command, home: home), never: never, broken: false)
    }
}

// ── The node's answer ────────────────────────────────────────────────────

/// One thing that holds, as the node says it: "red" for what to act on now,
/// "amber" for what to know of.
struct Hold {
    let level: String
    let says: String
}

/// A folder that syncs, as the last cycle reported it.
struct Project {
    let name: String
    let cwd: String?
    let error: String?
    let waiting: Bool
    let tooLarge: [String]
    /// Files that could not be synced, those the node did not list among them.
    let failed: Int
}

/// One folder the node lists as found and not syncing, or names in its
/// notice, as the menu shows it (Service.row).
///
/// `args` is what the menu maps it with. It is there only where the node says
/// that `cordelia sync map`, given the folder's directory, would sync that
/// folder. `command` is there where the folder can be mapped only under a
/// name that a person gives it: it is copied, for a terminal. A row with
/// neither says why the node would not map it. `under` is the name it would
/// sync under.
struct FolderRow {
    var title = ""
    var detail = ""
    var under = ""
    var args: [String]? = nil
    var command = ""
    var cwd = ""
}

/// One of this person's devices, as the node lists it under their phrase.
struct PersonDevice {
    let key: String
    let label: String
    let words: String
    let thisDevice: Bool
    let left: Bool
    /// "added from <label>", for a device added since the last change.
    let note: String
    let counted: Bool
    let whyNot: String
}

/// One relay. `state` is as the node says it of a relay it is set up with
/// ("connected", "connecting", "unreachable", "wrong key"), and "" where it
/// says only where the device stands there. `latest` is "yes", "no",
/// "unknown" (it has not answered), or "" where the node does not say.
struct Relay {
    let name: String
    let state: String
    let connected: Bool
    let secs: Int?
    let error: String
    let latest: String
    let noRoom: String
}

struct Model {
    let state: String
    let summary: String
    /// The node's: "red", "amber", or "" where none holds. The menu draws it,
    /// and works nothing out itself.
    let level: String
    /// Everything that holds, red first, each with its level and what it says.
    let holds: [Hold]
    let installed: Bool
    let running: Bool
    /// "personal" on a person's device.
    let role: String
    /// The command's version and the running node's. A node goes on running
    /// the version it was started as until it is restarted.
    let version: String
    let nodeVersion: String
    let otherVersion: Bool

    let syncOn: Bool
    /// Only what is mapped syncs: each folder with the name it syncs under.
    let mappings: [(folder: String, name: String)]
    /// Home memory syncs where the home directory is mapped: as "~", or under
    /// a name of its own.
    let home: Bool
    let homeName: String
    /// Every folder that syncs, home memory among them.
    let syncing: [Project]
    let homeEntry: Project?
    let projects: [Project]
    /// Nothing is sent from this device, and what is in its folders stays on
    /// it: it follows no recovery phrase yet, or it has stopped.
    let staysHere: Bool
    let conflicts: [String]
    let homeAvailable: Bool
    /// Memory found here that does not sync. Home memory has its own row.
    let found: [FolderRow]
    /// Names synced elsewhere with no folder found for them here.
    let elsewhere: [String]

    /// The node carries a notice of the folders that stopped syncing when
    /// only mapped folders came to sync.
    let noticed: Bool
    /// Each folder it names that no mapping syncs now.
    let stoppedSyncing: [FolderRow]
    /// One of its records names no folder: what stopped then is not known.
    let noticeNotKnown: Bool
    /// The day its first record was stored.
    let noticeDay: String

    /// The node says what it holds of this person's devices.
    let hasPerson: Bool
    /// This device follows no recovery phrase yet: it syncs nothing until it has one.
    let noPhrase: Bool
    /// "not added yet" after an upgrade, "no recovery phrase yet" on a new install.
    let personShort: String
    /// Why this device cannot go on, where it cannot, as the node says it.
    let cannotGoOn: String
    /// The devices of the last change and those added since. A removed key
    /// is not listed.
    let devices: [PersonDevice]
    let added: [PersonDevice]
    /// What this device has to tell its person, until it is cleared at a terminal.
    let notices: [String]
    let mayAdd: Bool
    let relays: [Relay]
    let noRelay: Bool
    let deviceKey: String
    let waiting: Int

    init(status st: JSON, home homeDir: String) {
        let s = st["sync"] as? JSON ?? [:]
        let available = strings(s["available"])

        state = nonEmpty(st["state"]) ?? "uninitialised"
        summary = st["summary"] as? String ?? ""
        let lv = st["level"] as? String ?? ""
        level = lv == "red" || lv == "amber" ? lv : ""
        holds = records(st["holds"]).map { Hold(level: $0["level"] as? String ?? "", says: plain($0["says"])) }
        installed = !st.isEmpty && st["state"] as? String != "uninitialised"
        running = st["running"] as? Bool == true
        role = st["role"] as? String ?? ""
        version = st["version"] as? String ?? ""
        nodeVersion = st["node_version"] as? String ?? ""
        otherVersion = running && !version.isEmpty && nodeVersion != version

        syncOn = s["enabled"] as? Bool == true
        mappings = records(s["mappings"]).map { (folder: $0["folder"] as? String ?? "", name: $0["name"] as? String ?? "") }
        let homeMapping = mappings.first { $0.name == "~" || (!homeDir.isEmpty && $0.folder == homeDir) }
        home = homeMapping != nil
        homeName = homeMapping?.name ?? ""
        syncing = records(s["projects"]).map {
            Project(name: $0["project"] as? String ?? "",
                    cwd: nonEmpty($0["cwd"]),
                    error: nonEmpty($0["error"]),
                    waiting: $0["waiting"] as? Bool == true,
                    tooLarge: strings($0["too_large"]),
                    failed: ($0["failed"] as? [Any] ?? []).count + (integer($0["failed_more"]) ?? 0))
        }
        let isHome = home
        let nameOfHome = homeName
        homeEntry = isHome ? syncing.first { $0.name == nameOfHome } : nil
        projects = syncing.filter { !isHome || $0.name != nameOfHome }
        let stands = s["stands"] as? String ?? ""
        staysHere = nonEmpty(s["publishes_nothing"]) != nil || (!stands.isEmpty && stands != "applied")
        conflicts = strings(s["conflicts"])
        homeAvailable = available.contains("~")
        let foundRows = records(s["unmapped"]).filter { $0["home"] as? Bool != true }
            .map { folderRow($0, noticed: false, available: available, home: homeDir) }
        found = foundRows
        elsewhere = available.filter { name in name != "~" && !foundRows.contains { $0.under == name } }

        let notice = record(s["notice"])
        noticed = notice != nil
        stoppedSyncing = records(notice?["folders"]).filter { $0["mapped"] as? Bool != true }
            .map { folderRow($0, noticed: true, available: available, home: homeDir) }
        noticeNotKnown = notice?["not_known"] as? Bool == true
        let first = records(notice?["records"]).first
        noticeDay = (first?["at"] as? String).map { String($0.prefix(10)) } ?? ""

        let person = record(st["person"])
        hasPerson = person != nil
        let without = person?["state"] as? String == "no_phrase"
        noPhrase = without
        personShort = plain(person?["short"])
        cannotGoOn = person != nil && !without ? whole(person?["cannot_go_on"]) : ""
        devices = records(person?["devices"]).map { personDevice($0, added: false) }
        added = records(person?["added"]).map { personDevice($0, added: true) }
        notices = records(person?["notices"]).map { plain($0["says"]) }.filter { !$0.isEmpty }
        mayAdd = person?["may_add"] as? Bool == true
        let rows = relayRows(st, stands: person != nil && !without ? records(person?["relays"]) : [])
        relays = rows
        noRelay = !rows.contains { $0.connected }
        deviceKey = st["device"] as? String ?? ""
        waiting = integer(st["outbox_waiting"]) ?? 0
    }
}

private func strings(_ value: Any?) -> [String] {
    (value as? [Any] ?? []).compactMap { $0 as? String }
}

private func nonEmpty(_ value: Any?) -> String? {
    guard let s = value as? String, !s.isEmpty else { return nil }
    return s
}

/// `value` where it is a record of the node's answer, and nil otherwise.
private func record(_ value: Any?) -> JSON? {
    value as? JSON
}

private func records(_ value: Any?) -> [JSON] {
    (value as? [Any] ?? []).compactMap { $0 as? JSON }
}

/// A number of the node's answer, and nil for anything else: true and false
/// are not numbers.
private func integer(_ value: Any?) -> Int? {
    guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
    return Int(n.doubleValue)
}

private func personDevice(_ d: JSON, added: Bool) -> PersonDevice {
    let from = added ? plain(record(d["by"])?["label"]) : ""
    return PersonDevice(key: d["key"] as? String ?? "",
                        label: plain(d["label"]),
                        words: plain(d["words"]),
                        thisDevice: d["this_device"] as? Bool == true,
                        left: d["left"] as? Bool == true,
                        note: from.isEmpty ? "" : "added from " + from,
                        counted: !(d["counted"] as? Bool == false),
                        whyNot: plain(d["why_not"]))
}

/// One folder the node lists as found and not syncing, or names in its notice.
private func folderRow(_ e: JSON, noticed: Bool, available: [String], home: String) -> FolderRow {
    let cwd = nonEmpty(e["cwd"])
    let name = plain(e["name"])
    var says = plain(e["says"])
    var out = FolderRow()
    out.under = name
    // What the notice names had a name, and what was found would get one.
    let was = !noticed ? "" : (!name.isEmpty ? "Synced as " + label(name) : "Synced under no name that was kept")
    guard e["mappable"] as? Bool == true, let dir = cwd else {
        let place = e["why_not"] as? String == "laid_out_by_hand" ? (e["folder"] as? String ?? "") + "/memory"
            : nonEmpty(e["directory"]) ?? cwd ?? nonEmpty(e["folder"]) ?? ""
        out.title = plain(shortPath(place, home: home))
        if says.isEmpty { says = "the node does not say whether it can be mapped" }
        out.detail = sentence(joined([was, says], " · "))
        return out
    }
    out.cwd = dir
    out.title = plain(shortPath(dir, home: home))
    if e["home"] as? Bool == true {
        out.args = ["sync", "map", dir] + (!name.isEmpty && name != "~" ? [name] : []) + ["--home"]
        out.detail = !was.isEmpty ? was : "Home memory"
    } else if e["needs_name"] as? Bool == true {
        // A folder that was found is offered under its own name. One that the
        // notice names synced under another, so its name is left to a person.
        let own = noticed ? "" : suggestedName(dir)
        if !own.isEmpty {
            out.under = own
            out.args = ["sync", "map", dir, own]
            out.detail = "Syncs as " + own
                + (available.contains(own) ? " · your other devices sync it" : (!says.isEmpty ? " · " + says : ""))
        } else {
            // A folder whose name holds a control character goes into no command.
            let safe = copyable(dir)
            if safe { out.command = "cordelia sync map " + shellArg(dir, home: home) + " <name>" }
            out.detail = sentence(joined([was, !says.isEmpty ? says : "needs a name",
                                          safe ? "" : "its folder's name cannot be copied safely"], " · "))
        }
    } else {
        // What was found is named by its remote as it is now. What the notice
        // names is mapped under the name it synced under.
        out.args = ["sync", "map", dir] + (noticed && !name.isEmpty ? [name] : [])
        out.detail = noticed ? was : name + (available.contains(name) ? " · your other devices sync it" : "")
    }
    return out
}

/// The relays this device is set up with, connected or not, each with where
/// this device stands at it once it follows a phrase: whether the relay holds
/// the latest change of this person's devices. A relay the node names only
/// there is listed after them.
private func relayRows(_ st: JSON, stands: [JSON]) -> [Relay] {
    let peers = st["peers"] as? JSON ?? [:]
    let connected = records(peers["list"])
    var out: [Relay] = []
    var listed = Set<String>()
    for c in records(peers["relays"]) {
        let host = c["host"] as? String ?? ""
        var secs: Int? = nil
        if let key = nonEmpty(c["key"]) {
            for p in connected where p["key"] as? String == key { secs = integer(p["connected_secs"]) }
        }
        let at = stands.last { $0["relay"] as? String == host }
        if secs == nil, let at = at { secs = integer(at["connected_secs"]) }
        out.append(relayRow(host, state: c["state"] as? String ?? "", secs: secs, error: plain(c["error"]), at: at))
        listed.insert(host)
    }
    for s in stands {
        let named = s["relay"] as? String ?? ""
        if !listed.contains(named) {
            out.append(relayRow(named, state: "", secs: integer(s["connected_secs"]), error: "", at: s))
        }
    }
    return out
}

private func relayRow(_ name: String, state: String, secs: Int?, error: String, at: JSON?) -> Relay {
    var latest = ""
    if let at = at {
        let holds = at["holds_latest"] as? Bool
        latest = holds == true ? "yes" : (holds == false ? "no" : "unknown")
    }
    return Relay(name: name,
                 state: state,
                 connected: state == "connected" || (state.isEmpty && secs != nil),
                 secs: secs,
                 error: error,
                 latest: latest,
                 noRoom: at != nil ? plain(at?["no_room"]) : "")
}

// ── The never-sync list ──────────────────────────────────────────────────

private func matches(_ pattern: String, _ value: String) -> Bool {
    pattern.hasSuffix("*") ? value.hasPrefix(String(pattern.dropLast())) : value == pattern
}

/// Whether a sync name or folder is on the never-sync list. `~` is home
/// memory; an entry starting with / or ~/ is a folder; anything else is a
/// name, with a trailing * matching a prefix.
func onNever(_ never: [String], name: String? = nil, cwd: String? = nil, home: String) -> Bool {
    for pattern in never {
        if pattern == "~" {
            if name == "~" { return true }
        } else if pattern.hasPrefix("/") || pattern.hasPrefix("~/") {
            if let cwd = cwd, !cwd.isEmpty, matches(expandTilde(pattern, home: home), cwd) { return true }
        } else if let name = name, !name.isEmpty, matches(pattern.lowercased(), name.lowercased()) {
            return true
        }
    }
    return false
}

/// Anything that syncs although the never-sync list rules it out.
func violations(_ m: Model, never: [String], home: String) -> [String] {
    var out: [String] = []
    for p in m.syncing {
        let isHome = m.home && p.name == m.homeName
        if onNever(never, name: isHome ? "~" : p.name, cwd: p.cwd, home: home)
            || (isHome && onNever(never, name: p.name, cwd: p.cwd, home: home)) {
            out.append(isHome ? "Home Memory" : projectLabel(p.name))
        }
    }
    return out
}

// ── Text, as the panel writes it ─────────────────────────────────────────

func expandTilde(_ path: String, home: String) -> String {
    if path == "~" { return home }
    return path.hasPrefix("~/") ? home + String(path.dropFirst(1)) : path
}

/// The name a folder that is not a git project is offered under: its own
/// name, in the characters a sync name allows. "" if nothing usable is left.
func suggestedName(_ cwd: String) -> String {
    let base = cwd.split(separator: "/").last.map(String.init) ?? ""
    var name = ""
    var gap = false
    for ch in base.lowercased().unicodeScalars {
        let ok = (ch >= "a" && ch <= "z") || (ch >= "0" && ch <= "9") || ch == "." || ch == "_" || ch == "-"
        if ok {
            if gap { name.append("-") }
            gap = false
            name.unicodeScalars.append(ch)
        } else {
            gap = true
        }
    }
    if gap { name.append("-") }
    name = name.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    let usable = name.unicodeScalars.contains { ($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9") }
    return usable ? name : ""
}

func shortPath(_ path: String, home: String) -> String {
    !home.isEmpty && (path == home || path.hasPrefix(home + "/")) ? "~" + String(path.dropFirst(home.count)) : path
}

func shortKey(_ key: String) -> String {
    let k = plain(key)
    return k.count > 26 ? String(k.prefix(18)) + "…" + String(k.suffix(6)) : k
}

func duration(_ secs: Int) -> String {
    let s = max(0, secs)
    if s < 60 { return "\(s)s" }
    if s < 3600 { return "\(s / 60)m" }
    if s < 86400 { return "\(s / 3600)h \((s % 3600) / 60)m" }
    return "\(s / 86400)d"
}

func fileName(_ path: String) -> String {
    path.split(separator: "/").last.map(String.init) ?? path
}

func projectLabel(_ project: String) -> String {
    project == "~" ? "Home Memory" : project
}

/// A sync name as people read it.
func label(_ name: String) -> String {
    name == "~" ? "home memory" : name
}

/// Text from the node, or from another device by way of it, as one line that
/// is safe to show. What would break the line becomes a space. What is not
/// seen and turns the direction of the text around, or sits in it with no
/// width, is taken out: a label cannot reorder what is shown beside it.
func plain(_ value: Any?) -> String {
    let text: String
    switch value {
    case let s as String: text = s
    case let n as NSNumber: text = "\(n)"
    default: return ""
    }
    var out = String.UnicodeScalarView()
    var gap = false
    for u in text.unicodeScalars {
        let v = u.value
        if v == 0x061c || (0x200b...0x200f).contains(v) || (0x202a...0x202e).contains(v)
            || (0x2066...0x2069).contains(v) || v == 0xfeff {
            continue
        }
        if v <= 0x1f || (0x7f...0x9f).contains(v) || v == 0x2028 || v == 0x2029 {
            gap = true
            continue
        }
        if gap { out.append(" ") }
        gap = false
        out.append(u)
    }
    if gap { out.append(" ") }
    return String(out).trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Whether `text` may go into a command to copy: it holds no control
/// character. A shell argument is quoted, and a line break pasted into a
/// terminal is still a line break.
func copyable(_ text: String) -> Bool {
    !text.unicodeScalars.contains { $0.value <= 0x1f || $0.value == 0x7f }
}

/// The same, with a capital to begin with.
func sentence(_ value: Any?) -> String {
    let text = plain(value)
    guard let first = text.first else { return text }
    return first.uppercased() + text.dropFirst()
}

/// The same, as a whole sentence.
func whole(_ value: Any?) -> String {
    let text = sentence(value)
    guard let last = text.last else { return text }
    return ".!?".contains(last) ? text : text + "."
}

/// The parts that say anything, joined.
func joined(_ parts: [String], _ separator: String) -> String {
    parts.filter { !$0.isEmpty }.joined(separator: separator)
}

/// `text` as one line that is safe to show, cut at `most` characters.
func cut(_ text: String, _ most: Int) -> String {
    let value = plain(text).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    return value.count > most ? String(value.prefix(most - 1)) + "…" : value
}

func elide(_ text: String) -> String {
    cut(text, 160)
}

/// A device's key, as the node writes one.
func isKey(_ key: String) -> Bool {
    let prefix = "cordelia_pk1"
    guard key.hasPrefix(prefix), key.count > prefix.count else { return false }
    return key.dropFirst(prefix.count).unicodeScalars.allSatisfy { ($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9") }
}

private func safeWord(_ text: String, first: String, rest: String) -> Bool {
    guard let head = text.unicodeScalars.first else { return false }
    let firstSet = CharacterSet(charactersIn: first), restSet = CharacterSet(charactersIn: rest)
    return firstSet.contains(head) && text.unicodeScalars.dropFirst().allSatisfy { restSet.contains($0) }
}

private let WORD = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789/._+"

private func quoted(_ text: String) -> String {
    "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

/// A word as a shell argument, as the node writes one into a command to copy:
/// as it is where that is safe, and quoted otherwise. A name from another
/// device goes into a command, and nothing in it may be read by the shell.
func shellWord(_ word: String) -> String {
    safeWord(word, first: WORD + "@", rest: WORD + "@-") ? word : quoted(word)
}

/// A path as a shell argument: with the home directory as ~, outside the
/// quotes where it is quoted, so that the shell still expands it.
func shellArg(_ path: String, home: String) -> String {
    let p = shortPath(path, home: home)
    let safe = { (s: String) in safeWord(s, first: WORD + "-", rest: WORD + "-") }
    if p == "~" { return p }
    if p.hasPrefix("~/") {
        let rest = String(p.dropFirst(2))
        return safe(rest) ? p : "~/" + quoted(rest)
    }
    return safe(p) ? p : quoted(p)
}
