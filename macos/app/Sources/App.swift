// The menu bar item: draws MenuTree as a native menu, and holds no state of
// its own. It asks the node again every few seconds and whenever the menu
// opens.

import AppKit
import UserNotifications

private final class Boxed {
    let act: Act
    init(_ act: Act) { self.act = act }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    private let home = NSHomeDirectory()
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private var timer: Timer?
    private var cliVersion = ""
    private lazy var actions = Actions(home: home, config: { [unowned self] in self.config() })

    private var configPath: String { home + "/.config/cordelia/menubar.json" }
    private func config() -> Config { Config.load(path: configPath, home: home) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // One icon only: a second copy started by hand gives way to the first.
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
            NSApp.terminate(nil)
            return
        }
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        item.button?.imagePosition = .imageOnly
        actions.changed = { [weak self] in self?.refresh() }
        Notifier.setUp(delegate: self)
        logAction("started: Cordelia menu \(APP_VERSION), panel \(TRACKS), pid \(ProcessInfo.processInfo.processIdentifier)")
        draw(tree(timeout: 2))
        refresh()
        let t = Timer(timeInterval: 10, repeats: true) { [weak self] _ in self?.refresh() }
        t.tolerance = 2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// The menu as the node describes it now.
    private func tree(timeout: TimeInterval) -> MenuTree {
        let cfg = config()
        let status = CLI(command: cfg.command).status(timeout: timeout)
        return buildMenu(Model(status: status, home: home), config: cfg, home: home, cliVersion: cliVersion,
                         nodeAgent: nodeAgentState(home: home))
    }

    /// Asks the node off the main thread and redraws the icon.
    private func refresh() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            if self.cliVersion.isEmpty { self.cliVersion = CLI(command: self.config().command).version() }
            let tree = self.tree(timeout: 8)
            DispatchQueue.main.async { self.draw(tree) }
        }
    }

    private func draw(_ tree: MenuTree) {
        guard let button = item.button else { return }
        // Cordelia's own mark while memory is in step, and an SF Symbol for the passing states.
        let image = tree.symbol == MARK ? cordeliaMarkImage()
            : NSImage(systemSymbolName: tree.symbol, accessibilityDescription: "Cordelia") ?? cordeliaMarkImage()
        // Red is highlighted. Amber is the alert in outline, and is not: it
        // is drawn as the bar draws any other item.
        if tree.urgent, let red = image.withSymbolConfiguration(.init(paletteColors: [.systemRed])) {
            red.isTemplate = false
            button.image = red
        } else {
            image.isTemplate = true
            button.image = image
        }
        button.appearsDisabled = tree.dimmed
        button.toolTip = tree.tooltip
    }

    // The status call takes about 10 ms, so the menu is filled as it opens.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        let tree = self.tree(timeout: 2)
        draw(tree)
        menu.removeAllItems()
        items(tree.rows).forEach(menu.addItem)
    }

    private func items(_ rows: [Row]) -> [NSMenuItem] {
        rows.map { row in
            if row.separator { return .separator() }
            let item = NSMenuItem(title: row.title, action: nil, keyEquivalent: "")
            var title = row.title
            if let subtitle = row.subtitle {
                if #available(macOS 14.4, *) {
                    item.subtitle = subtitle
                } else {
                    title += "  ·  " + subtitle
                    item.title = title
                }
            }
            // Red for what to act on now, and amber for what to know of.
            if row.tone == .urgent || row.tone == .amber {
                item.attributedTitle = NSAttributedString(
                    string: title,
                    attributes: [.foregroundColor: row.tone == .urgent ? NSColor.systemRed : NSColor.systemOrange,
                                 .font: NSFont.menuFont(ofSize: 0)])
            }
            if let checked = row.checked { item.state = checked ? .on : .off }
            item.toolTip = row.tip
            if !row.children.isEmpty {
                let sub = NSMenu()
                sub.autoenablesItems = false
                items(row.children).forEach(sub.addItem)
                item.submenu = sub
            }
            if let act = row.act {
                item.target = self
                item.action = #selector(clicked(_:))
                item.representedObject = Boxed(act)
            }
            item.isEnabled = row.enabled
            return item
        }
    }

    @objc private func clicked(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? Boxed else { return }
        actions.perform(box.act)
    }

    // A notification still shows while one of our own dialogs is in front.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }
}
