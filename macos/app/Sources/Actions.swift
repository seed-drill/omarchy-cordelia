// Everything the menu changes goes through the cordelia command line, as
// Service.qml's command functions do. Anything that widens what syncs asks
// first. What Cordelia does only at a terminal (the recovery phrase, adding,
// accepting and removing a device, clearing a notice) is never run from here:
// its command is copied.

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

    /// How much memory this device stores: the size of its encrypted content,
    /// from `cordelia stats --json`; nil where it failed or does not say.
    /// `stats` opens the database itself, so the caller runs this only where
    /// `maySize` allows: beside a running node of the command's own version.
    func storedBytes() -> Int? {
        let r = run(["stats", "--json"], timeout: 5)
        guard r.code == 0, let data = r.out.data(using: .utf8),
              let stats = (try? JSONSerialization.jsonObject(with: data)) as? JSON,
              let n = stats["content_bytes_stored"] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return Int(n.doubleValue)
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

    static func post(_ text: String, most: Int = 160) {
        let body = cut(text, most)
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

    /// What of a finished command's output to show: its first line, its
    /// last, what it said before its first empty line, or nothing.
    private enum Show { case first, last, said, none }

    /// Reports a finished command the way the panel does: the error, or the
    /// part of its output that was asked for. A command that was refused says
    /// why, and nothing is shown as done.
    private func finish(_ r: CLI.Result, show: Show = .last) {
        let lines = { (s: String) in s.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").map(String.init) }
        logAction("  exit \(r.code): \(lines(r.err.isEmpty ? r.out : r.err).first ?? "")")
        if r.code != 0 {
            Notifier.post(lines(r.err).first ?? lines(r.out).first ?? "The command failed")
        } else {
            switch show {
            case .first: if let text = lines(r.out).first { Notifier.post(text) }
            case .last: if let text = lines(r.out).last { Notifier.post(text) }
            case .said: Notifier.post(firstParagraph(r.out), most: 300)
            case .none: break
            }
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
        case .setSync(let on):
            run(command(for: act)!, show: on ? .none : .last)

        case .home(let on):
            if on && onNever(never, name: "~", home: home) {
                return Notifier.post("Home memory is on your never-sync list")
            }
            if on && !confirm("Sync home memory on this Mac?",
                              detail: "It goes to every device that syncs home memory.",
                              ok: "Sync Home Memory") { return }
            run(command(for: act)!)

        case .map(let args, let cwd, let under, let title):
            guard !args.isEmpty else { return }
            if onNever(never, name: under, cwd: cwd, home: home) {
                return Notifier.post("\(title) is on your never-sync list")
            }
            guard confirm("Start syncing \(title)" + (under.isEmpty ? "?" : " as \(label(under))?"),
                          detail: "Claude's memory for it will go to all your devices.",
                          ok: "Start Syncing") else { return }
            run(args, show: .first)

        // All that the command says of it is shown: it may say that this
        // device still holds the name.
        case .stop(_, let title):
            guard confirm("Stop syncing \(title) on this Mac?",
                          detail: "Its files stay where they are.",
                          ok: "Stop Syncing") else { return }
            run(command(for: act)!, show: .said)

        // The node puts the notice away, and the next status carries none.
        case .noticeSeen:
            run(command(for: act)!, show: .none)

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
            Notifier.post(note)

        // Adding a device is done at a terminal, where it asks a yes. This
        // puts the command on the clipboard, with the other device's key in
        // it where the clipboard held one, and says which key went in. It
        // runs nothing of Cordelia.
        case .copyAddDevice(let own):
            let made = addDeviceCommand(clipboard: NSPasteboard.general.string(forType: .string) ?? "", own: own)
            copyToClipboard(made.command)
            Notifier.post(made.note)

        case .open(let path):
            guard !path.isEmpty else { return }
            launch("/usr/bin/open", ["-t", path])

        case .openURL(let url):
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }

        case .openLoginItems:
            openLoginItemsSettings()

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

/// What a command printed before its first empty line.
func firstParagraph(_ text: String) -> String {
    var out: [String] = []
    for line in text.components(separatedBy: "\n") {
        if !line.trimmingCharacters(in: .whitespaces).isEmpty { out.append(line) }
        else if !out.isEmpty { break }
    }
    return out.joined(separator: "\n")
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
    let about = aboutText(cliVersion: cliVersion)
    let centred = NSMutableParagraphStyle()
    centred.alignment = .center
    let credits = NSAttributedString(
        string: "\(ABOUT_TAGLINE)\n\(about.detail)\nseeddrill.ai",
        attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                     .foregroundColor: NSColor.secondaryLabelColor,
                     .paragraphStyle: centred])
    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel(options: [
        .applicationName: "Cordelia",
        .applicationVersion: about.version,
        .version: "",
        .credits: credits,
    ])
}
