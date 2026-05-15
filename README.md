# Claude Code Usage Widget

A macOS menu bar app that shows your Claude Code subscription usage in real time.

- **5-hour** and **7-day** utilization percentages
- Color-coded indicator: 🟢 under 50% / 🟡 50–79% / 🔴 80%+
- Countdown to next reset
- Reads your existing Claude Code credentials — no extra login required
- Auto-refreshes every 5 minutes

---

## Requirements

- macOS 13 (Ventura) or later
- [Claude Code](https://claude.ai/code) installed and logged in
- Xcode (free from the Mac App Store)
- A Claude Pro, Max, Team, or Enterprise subscription

---

## Setup

### Step 1 — Clone the repo

```bash
git clone https://github.com/bjblakerpy/claude-code-usage-widget-macos.git
cd claude-code-usage-widget-macos
```

### Step 2 — Open in Xcode

```bash
open "Claude Usage Viewer/Claude Usage Viewer.xcodeproj"
```

Or double-click `Claude Usage Viewer.xcodeproj` in Finder.

### Step 3 — Set your signing team

1. Click the **Claude Usage Viewer** project in the left sidebar (blue icon at the top)
2. Under **TARGETS**, select **Claude Usage Viewer**
3. Click the **Signing & Capabilities** tab
4. Set **Team** to your Apple ID

> A free Apple ID works fine. You don't need a paid developer account.

### Step 4 — Build the app

Press **Cmd+B**. Wait for "Build Succeeded" in the top bar.

### Step 5 — Copy the app to Applications

1. Go to **Product → Show Build Folder in Finder**
2. Open the **Products → Applications** folder
3. Drag **Claude Usage Viewer.app** to your **/Applications** folder

### Step 6 — Launch it

Open **/Applications/Claude Usage Viewer**. The usage indicator will appear in your menu bar at the top right of your screen.

> If macOS says the app can't be opened because it's from an unidentified developer:
> Go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway**.

### Step 7 — Set it to launch at login (optional)

1. Go to **System Settings → General → Login Items & Extensions**
2. Under **Open at Login**, click **+**
3. Select **Claude Usage Viewer.app** from your Applications folder

It will now start automatically every time you log in.

---

## How it works

Claude Code stores your OAuth credentials in the macOS Keychain under `Claude Code-credentials`. This app reads that token — the same one Claude Code already uses — and calls Anthropic's usage endpoint to get your current utilization. Nothing is stored or sent anywhere other than Anthropic's own API.

---

## Troubleshooting

**"No Claude Code credentials found"**

Claude Code isn't installed or you haven't logged in yet. Run:
```bash
claude login
```
Then click the menu bar icon and hit **Refresh**.

**"Network error: hostname could not be found"**

The app needs permission to make outbound network calls. In Xcode:
1. Click the project in the sidebar
2. Select the **Claude Usage Viewer** target
3. Go to **Signing & Capabilities**
4. Find **App Sandbox** and check **Outgoing Connections (Client)**

Rebuild (Cmd+B), copy the new app to Applications, and relaunch.

**"API error: HTTP 401"**

Your token has expired. Run `claude login` in Terminal to refresh it, then click **Refresh** in the menu.

**Menu bar shows "⚡ Claude" with no percentages**

The first fetch may have failed. Click the icon and check for an error message. Hit **Refresh** to try again.

**macOS blocks the app on first launch**

Right-click the app → **Open** → **Open Anyway**. This only happens once.

---

## A note on terms of service

This app reads your own Claude Code credentials to show your own usage data back to you — the same numbers visible on claude.ai. It does not use your token to access Claude for any other purpose. That said, Anthropic's terms restrict OAuth token use to Claude Code and claude.ai. Use this for personal monitoring at your own discretion.

---

## License

MIT. See [LICENSE](LICENSE).
