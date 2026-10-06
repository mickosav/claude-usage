import AppKit
import ServiceManagement

// `--login-item=on|off|status` sets or prints the Start-at-login state and
// exits without showing the UI. Same SMAppService toggle as the right-click
// menu; exists so the login item can be driven and verified from a terminal:
//   /Applications/ClaudeUsage.app/Contents/MacOS/ClaudeUsage --login-item=status
if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--login-item=") }) {
    let want = String(arg.dropFirst("--login-item=".count))
    let service = SMAppService.mainApp
    do {
        switch want {
        case "on":  if service.status != .enabled { try service.register() }
        case "off": if service.status == .enabled { try service.unregister() }
        case "status": break
        default:
            FileHandle.standardError.write(Data("usage: --login-item=on|off|status\n".utf8))
            exit(2)
        }
    } catch {
        FileHandle.standardError.write(Data("login item: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
    let label: String
    switch service.status {
    case .enabled:          label = "enabled"
    case .requiresApproval: label = "requiresApproval (allow it in System Settings > General > Login Items)"
    case .notRegistered:    label = "notRegistered"
    case .notFound:         label = "notFound"
    @unknown default:       label = "unknown"
    }
    print("login item: \(label)")
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
    _ = delegate  // keep alive; NSApplication.delegate is weak
}
