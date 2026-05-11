# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] — 2026-05-11

Initial public release. Personal Team signed; no notarized binary shipped.
Build and install instructions live in the [README](README.md#build-menu-bar-app--widget).

### Added

- **HID++ 2.0 client (Python).** `bolt_battery.py` — stdlib-only macOS CLI
  that talks raw HID++ over IOKit to a Logi Bolt receiver, decoding device
  name, type, firmware versions, and battery state via UnifiedBattery `0x1004`
  (with legacy `0x1000` fallback). `--json` and `--device-type keyboard` flags
  emit a payload aligned with the Swift `BatterySnapshot` schema; `--debug`
  prints raw frames to stderr.
- **HID++ 2.0 client (Swift).** `BoltHIDPP` Swift Package
  (`Sources/BoltHIDPP/`) re-implements the protocol layer as a `public actor
  BoltClient` with typed `BoltError` cases for HID++ 1.0 and 2.0 errors.
  `bolt-battery-swift` CLI (`Sources/bolt-battery-swift/`) produces output
  byte-identical to `bolt_battery.py --json` modulo timestamps. Verified
  against MX Keys S.
- **Menu bar host app.** `Bolt Battery.app` (`app/BoltBattery/`) — `LSUIElement`
  background app with an image-only Logi Bolt status item. Polls the receiver
  every 5 minutes while discharging and every 1 minute while charging or on
  external power; samples immediately on launch, on `NSWorkspace.didWakeNotification`,
  on Bolt receiver unsolicited HID++ battery reports (charging-cable
  plug/unplug), and when the menu opens. The menu includes a `Status:` row for
  current connected/reconnecting/offline/receiver/error state while keeping
  the first row pinned to the last successful battery reading; `Last sampled`
  advances only after a successful battery read.
- **App Group snapshot.** Each successful sample writes a `BatterySnapshot`
  (`app/Shared/BatterySnapshot.swift`) to UserDefaults suite
  `YOUR_TEAM_ID.industries.stark.boltbattery`. Tracks the last
  `charging* → discharging` transition into `lastChargeEndedAt` /
  `lastChargeEndedPercent` without a percent threshold, so wall-clock display
  is "last time the user pulled the cable", not "last full charge".
- **Widget extension.** `BoltBatteryWidget.appex` embedded in the host app
  bundle, sandboxed, sharing the same App Group. `.systemSmall` only.
  `TimelineProvider` reads the snapshot and never does HID++ work itself; the
  host calls `WidgetCenter.shared.reloadAllTimelines()` after every sample.
  Provider also schedules a `sampledAt + 30 min + 1s` entry so the widget can
  auto-degrade to `Updated <X> ago` even if the host app stops running.
- **Widget visual.** Formula-based 2×2 quadrant layout (top-left ring with
  device glyph, top-right percentage, bottom merged footer area):
  `gridRingDiameter = side * 11/28`, visible ring `side * 5/14`, percentage
  centered in the right half such that the gap between ring-right and
  text-left equals the gap between text-right and widget-right. 24pt
  `keyboard` SF Symbol, 31pt rounded semibold monospaced-digit percentage,
  12pt secondary footer. `100%` scales down slightly to preserve side
  breathing room. Two-tier color rule: green when charging or `>20%`, red
  `≤20%`, gray for degraded states.
- **Charge-history footer.** `Last charged: N% · <elapsed>` with compact
  English (`just now` / `5 min ago` / `2 hr ago` / `1 day ago`), or
  `Charge to start tracking` until the first `charging* → discharging` event
  is observed.
- **Degraded states.** Failed samples preserve the last battery / device
  fields, update `sampledAt`, set structured `status` / `statusCode`, and reload widget timelines.
  The widget renders `Open Bolt Battery to start` (no snapshot),
  `Updated <X> ago` (>30 min stale, ring half-transparent),
  `Receiver disconnected` (IOKit / set-report failures, ring gray),
  `Keyboard offline` (>6 consecutive timeouts, ring gray), or
  `Error: 0xNN` (HID++ 1.0 / 2.0 protocol error, ring gray).
- **Connection-event refresh.** HID++ wireless-status / receiver connection
  reports and Bolt receiver USB-C presence changes can refresh the widget
  without waiting for the polling interval. Receiver replug uses a short
  `Reconnecting…` grace window plus background retry before settling on
  keyboard offline.
- **Charging indicator.** `BoltShape: Shape` encodes a custom 12-anchor,
  6-segment bezier bolt path (PDF-style Y-up coordinates flipped to SwiftUI
  Y-down). Visible bolt is 12×16pt at `offset(y: -radius)` on the ring's 12
  o'clock; the mask uses the same shape filled and stroked
  (`lineWidth: 3` → 1.5pt halo each side) with `.blendMode(.destinationOut)`
  inside a `compositingGroup`, so both track and progress taper along the
  bolt wing edges. The bolt is white below 100% SOC and green at 100%.
- **Logi Bolt branding.** App icon and 20pt `MenuBarBolt` template image
  drive the menu bar status item. While charging, the menu bar icon composes
  the logo with an SF Symbol `bolt.fill` corner badge plus a 0.75pt
  destinationOut halo (template-image polarity preserved). Image assets are
  user-supplied; the repository ships empty imagesets — see [README](README.md)
  for setup details.
- **Login item.** Menu bar **Open at Login** toggle backed by
  `SMAppService.mainApp.register()` / `unregister()`. When macOS reports
  `requiresApproval`, the menu jumps to *System Settings → General →
  Login Items* on the next click instead of erroring.
- **Logging.** `os.Logger` subsystem `industries.stark.boltbattery` records
  startup, sample success, sample failure, charging-cable HID++ events, and
  login-item state transitions. **Show Logs…** menu item spawns
  `/usr/bin/log show --predicate 'subsystem == "industries.stark.boltbattery"'
  --last 6h --info --debug --style compact`, dumps the output to
  `/tmp/BoltBattery-<timestamp>.log`, and opens that file with the system
  default `.log` handler — so the user lands on actual content instead of an
  empty Console.app stream that requires manual filter setup.
- **Packaging metadata.** `CFBundleName = "Bolt Battery"` and `PRODUCT_NAME =
  "Bolt Battery"` (both with a literal space), so Finder, Spotlight,
  `/Applications/Bolt Battery.app`, the application menu, Login Items, and
  Activity Monitor all show "Bolt Battery". `LSApplicationCategoryType =
  public.app-category.utilities`, `LSMinimumSystemVersion = 13.0`, and a
  copyright string in `Info.plist` for cleaner Finder / Spotlight presentation.
  Widget extension keeps `PRODUCT_NAME = BoltBatteryWidget` since the appex
  file name is internal; only its `CFBundleDisplayName` is "Bolt Battery
  Widget". The XcodeGen project, `.xcodeproj` file, and Xcode target are still
  named `BoltBattery` so existing pbxproj references stay stable.
- **Documentation.** README with quickstart, build instructions, and
  configuration notes covering the Personal Team packaging flow, widget setup,
  login item enablement, and log inspection.

### Known limitations

- **Liquid Glass background (deferred).** macOS Tahoe 26 currently has a beta
  bug where third-party widgets cannot adopt the system Liquid Glass treatment
  via any public API (`Color.clear`, `.fill.tertiary`, `.regularMaterial`,
  `.glassEffect(.regular)` all render as opaque dark). First-party widgets
  bypass this via private frameworks. This release ships a
  `Color.black.opacity(0.18)` + gradient fallback. The switch to system Liquid
  Glass is gated on the bug being resolved in a Tahoe stable release.

[Unreleased]: https://github.com/yuhangrao/Logi-Bolt-Battery/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/yuhangrao/Logi-Bolt-Battery/releases/tag/v0.1.0
