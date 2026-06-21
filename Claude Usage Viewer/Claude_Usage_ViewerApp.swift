// Claude_Usage_ViewerApp.swift
// Claude Usage Viewer
//
// A menu-bar app that surfaces your Claude Code 5-hour and 7-day usage
// windows, reading the OAuth token from the keychain entry the Claude
// Code CLI already maintains ("Claude Code-credentials").

import SwiftUI
import AppKit
import Observation

// MARK: - Models

struct UsageSnapshot: Codable, Equatable {
    var fiveHourPct:   Double?
    var sevenDayPct:   Double?
    var fiveHourReset: Date?
    var sevenDayReset: Date?
    var fetchedAt:     Date
}

private nonisolated struct APIWindow: Decodable, Sendable {
    let utilization: Double?
    let resets_at:   String?
}

private nonisolated struct APIUsage: Decodable, Sendable {
    let five_hour: APIWindow?
    let seven_day: APIWindow?
}

// MARK: - Errors

nonisolated enum UsageError: LocalizedError, Sendable {
    case noCredentials
    case unauthorized
    case rateLimited(retryAt: Date)
    case network(String)
    case http(Int)
    case decoding

    var errorDescription: String? {
        switch self {
        case .noCredentials:        return "No Claude Code credentials found.\nRun: claude login"
        case .unauthorized:         return "Credentials expired.\nRun: claude login"
        case .rateLimited(let at):  return "Rate limited by Anthropic.\nNext attempt in \(Self.minutesUntil(at)) min."
        case .network(let m):       return "Network error:\n\(m)"
        case .http(let c):          return "API error: HTTP \(c)"
        case .decoding:             return "Could not parse response."
        }
    }

    private static func minutesUntil(_ date: Date) -> Int {
        max(1, Int((date.timeIntervalSinceNow / 60).rounded(.up)))
    }
}

// MARK: - Keychain

nonisolated enum Keychain {
    // Reads the OAuth access token from the keychain item maintained by the
    // Claude Code CLI. The first call from a freshly-built binary will trigger
    // a one-time "Always Allow" prompt; clicking Always Allow persists access
    // for that binary signature.
    static func claudeAccessToken() throws -> String {
        let query: [String: Any] = [
            kSecClass       as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData  as String: true,
            kSecMatchLimit  as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data  = item as? Data,
              let json  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String
        else { throw UsageError.noCredentials }
        return token
    }
}

// MARK: - API client

// We mimic the Claude Code CLI's User-Agent so the OAuth usage endpoint
// accepts us. Bump this when the upstream CLI bumps. (We can't query the
// installed CLI from a sandboxed app — its binary path isn't reachable.)
private nonisolated let claudeCodeUserAgent = "claude-code/2.0.31"

actor UsageClient {
    // Cached so we only hit the keychain (and prompt the user) once per
    // launch, instead of on every 15-minute refresh.
    private var cachedToken: String?

    func fetch() async throws -> UsageSnapshot {
        do {
            return try await request(token: try token())
        } catch UsageError.unauthorized {
            cachedToken = nil
            return try await request(token: try token())
        }
    }

    private func token() throws -> String {
        if let cachedToken { return cachedToken }
        let fresh = try Keychain.claudeAccessToken()
        cachedToken = fresh
        return fresh
    }

    private func request(token: String) async throws -> UsageSnapshot {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.setValue("application/json",   forHTTPHeaderField: "Accept")
        req.setValue("application/json",   forHTTPHeaderField: "Content-Type")
        req.setValue(claudeCodeUserAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("Bearer \(token)",    forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20",   forHTTPHeaderField: "anthropic-beta")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw UsageError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw UsageError.network("No response from server.")
        }
        if http.statusCode == 401 { throw UsageError.unauthorized }
        if http.statusCode == 429 {
            // Honor Retry-After if present; default to 1 hour otherwise.
            let retryAt = Self.parseRetryAfter(http) ?? Date().addingTimeInterval(60 * 60)
            throw UsageError.rateLimited(retryAt: retryAt)
        }
        guard http.statusCode == 200 else { throw UsageError.http(http.statusCode) }

        guard let api = try? JSONDecoder().decode(APIUsage.self, from: data) else {
            throw UsageError.decoding
        }

        return UsageSnapshot(
            fiveHourPct:   api.five_hour?.utilization,
            sevenDayPct:   api.seven_day?.utilization,
            fiveHourReset: api.five_hour?.resets_at.flatMap(Self.parseDate),
            sevenDayReset: api.seven_day?.resets_at.flatMap(Self.parseDate),
            fetchedAt:     Date()
        )
    }

    private static func parseDate(_ iso: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }

    // Retry-After can be either an integer (seconds) or an HTTP-date.
    private static func parseRetryAfter(_ http: HTTPURLResponse) -> Date? {
        guard let raw = http.value(forHTTPHeaderField: "Retry-After") else { return nil }
        let val = raw.trimmingCharacters(in: .whitespaces)
        if let secs = TimeInterval(val) {
            return Date().addingTimeInterval(secs)
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f.date(from: val)
    }
}

// MARK: - Store

@MainActor
@Observable
final class UsageStore {
    private(set) var snapshot:           UsageSnapshot?
    private(set) var error:              UsageError?
    private(set) var isLoading:          Bool   = false
    // While in cooldown after a 429, suppress further network calls.
    private(set) var nextAllowedFetch:   Date?

    @ObservationIgnored private let client   = UsageClient()
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private static let snapshotKey = "lastSnapshot"

    init() {
        // Restore last-known usage so the menu bar shows real numbers the
        // moment the app launches, even before the first network call.
        if let data  = defaults.data(forKey: Self.snapshotKey),
           let saved = try? JSONDecoder().decode(UsageSnapshot.self, from: data) {
            snapshot = saved
        }
    }

    var canRefresh: Bool {
        if isLoading { return false }
        if let next = nextAllowedFetch, Date() < next { return false }
        return true
    }

    func refresh() async {
        if !canRefresh { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let fresh = try await client.fetch()
            snapshot          = fresh
            error             = nil
            nextAllowedFetch  = nil
            if let data = try? JSONEncoder().encode(fresh) {
                defaults.set(data, forKey: Self.snapshotKey)
            }
        } catch let usageError as UsageError {
            error = usageError
            if case .rateLimited(let retryAt) = usageError {
                nextAllowedFetch = retryAt
            }
        } catch {
            self.error = .network(error.localizedDescription)
        }
    }

    var menuBarTitle: String {
        let pcts = [snapshot?.fiveHourPct, snapshot?.sevenDayPct].compactMap { $0 }
        guard let top = pcts.max() else { return "⚡" }
        let icon = top >= 80 ? "🔴" : top >= 50 ? "🟡" : "🟢"
        return "\(icon) \(Int(top.rounded()))%"
    }
}

// MARK: - Views

struct UsageRowView: View {
    let label:    String
    let pct:      Double?
    let resetsAt: Date?
    let now:      Date

    private var barColor: Color {
        guard let p = pct else { return .gray }
        return p >= 80 ? .red : p >= 50 ? .yellow : .green
    }

    private var resetText: String {
        guard let resetsAt else { return "—" }
        let delta = resetsAt.timeIntervalSince(now)
        guard delta > 0 else { return "reset" }
        let h = Int(delta) / 3600
        let m = (Int(delta) % 3600) / 60
        let dur = h > 0 ? "\(h)h \(m)m" : "\(m)m"
        return "resets in \(dur)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(pct.map { String(format: "%.0f%%", $0) } ?? "—")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(barColor)
                Text(resetText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor)
                        .frame(
                            width:  geo.size.width * CGFloat((pct ?? 0) / 100.0),
                            height: 6
                        )
                        .animation(.easeInOut(duration: 0.4), value: pct)
                }
            }
            .frame(height: 6)
        }
    }
}

struct MenuPopoverView: View {
    let store: UsageStore

    var body: some View {
        // TimelineView gives us a once-per-minute `ctx.date` so the
        // "resets in 2h 14m" countdown actually ticks while open.
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Claude Code Usage").font(.headline)
                    Spacer()
                    if let fetched = store.snapshot?.fetchedAt {
                        Text("updated \(fetched, format: .relative(presentation: .numeric))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 2)

                if store.snapshot == nil, let err = store.error {
                    Text(err.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    UsageRowView(
                        label:    "5-Hour Window",
                        pct:      store.snapshot?.fiveHourPct,
                        resetsAt: store.snapshot?.fiveHourReset,
                        now:      ctx.date
                    )
                    UsageRowView(
                        label:    "7-Day Window",
                        pct:      store.snapshot?.sevenDayPct,
                        resetsAt: store.snapshot?.sevenDayReset,
                        now:      ctx.date
                    )
                    if let err = store.error {
                        // Refresh failed but we still have stale data — keep
                        // showing it, but warn the user the numbers are old.
                        Text(err.localizedDescription)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Divider()

                HStack {
                    Button(store.isLoading ? "Refreshing…" : "Refresh") {
                        Task { await store.refresh() }
                    }
                    .keyboardShortcut("r")
                    .disabled(!store.canRefresh)

                    Spacer()

                    Button("claude.ai") {
                        NSWorkspace.shared.open(URL(string: "https://claude.ai")!)
                    }

                    Spacer()

                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                    .keyboardShortcut("q")
                }
                .buttonStyle(.plain)
                .font(.caption)
            }
            .padding(14)
            .frame(width: 280)
        }
    }
}

// MARK: - App entry point

@main
struct Claude_Usage_ViewerApp: App {
    @State private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra {
            MenuPopoverView(store: store)
        } label: {
            Text(store.menuBarTitle)
                .task {
                    await store.refresh()
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(15 * 60))
                        if Task.isCancelled { break }
                        await store.refresh()
                    }
                }
        }
        .menuBarExtraStyle(.window)
    }
}
