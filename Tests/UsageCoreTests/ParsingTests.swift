import Foundation
import Testing
@testable import UsageCore

@Suite struct APIParserTests {
    let now = Date(timeIntervalSince1970: 1_792_200_000)

    func fixture() throws -> Data {
        let url = try #require(Bundle.module.url(forResource: "usage-response", withExtension: "json",
                                                 subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test func parsesLimitsListFromFullResponse() throws {
        let s = try UsageAPIParser.parse(fixture(), now: now)
        #expect(s.limits.map(\.kind) == ["session", "weekly_all"])
        #expect(s.limits[0].percent == 42)
        #expect(s.limits[0].group == .session)
        #expect(s.limits[0].title == "Session (5-hour)")
        #expect(s.limits[1].group == .weekly)
        #expect(s.limits[0].resetsAt == HTTPParsing.isoDate("2030-01-01T05:00:00.123456+00:00"))
        #expect(s.fetchedAt == now)
    }

    @Test func parsesExtraUsageAndBreakdown() throws {
        let s = try UsageAPIParser.parse(fixture(), now: now)
        #expect(s.extraUsage?.used.amount == 12.34)
        #expect(s.extraUsage?.limit?.amount == 100)
        #expect(s.weeklyBreakdown.map(\.key) == ["claude_code", "chat", "cowork"])  // zero rows dropped
    }

    @Test func fallsBackToLegacyWindows() throws {
        let json = """
        {"five_hour":{"utilization":23.0,"resets_at":"2026-10-17T03:20:00.860031+00:00"},
         "seven_day":{"utilization":4.0,"resets_at":"2026-10-23T11:00:00+00:00"},
         "seven_day_opus":{"utilization":12,"resets_at":null},
         "seven_day_sonnet":null}
        """
        let s = try UsageAPIParser.parse(Data(json.utf8), now: now)
        #expect(s.limits.map(\.kind) == ["session", "weekly_all", "weekly_opus"])
        #expect(s.limits[2].title == "Weekly (Opus)")
        #expect(s.limits[2].resetsAt == nil)
        #expect(s.extraUsage == nil)
    }

    @Test func skipsMalformedLimitEntriesInsteadOfFailing() throws {
        let json = """
        {"limits":[{"kind":"session","percent":"oops"},
                   {"kind":"weekly_all","group":"weekly","percent":11,"severity":"critical",
                    "resets_at":"2026-10-23T11:00:00.437889+00:00"},
                   {"kind":"weekly_scoped","group":"weekly","percent":true,"scope":"Opus"}]}
        """
        let s = try UsageAPIParser.parse(Data(json.utf8), now: now)
        #expect(s.limits.map(\.kind) == ["weekly_all"])
        #expect(s.limits[0].serverSeverity == .critical)
    }

    @Test func scopedLimitUsesScopeInTitle() {
        #expect(UsageLimit.title(kind: "weekly_scoped", scope: "Opus") == "Weekly (Opus)")
        #expect(UsageLimit.title(kind: "weekly_fable_max", scope: nil) == "Weekly (Fable Max)")
        #expect(UsageLimit.title(kind: "monthly_thing", scope: nil) == "Monthly Thing")
    }

    @Test func rejectsResponsesWithNoLimits() {
        #expect(throws: UsageError.decoding) { try UsageAPIParser.parse(Data("{}".utf8), now: now) }
        #expect(throws: UsageError.decoding) { try UsageAPIParser.parse(Data("[]".utf8), now: now) }
    }
}

@Suite struct HTTPParsingTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func retryAfterSeconds() {
        #expect(HTTPParsing.retryAfter("292", now: now) == now.addingTimeInterval(292))
        #expect(HTTPParsing.retryAfter(" 0 ", now: now) == now)
    }

    @Test func retryAfterHTTPDate() {
        let d = HTTPParsing.retryAfter("Wed, 21 Oct 2015 07:28:00 GMT", now: now)
        #expect(d == Date(timeIntervalSince1970: 1_445_412_480))
    }

    @Test func retryAfterMissingOrGarbage() {
        #expect(HTTPParsing.retryAfter(nil, now: now) == nil)
        #expect(HTTPParsing.retryAfter("soon", now: now) == nil)
    }

    @Test func isoDatesWithAndWithoutFractions() {
        #expect(HTTPParsing.isoDate("2026-10-23T11:00:00+00:00") == Date(timeIntervalSince1970: 1_792_753_200))
        let micro = HTTPParsing.isoDate("2026-10-23T11:00:00.437889+00:00")
        #expect(micro != nil)
        #expect(abs(micro!.timeIntervalSince1970 - 1_792_753_200.437) < 0.01)
    }
}

@Suite struct StatusLineFeedTests {
    let now = Date(timeIntervalSince1970: 1_792_200_000)

    @Test func parsesBareRateLimits() {
        let json = #"{"five_hour":{"used_percentage":65,"resets_at":1792206000},"seven_day":{"used_percentage":11.5,"resets_at":1792753200}}"#
        let limits = StatusLineFeed.parse(Data(json.utf8), observedAt: now, now: now)
        #expect(limits.map(\.kind) == ["session", "weekly_all"])
        #expect(limits[1].percent == 11.5)
        #expect(limits[0].resetsAt == Date(timeIntervalSince1970: 1_792_206_000))
        #expect(limits[0].observedAt == now)
    }

    @Test func acceptsFullPayloadAndDropsExpiredWindows() {
        let json = #"{"model":{"id":"x"},"rate_limits":{"five_hour":{"used_percentage":90,"resets_at":1792100000},"seven_day":{"used_percentage":11,"resets_at":1792753200}}}"#
        let limits = StatusLineFeed.parse(Data(json.utf8), observedAt: now, now: now)
        #expect(limits.map(\.kind) == ["weekly_all"])
    }

    @Test func garbageYieldsNothing() {
        #expect(StatusLineFeed.parse(Data("not json".utf8), observedAt: now, now: now).isEmpty)
    }
}

@Suite struct CredentialsTests {
    @Test func parsesKeychainJSON() throws {
        let json = #"{"claudeAiOauth":{"accessToken":"sk-ant-oat01-abc","refreshToken":"r","expiresAt":1792204910715,"subscriptionType":"max","rateLimitTier":"default_claude_max_20x"}}"#
        let c = try ClaudeCredentials.parse(Data(json.utf8))
        #expect(c.planName == "Max 20x")
        #expect(c.expiresAt == Date(timeIntervalSince1970: 1_792_204_910.715))
        #expect(c.isExpired(now: Date(timeIntervalSince1970: 1_792_204_900)))   // inside the 60s margin
        #expect(!c.isExpired(now: Date(timeIntervalSince1970: 1_792_200_000)))
        #expect(!c.description.contains("abc"))
        #expect(c.fingerprint.count == 16)
    }

    @Test func planNameFallsBackToSubscriptionType() throws {
        let json = #"{"claudeAiOauth":{"accessToken":"t","subscriptionType":"pro"}}"#
        #expect(try ClaudeCredentials.parse(Data(json.utf8)).planName == "Pro")
    }

    @Test func missingTokenThrows() {
        #expect(throws: UsageError.noCredentials) {
            try ClaudeCredentials.parse(Data(#"{"claudeAiOauth":{}}"#.utf8))
        }
    }

    @Test func cliVersionParsing() {
        #expect(CLIVersion.parse("2.1.302 (Claude Code)") == "2.1.302")
        #expect(CLIVersion.parse("/Users/x/.local/share/claude/versions/2.1.302") == "2.1.302")
        #expect(CLIVersion.parse("claude") == nil)
        #expect(CLIVersion.userAgent(nil) == "claude-code/\(CLIVersion.fallback)")
    }
}
