import AppKit
import SwiftUI
import Combine
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = UsageStore()
    private var statusItem: NSStatusItem!
    private var panel: UsagePanel!
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private let intervalKey = "refreshMinutes"
    private let intervalOptions = [0, 2, 5, 15, 30]   // 0 = Off
    private var refreshMinutes: Int {
        // Unset => 5 min default; explicit 0 => Off.
        guard UserDefaults.standard.object(forKey: intervalKey) != nil else { return 5 }
        return UserDefaults.standard.integer(forKey: intervalKey)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.image = StatusItemRenderer.placeholderImage()
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        panel = UsagePanel(
            rootView: PopoverView(store: store,
                                  onSetKey: { [weak self] in self?.promptForKey() },
                                  onQuit: { NSApp.terminate(nil) })
        )

        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.updateStatusItem() }
            .store(in: &cancellables)

        store.onFetched = { [weak self] in self?.scheduleTimer() }

        updateStatusItem()
        scheduleTimer()

        if store.hasSessionKey {
            Task { await store.refresh() }
        } else {
            promptForKey()
        }
    }

    // MARK: - Status item rendering

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        if let usage = store.usage {
            button.image = StatusItemRenderer.image(session: usage.session, weekly: usage.weeklyAll,
                                                    muted: store.isStale)
            button.attributedTitle = title("\(Int(usage.session.percent.rounded()))%")
            let base = "Session \(Int(usage.session.percent.rounded()))% · Weekly \(Int(usage.weeklyAll.percent.rounded()))%"
            button.toolTip = store.isOnline ? base : base + " · Offline"
        } else {
            button.image = StatusItemRenderer.placeholderImage()
            button.attributedTitle = title(store.hasSessionKey ? "…" : "")
            button.toolTip = store.errorMessage ?? "ClaudeUsage"
        }
    }

    // Standard menu-bar font with monospaced digits so the % doesn't jitter.
    // Leading space gives a small gap after the bars; color is left to the
    // button so the menu bar tints it for light/dark automatically.
    private func title(_ text: String) -> NSAttributedString {
        NSAttributedString(string: " " + text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular),
        ])
    }

    // MARK: - Click handling

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if panel.isVisible {
            panel.close()
        } else {
            Task { await store.refreshIfStale() }
            panel.show(below: button)
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Refresh now", action: #selector(refreshNow), keyEquivalent: "r")
            .target = self

        let intervalItem = NSMenuItem(title: "Update interval", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for m in intervalOptions {
            let item = NSMenuItem(title: m == 0 ? "Off" : "\(m) minutes",
                                  action: #selector(setInterval(_:)), keyEquivalent: "")
            item.target = self
            item.tag = m
            item.state = (m == refreshMinutes) ? .on : .off
            sub.addItem(item)
        }
        intervalItem.submenu = sub
        menu.addItem(intervalItem)

        let login = NSMenuItem(title: "Start at login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = isLoginEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Set session key…", action: #selector(promptForKeyMenu), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit ClaudeUsage", action: #selector(quit), keyEquivalent: "q")
            .target = self

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: - Menu actions

    @objc private func refreshNow() { Task { await store.refresh() } }

    @objc private func setInterval(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.tag, forKey: intervalKey)
        scheduleTimer()
    }

    @objc private func promptForKeyMenu() { promptForKey() }

    @objc private func quit() { NSApp.terminate(nil) }

    private func promptForKey() {
        if let key = SessionKeyPrompt.show(existing: store.hasSessionKey) {
            store.setSessionKey(key)
        }
    }

    // MARK: - Login item

    private var isLoginEnabled: Bool {
        if #available(macOS 13, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }

    @objc private func toggleLogin() {
        guard #available(macOS 13, *) else { return }
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSSound.beep()
        }
    }

    // MARK: - Timer

    private func scheduleTimer() {
        timer?.invalidate()
        timer = nil
        guard refreshMinutes > 0 else { return }   // "Off"
        let interval = TimeInterval(refreshMinutes * 60)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.store.refresh() }
        }
    }
}
