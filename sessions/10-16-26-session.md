## Session date
2026-10-16

## What we worked on
- Diagnosed why the Claude Usage Viewer menu-bar app had been showing "API error: HTTP 429" since 2026-10-14, and fixed it.
- Cleared the follow-up items from that fix (manual-refresh retry, stale User-Agent, commit/push).
- Reviewed the app end to end and rebuilt it as v2.0. The goal: a menu-bar widget that tells you at a glance whether you're on track, not just how much you've used.
- Replaced the captured API test fixture with made-up values.

## Changes made
Repo: `bjblakerpy/claude-code-usage-widget-macos` (all pushed to `main`; latest commit `7d042fe`)

Commit `b407c05`: retry on Retry-After, bump User-Agent
- `Claude Usage Viewer/Claude_Usage_ViewerApp.swift`: scheduled the next fetch on a wall clock owned by the store (Retry-After + 5–45 s jitter after a 429, otherwise 15 min). A 429 from manual Refresh now reschedules the loop too. User-Agent bumped to `claude-code/2.1.302`.

Commit `3f85e21`: v2.0 rebuild
- `Claude Usage Viewer/Core/Models.swift`: value types (`UsageLimit`, `UsageSnapshot`, `Severity`, `Money`, `ExtraUsage`, `BreakdownRow`, `UsageError`) and `UsageMerger`, which combines API and feed data, newest observation wins, and treats a passed reset as 0%.
- `Claude Usage Viewer/Core/APIParser.swift`: lenient parser for `/api/oauth/usage`. Reads the generic `limits` list (falling back to the legacy `five_hour`/`seven_day` fields), the weekly breakdown by product, and extra-usage spend.
- `Claude Usage Viewer/Core/StatusLineFeed.swift`: parses the `rate_limits` object Claude Code passes to status-line scripts.
- `Claude Usage Viewer/Core/Projection.swift`: burn rate (recent slope, else window average) → projected time to limit, severity, and the even-pace marker.
- `Claude Usage Viewer/Core/History.swift`: per-limit samples, deduplicated with a 5-minute heartbeat, kept 8 days. Used for sparklines and burn rate.
- `Claude Usage Viewer/Core/FetchScheduler.swift`: polling policy (15 min; 30 min while the feed is live; cooldown; exponential backoff up to 15 min; refresh-on-nudge only when data is over 5 min old).
- `Claude Usage Viewer/Core/Alerts.swift`: decides notifications (pace within the hour, thresholds, limit reached, reset after heavy use), once per window.
- `Claude Usage Viewer/Core/Formatting.swift`: durations ("6d 11h", compact "3h37m") and clock times ("8:28 PM" / "Thu 7:00 AM").
- `Claude Usage Viewer/Core/Credentials.swift`: parses the keychain JSON (redacted description, token fingerprint, plan name), plus CLI version parsing.
- `Claude Usage Viewer/Core/MenuBarPresenter.swift`: what the menu bar shows (most urgent limit, "~33m" / "↻3h37m" caption, tooltip).
- `Claude Usage Viewer/Core/StatusLineInstaller.swift`: installs and uninstalls the status-line feed script. It wraps and restores any existing status line and backs up settings.json.
- `Claude Usage Viewer/Core/HTTPParsing.swift`: ISO dates with microseconds; Retry-After as seconds or an HTTP-date.
- `Claude Usage Viewer/Services/ProcessRunner.swift`: async subprocess runner with a timeout.
- `Claude Usage Viewer/Services/ClaudeCode.swift`: app paths, keychain read via `/usr/bin/security`, installed CLI version lookup for the User-Agent.
- `Claude Usage Viewer/Services/UsageClient.swift`: HTTPS client for the usage endpoint; maps 401/403/429 to errors.
- `Claude Usage Viewer/Services/SystemServices.swift`: wake/lock/network monitor, notifications, launch at login (`SMAppService`).
- `Claude Usage Viewer/Store/UsageStore.swift`: state, both fetch loops, feed polling, history persistence, alerts.
- `Claude Usage Viewer/Store/Preferences.swift`: settings backed by UserDefaults.
- `Claude Usage Viewer/Views/PopoverView.swift`: the popover (plan badge, Live indicator, rows, breakdown, extra usage, footer).
- `Claude Usage Viewer/Views/LimitRowView.swift`: limit row, usage bar with pace tick, sparkline, breakdown bar.
- `Claude Usage Viewer/Views/SettingsView.swift`: Settings window (menu bar mode, launch at login, notifications, live-updates toggle, version).
- `Claude Usage Viewer/App/StatusItemController.swift`: the NSStatusItem (template icon, attributed title, stale dimming, right-click menu, popover).
- `Claude Usage Viewer/App/ClaudeUsageViewerApp.swift`: replaces `Claude_Usage_ViewerApp.swift`. Entry point, AppDelegate, single-instance guard, `--install-statusline-feed` / `--uninstall-statusline-feed` flags.
- `Claude Usage Viewer.xcodeproj/project.pbxproj`: `ENABLE_APP_SANDBOX = NO` and `MARKETING_VERSION = 2.0` (no other changes).
- `Package.swift`: builds `Core/` as the `UsageCore` SwiftPM target so `swift test` works without a test target in the Xcode project.
- `Tests/UsageCoreTests/ParsingTests.swift`, `LogicTests.swift`, `InstallerTests.swift`: 56 tests, including running the generated shell script end to end.
- `Makefile`: `test`, `build`, `install` (tests → Release build stamped with the commit count → replace in /Applications → relaunch), `install-feed`, `uninstall-feed`, `clean`.
- `.gitignore`: ignores `build/`, `.build/`, `.swiftpm/`.
- `README.md`: rewritten for v2.0.

Commit `7d042fe`: test fixture
- `Tests/UsageCoreTests/Fixtures/usage-response.json`: real captured response replaced with made-up values in the same shape.
- `Tests/UsageCoreTests/ParsingTests.swift`: assertions updated to the new values; test renamed to `parsesLimitsListFromFullResponse`.

Outside the repo
- `/Applications/Claude Usage Viewer.app`: replaced the June 1 Debug build with a v2.0 Release build (build 11).
- `~/.claude/settings.json`: added the `statusLine` entry for the live feed. Existing keys are untouched but now sorted. Backup at `~/.claude/settings.json.usage-viewer-backup`.
- `~/Library/Application Support/Claude Usage Viewer/`: new folder holding `statusline-feed.sh`, `statusline-feed.json` (mode 600) and `history.json`.
- Removed the legacy manual "Claude Usage Viewer" Login Item; the app now registers itself via `SMAppService`.
- `~/.claude/CLAUDE.md`: two Decision Log entries (Retry-After scheduling; the v2.0 rebuild).

## Decisions made
- **Retry right after Retry-After expires, with jitter, instead of on a fixed 15-minute tick.** The usage endpoint's limit (~3 calls per 5 min) is shared with every Claude Code session, Claude Desktop and the VS Code meter on the same login. A fixed tick usually landed while another client had drained it.
- **Color by projected time to limit, not raw percentage.** 48% with 4h left is alarming if the window is only 42 minutes old. Severity escalates only when the projected limit is within 40% of the window length, so a weekly projection about 6 days out stays informational instead of turning the menu bar amber.
- **Take live usage from Claude Code's status line.** Claude Code already receives `rate_limits` for free; a status-line script saves it via `plutil` (no jq/python dependency). API polling drops to every 30 min while the feed is live. Any existing status line is wrapped and restored exactly.
- **Drop the sandbox.** Needed to run `/usr/bin/security`: Claude Code creates the keychain item with that tool, so reading it this way never prompts, even after rebuilds. This replaces the 2026-06-01 "cache the token in-process" decision. Also needed to find the CLI version and to read and write the feed.
- **Never refresh the OAuth token ourselves.** Refreshing would rotate it out from under Claude Code (the same failure as the NotebookLM cookie revocations). A 401 blocks that token's fingerprint until Claude Code replaces it.
- **NSStatusItem instead of MenuBarExtra.** MenuBarExtra can't do monospaced digits, a colored caption, stale dimming or a right-click menu.
- **Core logic is Foundation-only and `nonisolated`,** compiled both into the app and as a SwiftPM target from the same folder. That gives tests without editing the pbxproj.
- **`make install` always builds Release** and stamps the commit count as the build number. This guards against a repeat of the stale Debug build.

## Problems encountered
- **The 429 had two causes.** (1) The shared rate limit, confirmed by calling the endpoint directly: 3×200 then 429 with `retry-after: 292`. (2) `/Applications` held a June 1 Debug build that predated the June 21 429-handling commit. `strings` on `Claude Usage Viewer.debug.dylib` showed it still had the generic "API error: HTTP" text.
- **The unified log had no record of the app's network calls,** so diagnosis relied on direct curl probes and the app's saved snapshot timestamp.
- **Swift Testing's `#expect` can't call a mutating method.** Fixed by capturing results first.
- **Two first-run test failures.** A clock-test date was miscalculated (fixed the test). A weekly projection was genuinely past 100% but about 6 days away, which led to the 40%-of-window warning rule.
- **Two Swift 6 concurrency warnings** (weak `self` captured outside a `Task`). Fixed; the build is now warning-free.
- **An `osascript` attempt to click the menu bar item** triggered a macOS "Terminal wants to control this Mac" prompt. The user was asked to deny it; screenshots were taken with `screencapture` instead.
- **`sfltool dumpbtm` hung** (likely needs sudo), so launch at login couldn't be verified from the command line.
- **SourceKit showed many "cannot find type" errors** from checking files on their own. These were false positives; `swift build` and `xcodebuild` were the source of truth.

## Left unfinished
- Launch at login hasn't been verified (Settings toggle and System Settings → Login Items).
- Notifications haven't been seen firing yet; macOS authorization is untested.
- Sparklines haven't been seen; they need a few samples to build up.
- Turning live updates off and back on from Settings hasn't been exercised in the app (the installer tests cover the logic).
- Claude Code now shows an empty status line, because the feed script only passes data along when no previous status line existed.
- The real API values are still in git history (commit `3f85e21`). Leaving them was the recommendation; removing them would need a history rewrite and force-push.
- The User-Agent fallback (`2.1.302`) needs a manual bump only if the installed CLI can't be found.

## Next steps
1. Run through the manual checks: launch at login, a notification firing (pace or threshold), sparklines, the Settings live-updates toggle, and the right-click menu.
2. Decide whether to add a visible Claude Code status line. If so, set it, then turn live updates off and on so the script wraps it.
3. Watch the app over a day or two: the Live indicator should drop about 10 min after Claude Code goes idle, polling should fall back to 15 min, and there should be no persistent 429s.
4. Consider tuning the projection thresholds (40% warning lead, 30-min critical, 90% floor) after real-world use.
5. Optionally: a desktop/Notification Center widget, or a per-model weekly row if Anthropic starts returning scoped limits.
