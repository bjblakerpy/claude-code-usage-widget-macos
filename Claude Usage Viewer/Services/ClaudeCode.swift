// ClaudeCode.swift
// Claude Usage Viewer
//
// Everything we read from the local Claude Code install: its login (from
// the keychain) and its version (for the User-Agent).

import Foundation

nonisolated enum AppPaths {
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    static var supportDir: URL {
        home.appendingPathComponent("Library/Application Support/Claude Usage Viewer", isDirectory: true)
    }

    static var historyFile: URL { supportDir.appendingPathComponent("history.json") }

    // Claude Code honours CLAUDE_CONFIG_DIR; default is ~/.claude.
    static var claudeConfigDir: URL {
        if let dir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !dir.isEmpty {
            return URL(fileURLWithPath: (dir as NSString).expandingTildeInPath, isDirectory: true)
        }
        return home.appendingPathComponent(".claude", isDirectory: true)
    }

    static var statusLineInstaller: StatusLineInstaller {
        StatusLineInstaller(settingsURL: claudeConfigDir.appendingPathComponent("settings.json"),
                            supportDir: supportDir)
    }
}

nonisolated enum CredentialReader {
    // Reads through /usr/bin/security rather than SecItemCopyMatching.
    // Claude Code creates the item with that tool, so it's on the item's
    // access list: no keychain prompt, even after a rebuild changes our
    // code signature. (This is why the app is no longer sandboxed.)
    static func read() async throws -> ClaudeCredentials {
        let out = try await ProcessRunner.run(
            "/usr/bin/security", ["find-generic-password", "-s", "Claude Code-credentials", "-w"])
        guard out.status == 0 else { throw UsageError.noCredentials }
        return try ClaudeCredentials.parse(out.stdout)
    }
}

actor ClaudeCLI {
    private var cached: (version: String?, at: Date)?

    private static let candidates = [
        "~/.local/bin/claude", "~/.claude/local/claude",
        "/opt/homebrew/bin/claude", "/usr/local/bin/claude",
    ].map { ($0 as NSString).expandingTildeInPath }

    func userAgent() async -> String {
        if let cached, Date().timeIntervalSince(cached.at) < 6 * 3600 {
            return CLIVersion.userAgent(cached.version)
        }
        let version = await Self.installedVersion()
        cached = (version, Date())
        return CLIVersion.userAgent(version)
    }

    // The native installer symlinks to …/versions/<x.y.z>, so the version is
    // usually in the resolved path; otherwise ask the binary.
    private static func installedVersion() async -> String? {
        let fm = FileManager.default
        for path in candidates where fm.isExecutableFile(atPath: path) {
            let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            if let v = CLIVersion.parse(resolved) { return v }
            if let out = try? await ProcessRunner.run(path, ["--version"]),
               out.status == 0, let v = CLIVersion.parse(String(decoding: out.stdout, as: UTF8.self)) {
                return v
            }
        }
        return nil
    }
}
