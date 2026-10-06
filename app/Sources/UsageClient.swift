import Foundation

enum LimitSeverity: String {
    case normal, warning, exceeded

    init(payload: String?, percent: Double) {
        switch payload {
        case "warning", "approaching": self = .warning
        case "exceeded", "critical", "blocked": self = .exceeded
        case "normal": self = .normal
        default:
            // Fall back to thresholds when the API omits/renames severity.
            self = percent >= 95 ? .exceeded : (percent >= 80 ? .warning : .normal)
        }
    }
}

struct UsageLimit {
    var percent: Double
    var resetsAt: Date?
    var severity: LimitSeverity
    var isUsed: Bool   // false => "You haven't used X yet"
}

/// A weekly limit scoped to one model family ("Sonnet", "Fable", ...). claude.ai
/// shows one row per scoped limit under "Weekly limits"; the set varies by plan.
struct ScopedLimit {
    var name: String        // model display name as the API reports it
    var limit: UsageLimit
}

struct Usage {
    var session: UsageLimit
    var weeklyAll: UsageLimit
    var weeklyScoped: [ScopedLimit]   // in API order; empty if the plan has none
    var planLabel: String?
    var fetchedAt: Date
}

enum UsageError: LocalizedError {
    case noSessionKey
    case unauthorized      // session key rejected by claude.ai (not a Cloudflare block)
    case http(Int)
    case parse
    case noOrganization
    case network(String)

    var errorDescription: String? {
        switch self {
        case .noSessionKey:    return "No session key set"
        case .unauthorized:    return "Session expired - update your key"
        case .http(let code):  return "Request failed (HTTP \(code))"
        case .parse:           return "Unexpected response from claude.ai"
        case .noOrganization:  return "No organization found for this account"
        case .network(let m):  return m
        }
    }
}

final class UsageClient {
    private let base = "https://claude.ai"

    func fetch(sessionKey: String) async throws -> Usage {
        let orgUUID = try await firstOrg(sessionKey: sessionKey)
        return try await usage(orgUUID: orgUUID.uuid, plan: orgUUID.plan, sessionKey: sessionKey)
    }

    // MARK: - Requests

    private func request(_ path: String, sessionKey: String) -> URLRequest {
        var r = URLRequest(url: URL(string: base + path)!)
        r.httpMethod = "GET"
        r.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        r.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        // Browser-like UA + fetch headers keep Cloudflare from challenging the call.
        r.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                   forHTTPHeaderField: "User-Agent")
        r.setValue("https://claude.ai/settings/usage", forHTTPHeaderField: "Referer")
        r.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
        r.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
        r.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
        r.setValue("empty", forHTTPHeaderField: "Sec-Fetch-Dest")
        return r
    }

    private func getJSON(_ path: String, sessionKey: String) async throws -> Any {
        let data: Data, resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: request(path, sessionKey: sessionKey))
        } catch {
            throw UsageError.network(error.localizedDescription)
        }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard code == 200 else {
            // A rejected session key returns 401/403 with a JSON auth error; a
            // Cloudflare block also returns 403 but as HTML - only the former is
            // a real "session expired".
            if code == 401 || code == 403, let body = String(data: data, encoding: .utf8),
               body.contains("account_session_invalid") || body.contains("Invalid authorization") {
                throw UsageError.unauthorized
            }
            throw UsageError.http(code)
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { throw UsageError.parse }
        return obj
    }

    // MARK: - Organizations

    private func firstOrg(sessionKey: String) async throws -> (uuid: String, plan: String?) {
        guard let arr = try await getJSON("/api/organizations", sessionKey: sessionKey) as? [[String: Any]],
              !arr.isEmpty else { throw UsageError.noOrganization }
        // Prefer an org that exposes chat (the claude.ai usage surface).
        let chat = arr.first { ($0["capabilities"] as? [String])?.contains("chat") == true }
        guard let org = chat ?? arr.first, let uuid = org["uuid"] as? String else {
            throw UsageError.noOrganization
        }
        let plan = (org["raven_type"] as? String).map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return (uuid, plan)
    }

    // MARK: - Usage

    private func usage(orgUUID: String, plan: String?, sessionKey: String) async throws -> Usage {
        guard let obj = try await getJSON("/api/organizations/\(orgUUID)/usage", sessionKey: sessionKey) as? [String: Any]
        else { throw UsageError.parse }

        // The `limits` array is the forward-compatible source; legacy top-level
        // keys (five_hour/seven_day/...) are the fallback.
        let byKind = (obj["limits"] as? [[String: Any]]) ?? []

        func limit(from m: [String: Any]) -> UsageLimit {
            let pct = (m["percent"] as? NSNumber)?.doubleValue ?? 0
            let resets = Self.parseDate(m["resets_at"] as? String)
            let used = pct > 0 || resets != nil
            return UsageLimit(percent: pct, resetsAt: resets,
                              severity: LimitSeverity(payload: m["severity"] as? String, percent: pct),
                              isUsed: used)
        }

        func fromLimits(kind: String) -> UsageLimit? {
            byKind.first { ($0["kind"] as? String) == kind }.map(limit(from:))
        }

        // Every `weekly_scoped` entry, named by its model's display_name.
        func scopedFromLimits() -> [ScopedLimit] {
            byKind.compactMap { m in
                guard (m["kind"] as? String) == "weekly_scoped" else { return nil }
                let model = ((m["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String
                guard let name = model, !name.isEmpty else { return nil }
                return ScopedLimit(name: name, limit: limit(from: m))
            }
        }

        func fromLegacy(_ key: String) -> UsageLimit? {
            guard let d = obj[key] as? [String: Any] else { return nil }
            let pct = (d["utilization"] as? NSNumber)?.doubleValue ?? 0
            let resets = Self.parseDate(d["resets_at"] as? String)
            let used = pct > 0 || resets != nil
            return UsageLimit(percent: pct, resetsAt: resets,
                              severity: LimitSeverity(payload: nil, percent: pct), isUsed: used)
        }

        guard let session = fromLimits(kind: "session") ?? fromLegacy("five_hour"),
              let weekly = fromLimits(kind: "weekly_all") ?? fromLegacy("seven_day")
        else { throw UsageError.parse }

        // Legacy shape only ever had `seven_day_sonnet`; any other `seven_day_<model>`
        // key is picked up the same way so a new model doesn't vanish from the panel.
        func scopedFromLegacy() -> [ScopedLimit] {
            obj.keys.sorted().compactMap { key in
                guard key.hasPrefix("seven_day_"), let l = fromLegacy(key) else { return nil }
                let name = String(key.dropFirst("seven_day_".count))
                return ScopedLimit(name: name.prefix(1).uppercased() + name.dropFirst(), limit: l)
            }
        }

        var scoped = scopedFromLimits()
        if scoped.isEmpty { scoped = scopedFromLegacy() }

        return Usage(session: session, weeklyAll: weekly, weeklyScoped: scoped,
                     planLabel: plan, fetchedAt: Date())
    }

    // MARK: - Date parsing

    static func parseDate(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFrac.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let d = plain.date(from: s) { return d }
        // Microsecond fractions (6 digits) trip ISO8601DateFormatter; trim to millis.
        if let dot = s.firstIndex(of: ".") {
            let tail = s[s.index(after: dot)...]
            if let tzStart = tail.firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
                let trimmed = String(s[..<dot]) + "." + tail[..<tzStart].prefix(3) + tail[tzStart...]
                if let d = withFrac.date(from: trimmed) { return d }
            }
        }
        return nil
    }
}
