import SwiftUI

struct PopoverView: View {
    @ObservedObject var store: UsageStore
    var onSetKey: () -> Void
    var onQuit: () -> Void

    // Ticks so relative times stay fresh while the popover is open (label only,
    // never the network).
    @State private var now = Date()
    private let tick = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.vertical, 14)
            content
            Divider().padding(.vertical, 12)
            footer
        }
        .padding(18)
        .frame(width: 360)
        .onReceive(tick) { now = $0 }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Your usage limits").font(.system(size: 15, weight: .semibold))
            if let plan = store.usage?.planLabel {
                Text(plan).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.hasSessionKey == false {
            needsKey
        } else if store.authExpired {
            sessionExpired
        } else if let usage = store.usage {
            usageBody(usage)
                .opacity(store.isStale ? 0.5 : 1)   // dim last-good data we couldn't refresh
        } else if let err = store.errorMessage {
            errorState(err)
        } else {
            HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
                .frame(height: 80)
        }
    }

    private func usageBody(_ usage: Usage) -> some View {
        VStack(alignment: .leading, spacing: 18) {
                LimitRow(title: "Current session",
                         subtitle: Self.sessionReset(usage.session.resetsAt, now: now),
                         limit: usage.session, notUsedText: nil)

                VStack(alignment: .leading, spacing: 14) {
                    Text("Weekly limits").font(.system(size: 14, weight: .semibold))

                    LimitRow(title: "All models",
                             subtitle: Self.weeklyReset(usage.weeklyAll.resetsAt),
                             limit: usage.weeklyAll, notUsedText: nil)

                    if let sonnet = usage.weeklySonnet {
                        LimitRow(title: "Sonnet only",
                                 subtitle: sonnet.isUsed ? Self.weeklyReset(sonnet.resetsAt) : nil,
                                 limit: sonnet,
                                 notUsedText: sonnet.isUsed ? nil : "You haven't used Sonnet yet")
                    }
                }
        }
    }

    private var needsKey: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connect your account").font(.system(size: 14, weight: .semibold))
            Text("Paste your claude.ai session key to start tracking usage.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Button("Set session key…", action: onSetKey)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func errorState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            HStack {
                Button("Retry") { Task { await store.refresh() } }
                Button("Update key…", action: onSetKey)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sessionExpired: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Session expired", systemImage: "lock.slash")
                .font(.system(size: 14, weight: .semibold))
            Text("Your claude.ai session key is no longer valid. Open claude.ai, copy a fresh sessionKey cookie, and paste it here.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Update session key…", action: onSetKey)
                Link("Open claude.ai", destination: URL(string: "https://claude.ai/settings/usage")!)
                    .font(.system(size: 12))
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if let usage = store.usage {
                // `now` is referenced so the 15s tick re-renders this; the age is
                // recomputed from the real clock and clamped to avoid future times.
                Text(footerStatus(usage))
                    .font(.system(size: 11))
                    .foregroundStyle(store.isStale ? Color.orange : Color.secondary)
            }
            Button {
                Task { await store.manualRefresh() }
            } label: {
                if store.isLoading {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11))
                }
            }
            .buttonStyle(.borderless)
            .disabled(store.isLoading)
            .help("Refresh now")
            .accessibilityLabel("Refresh usage")

            Spacer()
            Menu {
                Button("Set session key…", action: onSetKey)
                Button("Quit ClaudeUsage", action: onQuit)
            } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 12))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private func footerStatus(_ usage: Usage) -> String {
        let age = Self.lastUpdated(since: usage.fetchedAt, now: max(now, Date()))
        if !store.isOnline { return "Offline · \(age)" }
        if store.errorMessage != nil { return "Couldn't refresh · \(age)" }
        return age
    }

    // MARK: - Formatting

    static func sessionReset(_ date: Date?, now: Date) -> String? {
        guard let date else { return nil }
        let secs = Int(date.timeIntervalSince(now))
        guard secs > 0 else { return "Resetting now" }
        let h = secs / 3600, m = (secs % 3600) / 60
        if h > 0 { return "Resets in \(h) hr \(m) min" }
        if m > 0 { return "Resets in \(m) min" }
        return "Resets in less than a minute"
    }

    static func weeklyReset(_ date: Date?) -> String? {
        guard let date else { return nil }
        let f = DateFormatter()
        f.dateFormat = "EEE h:mm a"
        return "Resets \(f.string(from: date))"
    }

    static func lastUpdated(since date: Date, now: Date) -> String {
        let s = max(0, now.timeIntervalSince(date))   // clamp: never a future time
        switch s {
        case ..<10:    return "Updated just now"
        case ..<60:    return "Updated less than a minute ago"
        case ..<3600:  return "Updated \(Int(s / 60)) min ago"
        case ..<86400: return "Updated \(Int(s / 3600)) hr ago"
        default:
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return "Updated at \(f.string(from: date))"
        }
    }
}

private struct LimitRow: View {
    let title: String
    let subtitle: String?
    let limit: UsageLimit
    let notUsedText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    if let notUsedText {
                        Text(notUsedText).font(.system(size: 11)).foregroundStyle(.secondary)
                    } else if let subtitle {
                        Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text("\(Int(limit.percent.rounded()))% used")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            ProgressBar(percent: limit.percent, color: barColor)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        let pct = "\(Int(limit.percent.rounded()))% used"
        if let notUsedText { return notUsedText }
        if let subtitle { return "\(pct), \(subtitle)" }
        return pct
    }

    private var barColor: Color {
        switch limit.severity {
        case .normal:   return .blue
        case .warning:  return .orange
        case .exceeded: return .red
        }
    }
}

private struct ProgressBar: View {
    let percent: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.25))
                Capsule().fill(color)
                    .frame(width: max(percent > 0 ? 6 : 0,
                                      geo.size.width * CGFloat(min(100, max(0, percent)) / 100)))
            }
        }
        .frame(height: 6)
    }
}
