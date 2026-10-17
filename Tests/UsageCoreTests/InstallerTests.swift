import Foundation
import Testing
@testable import UsageCore

@Suite struct StatusLineInstallerTests {
    let root: URL
    let installer: StatusLineInstaller

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("installer-tests-\(UUID().uuidString)")
        installer = StatusLineInstaller(
            settingsURL: root.appendingPathComponent("claude/settings.json"),
            supportDir:  root.appendingPathComponent("App Support/Claude Usage Viewer")
        )
        try FileManager.default.createDirectory(at: root.appendingPathComponent("claude"),
                                                withIntermediateDirectories: true)
    }

    func settings() throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: installer.settingsURL)) as! [String: Any]
    }

    func writeSettings(_ s: String) throws {
        try Data(s.utf8).write(to: installer.settingsURL)
    }

    @Test func installWithoutExistingStatusLineThenUninstall() throws {
        try writeSettings(#"{"model":"opus","hooks":{}}"#)
        #expect(installer.state() == .notInstalled)
        try installer.install()
        #expect(installer.state() == .installed)
        let s = try settings()
        #expect((s["statusLine"] as? [String: Any])?["command"] as? String == installer.command)
        #expect(s["model"] as? String == "opus")
        #expect(FileManager.default.isExecutableFile(atPath: installer.scriptURL.path))
        #expect(FileManager.default.fileExists(atPath: installer.backupURL.path))

        try installer.uninstall()
        #expect(try settings()["statusLine"] == nil)
        #expect(try settings()["model"] as? String == "opus")
        #expect(installer.state() == .notInstalled)
    }

    @Test func wrapsAndRestoresExistingStatusLine() throws {
        try writeSettings(#"{"statusLine":{"type":"command","command":"echo hi","padding":2}}"#)
        try installer.install()
        let ours = try settings()["statusLine"] as! [String: Any]
        #expect(ours["padding"] as? Int == 2)
        #expect(try String(contentsOf: installer.previousCommandURL, encoding: .utf8) == "echo hi")

        try installer.install()   // idempotent: must not save itself as "previous"
        #expect(try String(contentsOf: installer.previousCommandURL, encoding: .utf8) == "echo hi")

        try installer.uninstall()
        let restored = try settings()["statusLine"] as! [String: Any]
        #expect(restored["command"] as? String == "echo hi")
        #expect(restored["padding"] as? Int == 2)
    }

    @Test func refusesToTouchMalformedSettings() throws {
        try writeSettings("{ not json")
        #expect(throws: StatusLineInstaller.InstallError.self) { try installer.install() }
        #expect(try String(contentsOf: installer.settingsURL, encoding: .utf8) == "{ not json")
    }

    @Test func detectsReplacement() throws {
        try installer.install()
        try writeSettings(#"{"statusLine":{"type":"command","command":"other"}}"#)
        #expect(installer.state() == .replaced)
    }

    // Runs the generated script the way Claude Code does.
    @Test func scriptSavesRateLimitsAndRunsPreviousCommand() throws {
        try writeSettings(#"{"statusLine":{"type":"command","command":"cat >/dev/null; echo previous-output"}}"#)
        try installer.install()

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", installer.command]
        let input = Pipe(), output = Pipe()
        p.standardInput = input
        p.standardOutput = output
        try p.run()
        input.fileHandleForWriting.write(Data(#"{"model":{"id":"x"},"rate_limits":{"five_hour":{"used_percentage":42,"resets_at":1792206000}}}"#.utf8))
        try input.fileHandleForWriting.close()
        p.waitUntilExit()

        let out = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        #expect(out == "previous-output\n")
        let feed = try Data(contentsOf: installer.feedURL)
        let limits = StatusLineFeed.parse(feed, observedAt: t0, now: t0)
        #expect(limits.first?.percent == 42)
        let attrs = try FileManager.default.attributesOfItem(atPath: installer.feedURL.path)
        #expect((attrs[.posixPermissions] as? Int) == 0o600)
    }

    @Test func shellQuoting() {
        #expect(StatusLineInstaller.shellQuote("/a b/it's") == #"'/a b/it'\''s'"#)
    }
}
