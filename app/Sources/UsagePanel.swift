import AppKit
import SwiftUI

/// Borderless rounded window shown just below the status item - no popover arrow.
@MainActor
final class UsagePanel {
    private let panel: KeyPanel
    private let hosting: NSHostingView<PopoverView>
    private var clickMonitor: Any?

    var isVisible: Bool { panel.isVisible }

    init(rootView: PopoverView) {
        hosting = NSHostingView(rootView: rootView)
        panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 200),
                         styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false

        let container = NSVisualEffectView()
        container.material = .popover
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.masksToBounds = true

        hosting.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        panel.contentView = container
    }

    func toggle(relativeTo button: NSStatusBarButton) {
        isVisible ? close() : show(below: button)
    }

    func show(below button: NSStatusBarButton) {
        guard let buttonWindow = button.window, let screen = buttonWindow.screen else { return }

        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        panel.setContentSize(size)

        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        var x = buttonRect.midX - size.width / 2
        let minX = screen.visibleFrame.minX + 8
        let maxX = screen.visibleFrame.maxX - size.width - 8
        x = min(max(x, minX), maxX)
        let y = buttonRect.minY - size.height - 4
        panel.setFrameOrigin(NSPoint(x: x, y: y))

        panel.makeKeyAndOrderFront(nil)

        // Dismiss when the user clicks outside the app (the status button click
        // is delivered to its own action, so it won't trip this).
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
    }

    func close() {
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
        panel.orderOut(nil)
    }
}

private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
