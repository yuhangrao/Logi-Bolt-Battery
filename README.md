# Logi-Bolt-Battery

Read battery and device info from a Logitech Bolt receiver and any paired peripheral on macOS, using raw HID++ 2.0 over IOKit. No `Logi Options+`, no Solaar, no third-party libraries.

## Status

`bolt_battery.py` — working Python CLI probe.

- Talks HID++ 2.0 directly to the Bolt receiver's vendor-specific HID interface (PrimaryUsagePage `0xFF00`, 20-byte long reports in/out)
- Uses `ctypes` to bind macOS IOKit's `IOHIDManager` / `IOHIDDevice` / `IOHIDDeviceSetReport` / report callbacks
- No external dependencies (stdlib only), no TCC permission prompt
- Iterates device indices 1–6 and reports each paired device's name, type, battery (UnifiedBattery `0x1004` with fallback to legacy `0x1000`), and firmware versions

Sample output on this machine:

```
━━━ Device #1 ━━━
  HID++ protocol: 4.5 (echo 0xaa)
  Type:           Keyboard
  Name:           MX Keys S
  Battery:        35% [discharging]  (UnifiedBattery (0x1004))
  Firmware:       Bootloader BL1 v88.01.B0015
  Firmware:       MainApp    RBK v81.01.B0015
```

Run: `python3 bolt_battery.py` for human-readable output. Flags:

- `--json` — emit a `{"devices":[...]}` payload with `socPercent` / `chargingState` / `externalPower` / `deviceName` / `deviceType` (matching the future `BatterySnapshot` schema, so the Swift port can diff against this output)
- `--device-type keyboard` — only the first keyboard, and JSON mode unwraps to a single object (e.g. `python3 bolt_battery.py --json --device-type keyboard | jq '.socPercent'`)
- `--debug` — print raw HID++ frames to stderr (safe to combine with `--json`)

`BoltHIDPP` Swift package — full HID++ 2.0 port (Steps 2–3 of the plan).

- `swift build` / `swift test` / `swift run bolt-battery-swift [--json] [--device-type any|keyboard]`
- `public actor BoltClient` exposes `getProtocolVersion` / `getFeatureIndex` / `getDeviceName` / `getDeviceType` / `getBattery` (UnifiedBattery `0x1004` with fallback to legacy `0x1000`) / `getFirmware` / `discoverKeyboard` / `ping`. Errors are typed `BoltError` (IOKit return codes + HID++ 1.0 / 2.0 protocol errors with raw codes).
- `bolt-battery-swift` produces the same human and JSON output as `bolt_battery.py`. Verified byte-identical: `swift run bolt-battery-swift --json | jq -S 'del(.devices[].sampledAt)'` == `python3 bolt_battery.py --json | jq -S 'del(.devices[].sampledAt)'` on the live MX Keys S.

`BoltBattery` menu bar host app — Steps 4–5 plus producer-side Step 8/8.1/9 history, cable-event tracking, degraded-state snapshots, and Step 9.5/9.6 menu bar branding.

- Lives under `app/`. Project is declared in `app/project.yml` (XcodeGen) and signed with the Personal Team locked in `docs/open-decisions.md` D8.
- Build: `brew install xcodegen` once, then `cd app && xcodegen generate && xcodebuild -scheme BoltBattery -configuration Debug build`. Open the resulting `Bolt Battery.app` to see the image-only Logi Bolt icon in the menu bar — the app polls the Bolt receiver every 5 minutes while discharging and every 1 minute while charging / on external power, then updates a small drop-down (`MX Keys S — N% (state)`, `Last sampled X ago`, `Show Logs…`, `Open at Login`, `Quit`). It also wakes from `NSWorkspace.didWakeNotification` for an immediate post-sleep sample and listens for Bolt receiver unsolicited battery reports so charging-cable plug/unplug refreshes the snapshot and widget within seconds. While charging, the menu bar icon composes the Logi Bolt logo with an SF Symbol `bolt.fill` corner badge (8pt, 0.75pt destinationOut halo) so polarity still adapts to the menu bar tint.
- Step 10 wired up the launch agent and the log inspection path: `Open at Login` toggles `SMAppService.mainApp` (jumps to *System Settings → General → Login Items* the first time the user has to approve), and `Show Logs…` spawns `/usr/bin/log show` with a `subsystem == "industries.stark.boltbattery"` predicate, writes 6 hours of output to `/tmp/BoltBattery-<timestamp>.log`, and opens it with the system default handler so the file is non-empty on first click instead of asking the user to fight Console.app's filters. Startup, sample success/failure, charging-cable events, and login-item transitions all flow through `os.Logger`. See the [Install](#install) section for the exact build/copy steps.
- After every successful sample the app writes a `BatterySnapshot` (`app/Shared/BatterySnapshot.swift`) into the App Group `YOUR_TEAM_ID.industries.stark.boltbattery` via `SnapshotStore.shared.write(...)`. It records the last observed `charging* → discharging` transition as `lastChargeEndedAt` / `lastChargeEndedPercent`, without requiring the battery to reach 100%. Failed samples preserve the previous battery/device fields, update `sampledAt`, set `lastError` to a compact status such as `Receiver disconnected`, `Keyboard offline`, or `Error: 0xNN`, and reload widget timelines. Inspect the stored JSON with `/usr/libexec/PlistBuddy -c "Print :snapshot" ~/Library/Group\ Containers/YOUR_TEAM_ID.industries.stark.boltbattery/Library/Preferences/YOUR_TEAM_ID.industries.stark.boltbattery.plist` (a non-entitled `defaults read <group>` will say "Domain does not exist" — that's expected for App Group plists on macOS).

`BoltBatteryWidget` widget extension — Steps 6–9.6 of the plan.

- Embedded inside `Bolt Battery.app/Contents/PlugIns/BoltBatteryWidget.appex` (the widget's own product name has no space — only the host bundle does). Bundle ID `industries.stark.boltbattery.widget`, sandboxed, sharing the same App Group as the host so it can read `BatterySnapshot`.
- `app/BoltBatteryWidget/BoltBatteryWidget.swift` is a `@main` `Widget` exposing one `.systemSmall` configuration. The `TimelineProvider` reads `SnapshotStore.shared.read()` only; the host app calls `WidgetCenter.shared.reloadAllTimelines()` after successful and failed samples so the widget reflects the latest snapshot. If the host app stops running, the provider schedules a future entry at `sampledAt + 30 min` so the widget can degrade to `Updated <X> ago` without doing any HID++ work in the extension.
- Step 7 polished the view as a **2x2 quadrant layout** modeled on the reference battery multi-device widget grid (top-left ring, top-right percentage, bottom merged area for the charge-history footer or degraded-state copy). The sizing is formula-based from Apple's 2×2 ring grid: the grid centerlines use `gridRingDiameter = side * 11 / 28`, while the visible ring diameter is corrected to `side * 5 / 14` for the current macOS widget coordinate space. The `keyboard` SF Symbol is centered (24pt regular), the percentage uses 31pt rounded semibold type with a constrained width budget so `100%` scales down just enough to keep side breathing room, and the bottom row renders either compact charge-history text like `Last charged: 75% · 5 min ago` (fallback: `Charge to start tracking`) or Step 9 degraded copy like `Open Bolt Battery to start`, `Receiver disconnected`, `Keyboard offline`, `Error: 0xNN`, or `Updated 30 min ago`. Layout disables WidgetKit content margins and positions elements with measured `GeometryReader` coordinates; the percentage is centered in the remaining region from ring-right to widget-right, preserving balanced side gaps without assuming text width equals ring diameter. Color rule is Apple's verified two-tier behavior — green when charging or `>20%`, red `≤20%` (Apple uses yellow only for Low Power Mode, which keyboards don't have); degraded error states force the ring gray, while stale snapshots show the old value half-transparent.
- Step 9.6 swaps the placeholder `bolt.fill` badge for an exact match of the reference battery widget charging indicator. The bolt path is hand-drawn as `system battery UI.framework`'s private `custom bolt` asset (`bolt path reference`), encoded as a SwiftUI `BoltShape` (12 anchors, 6 bezier segments, with a Y-flip from PDF Y-up to SwiftUI Y-down). The visible bolt is `BoltShape().fill` in a 12×16pt frame at `offset(y: -radius)`, white below 100% and green at 100%. The ring is carved by a destinationOut mask — same path filled plus a `stroke(lineWidth: 3)` (1.5pt halo on each side, mirroring `bolt-shaped knockout`) wrapped in a `compositingGroup` — so both track and progress taper along the bolt's wing edges and the gap reads as the widget background, not the gray track. See `docs/development-plan.md` Step 9.6 for the implementation recipe (`implementation notes` → `asset lookup` → `vector extraction`).
- **Background — known macOS Tahoe 26 limitation**: third-party widgets in Notification Center cannot currently adopt the system Liquid Glass treatment that Apple's first-party widgets show, regardless of what `containerBackground(for: .widget)` is set to (`Color.clear` / `Color.X.opacity(...)` / `.fill.tertiary` / `.regularMaterial` / `.glassEffect(.regular)` all render as opaque dark). This is documented in [LiquidGlassReference](https://github.com/conorluddy/LiquidGlassReference) as "Status: No complete solution yet." the reference battery widget bypasses this via the private `BatteryCenter.framework`. As a fallback, our widget paints a `Color.black.opacity(0.18)` base plus top/bottom `LinearGradient` decorations to approximate a glossy card, but this is not real Liquid Glass. Step 7.5 in `docs/development-plan.md` will switch to `Color.clear` once Apple resolves the bug in a Tahoe stable release.
- After building, drag *Bolt Battery* from Notification Center → Edit Widgets to add it. The same `cd app && xcodegen generate && xcodebuild ...` command builds both targets in one go.

## Why a separate widget

Apple's built-in Batteries widget is fed by the private `com.apple.BatteryCenter` framework, which only sees devices that publish a `BatteryPercent` property in IORegistry. The Bolt receiver presents itself to macOS as a generic USB HID composite device, hiding the real keyboard/mouse battery behind Logitech's HID++ protocol — so it can't be merged into Apple's widget without virtualizing a BLE peripheral (impossible on macOS userspace) or shipping a DriverKit DEXT (entitlement-gated, brittle).

This repo therefore ships a **standalone Notification Center widget** with its own data path: the menu bar app polls the receiver via `BoltHIDPP`, writes a `BatterySnapshot` into an App Group, and the widget extension renders it.

### Goal visual

- **Form factor:** macOS small widget (single rectangle), visual style matching Apple's built-in Batteries widget — rounded dark background, **2x2 quadrant layout** cleanly multi-device grid (top-left = circular progress ring with device glyph centered; top-right = large percentage; bottom-half = charge-history footer), identical color ramp (Apple's verified two-tier behavior: green when charging or `>20%`, red `≤20%`)
- **Primary readout:** current battery percentage + charging state, matching Apple's widget behavior (ring fills clockwise, ring color reflects level, glyph shows charging bolt when applicable)
- **Footer line:** small English text — `Last charged: <percent>% · <elapsed>` (e.g. `Last charged: 75% · 5 min ago`, or `just now` for the first minute)

### Roadmap

Implementation is broken into 10 main steps with 4 follow-up sub-steps. **Steps 1–10 and Step 4.1 are landed** (Python protocol probe → Swift HID++ port → menu bar host app → App Group snapshot → widget extension scaffold → widget visual polish to a formula-based 2x2 quadrant layout matching the reference battery widget → menu sampled-line refresh on menu open → last charge-end history + footer → immediate charging-cable plug/unplug refresh via Bolt unsolicited HID++ reports → degraded/error states for missing, stale, disconnected, offline, and HID++ error snapshots → Logi Bolt app icon plus image-only menu bar status item → charging indicator hand-drawn as Apple's system battery UI bolt assets, with destinationOut bolt-shaped knockout on the ring and a charging corner badge on the menu bar logo → packaging metadata, `SMAppService.mainApp` "Open at Login" toggle, `os.Logger` instrumentation feeding a "Show Logs…" Console.app deep link, and an Install section in this README). Remaining: Step 7.5 retry system Liquid Glass background once the macOS Tahoe beta bug is fixed. Detail in:

- [`docs/architecture.md`](docs/architecture.md) — three-tier architecture (HID++ producer → App Group snapshot → widget extension), refresh strategy, macOS-specific App Group quirks
- [`docs/development-plan.md`](docs/development-plan.md) — Step 0–10 with scope, acceptance criteria, and explicit non-goals per step
- [`docs/open-decisions.md`](docs/open-decisions.md) — locked design decisions
- [`CHANGELOG.md`](CHANGELOG.md) — Keep a Changelog v0.1.0 release notes

## Requirements

- macOS Apple Silicon (tested on Darwin 25.5)
- A Logi Bolt receiver (`VID 0x046D`, `PID 0xC548`) plugged in
- Python 3 with stdlib (no pip installs needed for `bolt_battery.py`)
- For the Swift package (Step 2+): Xcode Command Line Tools (`xcode-select --install`); Swift 5.9+ toolchain. Tested on Swift 6.3.1 / Xcode 26
- For the menu bar app and widget extension (Steps 4+): full Xcode 14+ install, plus an Apple ID added to Xcode → Settings → Accounts (Personal Team is sufficient — see `docs/open-decisions.md` D8). Also `brew install xcodegen` for regenerating `app/BoltBattery.xcodeproj` from `app/project.yml`.

## Install

Personal Team self-build, self-use. The repo does not ship a binary — the Logi Bolt receiver pairing is per-machine and Personal Team signing means a binary built on one Mac would still need to be re-signed for another, so it is simpler to build from source on the machine you want to run it on.

### One-time setup

1. Install full Xcode 14+ from the App Store, open it once, accept the license, and add your Apple ID under **Settings → Accounts** so a Personal Team is provisioned (see [`docs/open-decisions.md`](docs/open-decisions.md) D8).
2. `brew install xcodegen`.
3. If you fork into your own Apple ID: change `DEVELOPMENT_TEAM` in `app/project.yml` to your 10-character team ID, replace every occurrence of the App Group `YOUR_TEAM_ID.industries.stark.boltbattery` (project YAML, entitlements, the constants in `app/Shared/BatterySnapshot.swift`) with `<YOUR_TEAMID>.industries.stark.boltbattery` (or any reverse-DNS you prefer prefixed with your team ID — macOS App Groups must start with the team ID), then re-run `xcodegen generate`.

### Build and copy the .app

```bash
cd app
xcodegen generate
xcodebuild -scheme BoltBattery -configuration Release \
  -derivedDataPath /tmp/boltbat-build build
cp -R "/tmp/boltbat-build/Build/Products/Release/Bolt Battery.app" /Applications/
open "/Applications/Bolt Battery.app"
```

The build emits a `Bolt Battery.app` (with a literal space — the `PRODUCT_NAME` is set that way in `app/project.yml` so Finder, Spotlight, Login Items, and the application menu all show "Bolt Battery") signed with the Personal Team's Apple Development certificate. Copying it from a local build path to `/Applications` avoids Gatekeeper's quarantine flag (which only attaches to downloaded files), so first launch is silent. After `open` you should see the Logi Bolt logo in the menu bar within a couple of seconds — the app samples the receiver immediately on launch.

### Add the widget

Notification Center (swipe right from the right edge of the menu bar, or click the date/time) → scroll to the bottom → **Edit Widgets** → search "Bolt Battery" → drag the small variant into Notification Center.

### Enable launch at login

Click the menu bar logo → **Open at Login**. The first time you toggle it on, macOS may show "Approve in Settings…" alongside the menu item; clicking it again opens *System Settings → General → Login Items* where you can flip the toggle on. Subsequent toggles register/unregister the launch agent silently via `SMAppService.mainApp`.

### Inspect logs

Click the menu bar logo → **Show Logs…**. The host app spawns `/usr/bin/log show --predicate 'subsystem == "industries.stark.boltbattery"' --last 6h --info --debug --style compact`, writes the output to `/tmp/BoltBattery-<timestamp>.log`, and opens that file with the system default `.log` handler (Console.app or your editor of choice). Re-run the menu item any time you want a fresh window. The Python CLI (`python3 bolt_battery.py --debug`) is still the lower-level diff tool when you need raw HID++ frames.

### Uninstall

Quit from the menu bar logo → drag `/Applications/Bolt Battery.app` to the trash → optionally `defaults delete YOUR_TEAM_ID.industries.stark.boltbattery` to drop the App Group snapshot. The widget will fall back to "Open Bolt Battery to start" until the app is reinstalled.
