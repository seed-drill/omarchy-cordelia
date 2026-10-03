// What the menu shows, derived from `cordelia status --json` as Service.qml
// derives it. Nothing here touches AppKit, so it runs headless in the tests.

import Foundation

/// The Omarchy panel commit this app matches. See the README, "Keeping in step".
let TRACKS = "5286109"
let APP_VERSION = "0.1.0"

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

struct Project {
    let name: String
    let cwd: String?
    let mapped: Bool
    let error: String?
    let waiting: Bool
}

struct Found {
    let cwd: String
    let name: String
    let named: Bool
}

struct Device {
    let key: String
    let name: String?
    let thisDevice: Bool
    let inPersonalChannel: Bool
}

struct Relay {
    let key: String
    let address: String
    let state: String
    let connectedSecs: Int

    /// Connected now. A relay the node knows of and cannot reach is listed
    /// with another state once the node reports those.
    var connected: Bool { state == "hot" || state == "warm" }
}

struct Model {
    let state: String
    let summary: String
    let installed: Bool
    let running: Bool
    let syncOn: Bool
    /// Everything that syncs, home memory included.
    let syncing: [Project]
    let home: Bool
    let projects: [Project]
    let knowsMappings: Bool
    let all: Bool
    let excluded: [String]
    let conflicts: [String]
    let homeAvailable: Bool
    let found: [Found]
    let elsewhere: [String]
    let devices: [Device]
    let relays: [Relay]
    let deviceKey: String
    let waiting: Int
    let version: String

    init(status st: JSON, home homeDir: String) {
        let s = st["sync"] as? JSON ?? [:]
        let available = strings(s["available"])

        syncing = (s["projects"] as? [Any] ?? []).compactMap { $0 as? JSON }.map {
            Project(name: $0["project"] as? String ?? "",
                    cwd: nonEmpty($0["cwd"]),
                    mapped: $0["mapped"] as? Bool == true,
                    error: nonEmpty($0["error"]),
                    waiting: $0["waiting"] as? Bool == true)
        }
        home = syncing.contains { $0.name == "~" }
        projects = syncing.filter { $0.name != "~" }

        // Memory found here that does not sync, each with the name it would get.
        var list: [Found] = []
        for e in (s["unmapped"] as? [Any] ?? []).compactMap({ $0 as? JSON }) {
            guard let cwd = nonEmpty(e["cwd"]), e["name"] as? String != "~" else { continue }
            // The node refuses to map a folder outside the home directory, so don't offer one.
            guard cwd == homeDir || cwd.hasPrefix(homeDir + "/") else { continue }
            let given = nonEmpty(e["name"])
            let name = given ?? suggestedName(cwd)
            if !name.isEmpty { list.append(Found(cwd: cwd, name: name, named: given != nil)) }
        }
        found = list
        let foundNames = Set(list.map { $0.name })

        state = nonEmpty(st["state"]) ?? "uninitialised"
        summary = st["summary"] as? String ?? ""
        installed = !st.isEmpty && st["state"] as? String != "uninitialised"
        running = st["running"] as? Bool == true
        syncOn = s["enabled"] as? Bool == true
        knowsMappings = s["all"] != nil
        all = s["all"] as? Bool == true
        // Folders in the exclude list were unmapped; they show under "found".
        excluded = strings(s["exclude"]).filter { !$0.hasPrefix("/") }
        conflicts = strings(s["conflicts"])
        homeAvailable = available.contains("~")
        // Names synced elsewhere with no folder found for them here.
        elsewhere = available.filter { $0 != "~" && !foundNames.contains($0) }
        devices = (st["devices"] as? [Any] ?? []).compactMap { $0 as? JSON }.map {
            Device(key: $0["key"] as? String ?? "",
                   name: nonEmpty($0["name"]),
                   thisDevice: $0["this_device"] as? Bool == true,
                   inPersonalChannel: $0["in_personal_channel"] as? Bool == true)
        }
        let peers = (st["peers"] as? JSON)?["list"] as? [Any] ?? []
        relays = peers.compactMap { $0 as? JSON }.filter { $0["role"] as? String == "relay" }.map {
            Relay(key: $0["key"] as? String ?? "",
                  address: $0["address"] as? String ?? "",
                  state: $0["state"] as? String ?? "",
                  connectedSecs: ($0["connected_secs"] as? NSNumber)?.intValue ?? 0)
        }
        deviceKey = st["device"] as? String ?? ""
        waiting = (st["outbox_waiting"] as? NSNumber)?.intValue ?? 0
        version = st["version"] as? String ?? ""
    }
}

private func strings(_ value: Any?) -> [String] {
    (value as? [Any] ?? []).compactMap { $0 as? String }
}

private func nonEmpty(_ value: Any?) -> String? {
    guard let s = value as? String, !s.isEmpty else { return nil }
    return s
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
            if let cwd = cwd, matches(expandTilde(pattern, home: home), cwd) { return true }
        } else if let name = name, !name.isEmpty, matches(pattern.lowercased(), name.lowercased()) {
            return true
        }
    }
    return false
}

/// Anything that syncs although the never-sync list rules it out.
func violations(_ m: Model, never: [String], home: String) -> [String] {
    var out: [String] = []
    if !never.isEmpty && m.all { out.append("Everything Found") }
    for p in m.syncing where onNever(never, name: p.name, cwd: p.cwd, home: home) {
        out.append(projectLabel(p.name))
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
    path == home || path.hasPrefix(home + "/") ? "~" + String(path.dropFirst(home.count)) : path
}

func shortKey(_ key: String) -> String {
    key.count > 26 ? String(key.prefix(18)) + "…" + String(key.suffix(6)) : key
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

func elide(_ text: String) -> String {
    let value = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    return value.count > 160 ? String(value.prefix(157)) + "…" : value
}

func capitalised(_ text: String) -> String {
    guard let first = text.first else { return text }
    return first.uppercased() + text.dropFirst()
}
