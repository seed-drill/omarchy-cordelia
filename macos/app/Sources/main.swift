// Cordelia for the macOS menu bar: the native twin of the Omarchy panel.
//
//   Cordelia                       run the menu bar item
//   Cordelia --dump-menu           print the menu as text and exit; with
//       [--status-file F]          a saved `status --json` instead of the node,
//       [--config F] [--home D]    another settings file or home directory
//       [--node-agent S]           ok, needs-approval or absent, instead of asking macOS
//   Cordelia --login-item on|off|status   open this app at login, or not
//   Cordelia --make-iconset DIR    write the app icon's PNGs (used by build.sh)
//   Cordelia --version

import AppKit

let arguments = Array(CommandLine.arguments.dropFirst())

func option(_ flag: String) -> String? {
    guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
    return arguments[i + 1]
}

if arguments.contains("--version") {
    print("Cordelia menu \(APP_VERSION) (panel \(TRACKS))")
    exit(0)
}

if arguments.contains("--dump-menu") {
    let home = option("--home") ?? NSHomeDirectory()
    let config = Config.load(path: option("--config") ?? home + "/.config/cordelia/menubar.json", home: home)
    let status: JSON
    // A saved status is drawn as if the node will start at login, unless the test says otherwise.
    var agent = option("--node-agent").flatMap(NodeAgent.init(rawValue:))
    if let file = option("--status-file") {
        if agent == nil { agent = .ok }
        guard let data = FileManager.default.contents(atPath: file) else {
            FileHandle.standardError.write("cannot read \(file)\n".data(using: .utf8)!)
            exit(2)
        }
        status = (try? JSONSerialization.jsonObject(with: data)) as? JSON ?? [:]
    } else {
        status = CLI(command: config.command).status()
    }
    let tree = buildMenu(Model(status: status, home: home), config: config, home: home,
                         nodeAgent: agent ?? nodeAgentState(home: home))
    print(dump(tree), terminator: "")
    exit(0)
}

if let want = option("--login-item") {
    if want == "on" || want == "off", let problem = setOpenAtLogin(want == "on") {
        FileHandle.standardError.write("could not change the login item: \(problem)\n".data(using: .utf8)!)
        exit(1)
    }
    print(openAtLoginStatus())
    exit(0)
}

if let dir = option("--make-iconset") {
    exit(makeIconset(dir) ? 0 : 1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
