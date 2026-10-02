// Everything the menu changes goes through the cordelia command line, as
// Service.qml's command functions do. Anything that widens what syncs, or
// adds or removes a device, asks first.

import AppKit
import UserNotifications

// ── The node ─────────────────────────────────────────────────────────────

struct CLI {
    let command: String

    typealias Result = (code: Int32, out: String, err: String)

    func run(_ args: [String], timeout: TimeInterval = 60) -> Result {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: command)
        p.arguments = args
        let outPipe = Pipe(), errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return (1, "", error.localizedDescription) }

        // Both pipes are read while the command runs, so a long answer on one
        // can't block it.
        var outData = Data(), errData = Data()
        let readers = DispatchGroup()
        let queue = DispatchQueue.global(qos: .userInitiated)
        readers.enter()
        queue.async { outData = outPipe.fileHandleForReading.readDataToEndOfFile(); readers.leave() }
        readers.enter()
        queue.async { errData = errPipe.fileHandleForReading.readDataToEndOfFile(); readers.leave() }
        let stop = DispatchWorkItem { if p.isRunning { p.terminate() } }
        queue.asyncAfter(deadline: .now() + timeout, execute: stop)
        p.waitUntilExit()
        stop.cancel()
        readers.wait()
        return (p.terminationStatus, String(decoding: outData, as: UTF8.self), String(decoding: errData, as: UTF8.self))
    }

    /// The node's answer to `status --json`, or [:] if there is no node.
    func status(timeout: TimeInterval = 8) -> JSON {
        let r = run(["status", "--json"], timeout: timeout)
        guard r.code == 0, let data = r.out.data(using: .utf8) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data)) as? JSON ?? [:]
    }

    /// "0.2.0-alpha.3", from `cordelia --version`; "" if it can't be run.
    func version() -> String {
        let r = run(["--version"], timeout: 5)
        return r.code == 0 ? (r.out.split(whereSeparator: { $0.isWhitespace }).last.map(String.init) ?? "") : ""
    }
}

// ── Telling the person ───────────────────────────────────────────────────

/// One line per click, and its outcome, in ~/.cordelia/logs/menubar.log.
/// Never the clipboard's content.
func logAction(_ text: String, home: String = NSHomeDirectory()) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    let line = "\(stamp) \(elide(text))\n"
    let path = home + "/.cordelia/logs/menubar.log"
    guard let data = line.data(using: .utf8) else { return }
    if let handle = FileHandle(forWritingAtPath: path) {
        handle.seekToEndOfFile()
        handle.write(data)
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: path, contents: data)
    }
}

enum Notifier {
    private static var allowed = false

    /// Notifications come from the app itself when it runs from its bundle and
    /// the person allows them; otherwise through osascript, as the SwiftBar
    /// plugin sent them.
    static func setUp(delegate: UNUserNotificationCenterDelegate) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let centre = UNUserNotificationCenter.current()
        centre.delegate = delegate
        centre.requestAuthorization(options: [.alert]) { ok, _ in
            allowed = ok
            logAction("notifications: " + (ok ? "allowed" : "not allowed, so sent through osascript"))
        }
    }

    static func post(_ text: String) {
        let body = elide(text)
        guard !body.isEmpty else { return }
        if allowed {
            let content = UNMutableNotificationContent()
            content.title = "Cordelia"
            content.body = body
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
            return
        }
        let escaped = body.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "display notification \"\(escaped)\" with title \"Cordelia\""]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }
}

/// Asks before doing. Cancel is the default button, so Return never widens
/// anything.
func confirm(_ question: String, detail: String, ok: String, destructive: Bool = false) -> Bool {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = question
    alert.informativeText = detail
    alert.addButton(withTitle: "Cancel")
    let button = alert.addButton(withTitle: ok)
    if destructive { button.hasDestructiveAction = true }
    let yes = alert.runModal() == .alertSecondButtonReturn
    logAction("  confirm \(yes ? "yes" : "no or cancelled"): \(question)")
    return yes
}

// ── What each row does ───────────────────────────────────────────────────

final class Actions {
    private let home: String
    private let work = DispatchQueue(label: "ai.seeddrill.cordelia.menubar.actions")
    /// Called on the main thread when something may have changed.
    var changed: () -> Void = {}
    /// The settings, read again for every click so an edit takes effect at once.
    var config: () -> Config

    init(home: String, config: @escaping () -> Config) {
        self.home = home
        self.config = config
    }

    private enum Show { case first, last, none }

    /// Reports a finished command the way the panel does: the error, or the
    /// first or last line of its output.
    private func finish(_ r: CLI.Result, show: Show = .last) {
        let lines = { (s: String) in s.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").map(String.init) }
        logAction("  exit \(r.code): \(lines(r.err.isEmpty ? r.out : r.err).first ?? "")")
        if r.code != 0 {
            Notifier.post(!r.err.isEmpty ? r.err : (!r.out.isEmpty ? r.out : "The command failed"))
        } else if let text = show == .first ? lines(r.out).first : show == .last ? lines(r.out).last : nil {
            Notifier.post(text)
        }
        DispatchQueue.main.async { self.changed() }
    }

    /// Runs a cordelia command off the main thread, then reports it.
    private func run(_ args: [String], timeout: TimeInterval = 60, show: Show = .last) {
        let cli = CLI(command: config().command)
        work.async { self.finish(cli.run(args, timeout: timeout), show: show) }
    }

    func perform(_ act: Act) {
        logAction("click: \(act.name)")
        let cfg = config()
        let never = cfg.never
        let cli = CLI(command: cfg.command)

        switch act {
        case .toggleSync:
            // Turning sync on again keeps the mappings and the scope set before.
            work.async {
                if Model(status: cli.status(), home: self.home).syncOn {
                    self.finish(cli.run(["sync", "off"]))
                } else {
                    self.finish(cli.run(["sync", "claude"]), show: .none)
                }
            }

        case .home(let on):
            if on && onNever(never, name: "~", home: home) {
                return Notifier.post("Home memory is on your never-sync list")
            }
            if on && !confirm("Sync home memory on this Mac?",
                              detail: "It goes to every device that syncs home memory.",
                              ok: "Sync Home Memory") { return }
            run(["sync", "home", on ? "on" : "off"])

        case .all(let on):
            if on && !never.isEmpty {
                return Notifier.post("Everything Found stays off while a never-sync list is set")
            }
            if on && !confirm("Sync everything found?",
                              detail: "Home memory and every git project on this Mac, now and later.",
                              ok: "Sync Everything") { return }
            run(["sync", "claude", on ? "--all" : "--mapped-only"], show: .none)

        case .map(let cwd, let name, let named):
            guard !cwd.isEmpty, !name.isEmpty else { return }
            let folder = shortPath(cwd, home: home)
            if onNever(never, name: name, cwd: cwd, home: home) {
                return Notifier.post("\(folder) is on your never-sync list")
            }
            guard confirm("Start syncing \(folder) as \(name)?",
                          detail: "Claude's memory for it will go to all your devices.",
                          ok: "Start Syncing") else { return }
            // A git project is named by its remote; any other folder is given its name.
            run(["sync", "map", cwd] + (named ? [] : [name]), show: .first)

        case .stop(let project, let mapped, let title):
            guard confirm("Stop syncing \(title.isEmpty ? project : title) on this Mac?",
                          detail: "Its files stay where they are.",
                          ok: "Stop Syncing") else { return }
            // A mapped folder is unmapped; one found because everything syncs is excluded here.
            if mapped {
                run(["sync", "unmap", project], show: .first)
            } else {
                run(["sync", "exclude", project])
            }

        case .include(let name):
            if onNever(never, name: name, home: home) {
                return Notifier.post("\(name) is on your never-sync list")
            }
            run(["sync", "include", name])

        case .copyKey:
            work.async {
                let key = cli.status()["device"] as? String ?? ""
                guard !key.isEmpty else { return }
                DispatchQueue.main.async {
                    copyToClipboard(key)
                    Notifier.post("This device's key is on the clipboard")
                }
            }

        case .copyText(let text, let note):
            copyToClipboard(text)
            Notifier.post(note == "relay key" ? "The relay's key is on the clipboard" : "Copied: \(text)")

        case .addDevice:
            // Pairing takes one key copied in each direction. The other device's key
            // comes from the clipboard; the command it must run goes back onto it.
            let key = (NSPasteboard.general.string(forType: .string) ?? "").filter { !$0.isWhitespace }
            guard key.hasPrefix("cordelia_pk1") else {
                return Notifier.post("The clipboard does not hold a device key (cordelia_pk1…)")
            }
            guard confirm("Add \(shortKey(key)) as one of your devices?",
                          detail: "It will receive the memory this Mac syncs.",
                          ok: "Add Device") else { return }
            work.async {
                let r = cli.run(["add-device", key])
                logAction("  exit \(r.code)")
                guard r.code == 0 else {
                    Notifier.post(!r.err.isEmpty ? r.err : (!r.out.isEmpty ? r.out : "Adding the device failed"))
                    return
                }
                let accept = r.out.split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .first { $0.hasPrefix("cordelia accept ") }
                DispatchQueue.main.async {
                    if let accept = accept { copyToClipboard(accept) }
                    Notifier.post("Added. The command for the other device is on the clipboard.")
                    self.changed()
                }
            }

        case .removeDevice(let key):
            guard !key.isEmpty else { return }
            guard confirm("Remove \(shortKey(key))?", detail: "It stops receiving memory.", ok: "Continue") else { return }
            guard confirm("Remove \(shortKey(key)) for good?",
                          detail: "This changes the keys on every channel.",
                          ok: "Remove", destructive: true) else { return }
            Notifier.post("Removing the device and changing keys…")
            run(["remove-device", key], timeout: 180)

        case .open(let path):
            guard !path.isEmpty else { return }
            launch("/usr/bin/open", ["-t", path])

        case .openURL(let url):
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }

        case .startNode:
            work.async {
                let target = "gui/\(getuid())/ai.seeddrill.cordelia"
                if launch("/bin/launchctl", ["kickstart", "-k", target], wait: true) != 0 {
                    launch("/bin/launchctl", ["load", self.home + "/Library/LaunchAgents/ai.seeddrill.cordelia.plist"], wait: true)
                }
                Notifier.post("Starting the node…")
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.changed() }
            }

        case .about:
            work.async {
                let version = cli.version()
                DispatchQueue.main.async { showAbout(cliVersion: version) }
            }

        case .quit:
            NSApp.terminate(nil)
        }
    }
}

func copyToClipboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

@discardableResult
private func launch(_ path: String, _ args: [String], wait: Bool = false) -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return 1 }
    guard wait else { return 0 }
    p.waitUntilExit()
    return p.terminationStatus
}

func showAbout(cliVersion: String) {
    let centred = NSMutableParagraphStyle()
    centred.alignment = .center
    let credits = NSAttributedString(
        string: "Your AI agent's memory, in step across your machines.\n"
            + "cordelia \(cliVersion.isEmpty ? "not found" : cliVersion) · panel \(TRACKS)\nseeddrill.ai",
        attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                     .foregroundColor: NSColor.secondaryLabelColor,
                     .paragraphStyle: centred])
    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel(options: [
        .applicationName: "Cordelia",
        .applicationVersion: APP_VERSION,
        .version: "",
        .credits: credits,
    ])
}
