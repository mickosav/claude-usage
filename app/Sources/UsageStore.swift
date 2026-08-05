import Foundation
import Combine
import Network

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var usage: Usage?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isOnline = true
    @Published private(set) var authExpired = false
    @Published var hasSessionKey: Bool

    /// Showing last-good data that we couldn't refresh (failed fetch or offline).
    var isStale: Bool { usage != nil && (errorMessage != nil || !isOnline) }

    /// Called after every successful fetch so the owner can reset the auto-poll timer.
    var onFetched: (() -> Void)?

    private let client = UsageClient()
    private let monitor = NWPathMonitor()
    private var lastManualRefresh: Date?
    private let manualDebounce: TimeInterval = 3
    private let openFreshness: TimeInterval = 60

    init() {
        hasSessionKey = Keychain.loadSessionKey() != nil
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.networkChanged(online: online) }
        }
        monitor.start(queue: DispatchQueue(label: "com.milutin.claudeusage.network"))
    }

    private func networkChanged(online: Bool) {
        let cameBackOnline = online && !isOnline
        isOnline = online
        if cameBackOnline { Task { await refresh() } }   // fetch once on reconnect
    }

    func setSessionKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Keychain.saveSessionKey(trimmed)
        hasSessionKey = true
        authExpired = false
        errorMessage = nil
        Task { await refresh() }
    }

    /// Fetch only if there's no data yet or it's older than the freshness window.
    func refreshIfStale() async {
        guard let u = usage else { await refresh(); return }
        if Date().timeIntervalSince(u.fetchedAt) > openFreshness { await refresh() }
    }

    /// User tapped refresh. Short-circuits if a fetch is in flight or one happened
    /// within the debounce window.
    func manualRefresh() async {
        if isLoading { return }
        if let last = lastManualRefresh, Date().timeIntervalSince(last) < manualDebounce { return }
        lastManualRefresh = Date()
        await refresh()
    }

    func refresh() async {
        guard let key = Keychain.loadSessionKey() else {
            hasSessionKey = false
            errorMessage = UsageError.noSessionKey.errorDescription
            return
        }
        hasSessionKey = true
        guard isOnline else { return }   // keep last-good data; UI shows the offline state

        isLoading = true
        defer { isLoading = false }
        do {
            usage = try await client.fetch(sessionKey: key)
            errorMessage = nil
            authExpired = false
            onFetched?()
        } catch {
            if case UsageError.unauthorized = error { authExpired = true }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
