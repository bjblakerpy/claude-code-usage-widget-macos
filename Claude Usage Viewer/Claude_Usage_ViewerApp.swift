// Claude_Usage_ViewerApp.swift
// Claude Usage Viewer
//
// Paste this entire file into Claude_Usage_ViewerApp.swift
// Delete ContentView.swift and Item.swift if they exist

import SwiftUI
import AppKit
import Combine

// ── Data model ────────────────────────────────────────────────────────────────
struct UsageWindow: Codable {
    let utilization: Double?
    let resets_at: String?
}

struct UsageResponse: Codable {
    let five_hour: UsageWindow?
    let seven_day: UsageWindow?
}

// ── Helpers ───────────────────────────────────────────────────────────────────
func timeUntilReset(_ isoString: String?) -> String {
    guard let iso = isoString else { return "—" }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let dt = formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    guard let dt else { return "—" }
    let delta = dt.timeIntervalSince(Date())
    guard delta > 0 else { return "resetting soon" }
    let hours   = Int(delta) / 3600
    let minutes = (Int(delta) % 3600) / 60
    if hours > 0 { return "\(hours)h \(minutes)m" }
    return "\(minutes)m"
}

func readKeychainToken() -> String? {
    let query: [String: Any] = [
        kSecClass          as String: kSecClassGenericPassword,
        kSecAttrService    as String: "Claude Code-credentials",
        kSecReturnData     as String: true,
        kSecMatchLimit     as String: kSecMatchLimitOne
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess,
          let data = item as? Data,
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let oauth = json["claudeAiOauth"] as? [String: Any],
          let token = oauth["accessToken"] as? String
    else { return nil }
    return token
}

// ── ViewModel ─────────────────────────────────────────────────────────────────
class UsageViewModel: ObservableObject {
    @Published var fiveHourPct:   Double? = nil
    @Published var sevenDayPct:   Double? = nil
    @Published var fiveHourReset: String  = "—"
    @Published var sevenDayReset: String  = "—"
    @Published var errorMessage:  String? = nil
    @Published var isLoading:     Bool    = false

    var menuBarTitle: String {
        let pcts = [fiveHourPct, sevenDayPct].compactMap { $0 }
        guard !pcts.isEmpty else { return "⚡ Claude" }
        let top  = pcts.max()!
        let icon = top >= 80 ? "🔴" : top >= 50 ? "🟡" : "🟢"
        let fStr = fiveHourPct.map { String(format: "%.0f%%", $0) } ?? "—"
        let sStr = sevenDayPct.map { String(format: "%.0f%%", $0) } ?? "—"
        return "\(icon) \(fStr) | 7d \(sStr)"
    }

    func fetch() {
        DispatchQueue.main.async { self.isLoading = true; self.errorMessage = nil }

        guard let token = readKeychainToken() else {
            DispatchQueue.main.async {
                self.errorMessage = "No Claude Code credentials found.\nRun: claude login"
                self.isLoading = false
            }
            return
        }

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.setValue("application/json",   forHTTPHeaderField: "Accept")
        req.setValue("application/json",   forHTTPHeaderField: "Content-Type")
        req.setValue("claude-code/2.0.31", forHTTPHeaderField: "User-Agent")
        req.setValue("Bearer \(token)",    forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20",   forHTTPHeaderField: "anthropic-beta")

        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                defer { self.isLoading = false }

                if let error = error {
                    self.errorMessage = "Network error:\n\(error.localizedDescription)"
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    self.errorMessage = "No response from server."
                    return
                }
                guard http.statusCode == 200, let data = data else {
                    self.errorMessage = "API error: HTTP \(http.statusCode)\nToken may be expired.\nRun: claude login"
                    return
                }
                guard let usage = try? JSONDecoder().decode(UsageResponse.self, from: data) else {
                    self.errorMessage = "Could not parse response."
                    return
                }
                self.fiveHourPct   = usage.five_hour?.utilization
                self.sevenDayPct   = usage.seven_day?.utilization
                self.fiveHourReset = timeUntilReset(usage.five_hour?.resets_at)
                self.sevenDayReset = timeUntilReset(usage.seven_day?.resets_at)
            }
        }.resume()
    }
}

// ── Usage row with progress bar ───────────────────────────────────────────────
struct UsageRowView: View {
    let label: String
    let pct:   Double?
    let reset: String

    private var barColor: Color {
        guard let p = pct else { return .gray }
        return p >= 80 ? .red : p >= 50 ? .yellow : .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(pct.map { String(format: "%.0f%%", $0) } ?? "—")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(barColor)
                Text("resets \(reset)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor)
                        .frame(
                            width: geo.size.width * CGFloat((pct ?? 0) / 100.0),
                            height: 6
                        )
                        .animation(.easeInOut(duration: 0.4), value: pct)
                }
            }
            .frame(height: 6)
        }
    }
}

// ── Popover content ───────────────────────────────────────────────────────────
struct MenuPopoverView: View {
    @ObservedObject var vm: UsageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Claude Code Usage")
                .font(.headline)
                .padding(.bottom, 2)

            if let err = vm.errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                UsageRowView(label: "5-Hour Window",
                             pct:   vm.fiveHourPct,
                             reset: vm.fiveHourReset)
                UsageRowView(label: "7-Day Window",
                             pct:   vm.sevenDayPct,
                             reset: vm.sevenDayReset)
            }

            Divider()

            HStack {
                Button(vm.isLoading ? "Loading…" : "Refresh") {
                    vm.fetch()
                }
                .disabled(vm.isLoading)

                Spacer()

                Button("claude.ai") {
                    NSWorkspace.shared.open(URL(string: "https://claude.ai")!)
                }

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .buttonStyle(.plain)
            .font(.caption)
        }
        .padding(14)
        .frame(width: 280)
    }
}

// ── App entry point ───────────────────────────────────────────────────────────
@main
struct Claude_Usage_ViewerApp: App {
    @StateObject private var vm = UsageViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuPopoverView(vm: vm)
                .onAppear { vm.fetch() }
        } label: {
            Text(vm.isLoading ? "⚡ …" : vm.menuBarTitle)
        }
        .menuBarExtraStyle(.window)
    }
}
