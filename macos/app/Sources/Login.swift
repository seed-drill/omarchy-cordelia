// What macOS will do at the next login: start the node, and open this app.
// This is the one thing the menu shows that `cordelia status --json` cannot
// tell it, because the node cannot see it either.

import Foundation
import ServiceManagement

/// Whether macOS will start the node at login. Its launch agent can be loaded
/// and running now while the system has it switched off in Login Items: the
/// installer starts it by hand, and a switch left off by an earlier install
/// under the same label is kept. Sync then stops, silently, at the next login.
func nodeAgentState(home: String) -> NodeAgent {
    let plist = URL(fileURLWithPath: home + "/Library/LaunchAgents/ai.seeddrill.cordelia.plist")
    switch SMAppService.statusForLegacyPlist(at: plist) {
    case .enabled: return .ok
    case .requiresApproval: return .needsApproval
    default: return .absent
    }
}

func openLoginItemsSettings() {
    SMAppService.openSystemSettingsLoginItems()
}

/// This app as a login item of its own, so it is listed under "Open at Login"
/// by name and icon, not as a second background item beside the node's.
/// Returns what went wrong, or nil.
func setOpenAtLogin(_ on: Bool) -> String? {
    do {
        if on {
            if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
        } else if SMAppService.mainApp.status != .notRegistered {
            try SMAppService.mainApp.unregister()
        }
        return nil
    } catch {
        return error.localizedDescription
    }
}

func openAtLoginStatus() -> String {
    switch SMAppService.mainApp.status {
    case .enabled: return "opens at login"
    case .requiresApproval: return "switched off in Login Items"
    case .notRegistered: return "does not open at login"
    case .notFound: return "not found"
    @unknown default: return "unknown"
    }
}
