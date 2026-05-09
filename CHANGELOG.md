# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Constrained the widget percentage readout to preserve side breathing room at `100%`; 2-digit values stay at the original 31pt size, while `100%` scales down slightly instead of touching the ring and widget edge.

## [0.1.0] — 2026-05-09

First 0.1.0 package. Personal Team signed; no notarized binary shipped.
Build and install instructions live in the [README](README.md#install).

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
  plug/unplug), and when the menu opens. Sub-second-fresh "Last sampled"
  copy refreshed on `menuNeedsUpdate`.
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
- **Widget visual.** Formula-based 2x2 quadrant layout modeled on Apple's
  Batteries multi-device widget grid: `gridRingDiameter = side * 11/28`,
  visible ring `side * 5/14`, percentage centered in the right half such that
  the gap between ring-right and text-left equals the gap between text-right
  and widget-right. 24pt `keyboard` SF Symbol, 31pt rounded semibold
  monospaced-digit percentage, 12pt secondary footer. Apple's two-tier color
  rule: green when charging or `>20%`, red `≤20%`, gray for degraded states.
- **Charge-history footer.** `Last charged: N% · <elapsed>` with compact
  English (`just now` / `5 min ago` / `2 hr ago` / `1 day ago`), or
  `Charge to start tracking` until the first `charging* → discharging` event
  is observed.
- **Degraded states.** Failed samples preserve the last battery / device
  fields, update `sampledAt`, set `lastError`, and reload widget timelines.
  The widget renders `Open Bolt Battery to start` (no snapshot),
  `Updated <X> ago` (>30 min stale, ring half-transparent),
  `Receiver disconnected` (IOKit / set-report failures, ring gray),
  `Keyboard offline` (>6 consecutive timeouts, ring gray), or
  `Error: 0xNN` (HID++ 1.0 / 2.0 protocol error, ring gray).
- **Charging indicator (Apple-equivalent).** `BoltShape: Shape` hand-codes
  Apple's `system battery UI.framework` private `custom bolt`
  (`bolt path reference`) path: 12 anchors, 6 bezier segments, PDF Y-up flipped to
  SwiftUI Y-down. Visible bolt is 12×16pt at `offset(y: -radius)` on the
  ring's 12 o'clock; mask uses the same shape filled and stroked
  (`lineWidth: 3` → 1.5pt halo each side) with `.blendMode(.destinationOut)`
  inside a `compositingGroup`, so both track and progress taper along the
  bolt wing edges. Bolt is white below 100% SOC and green at 100%, matching
  the intended behavior. Implementation recipe (`implementation notes` →
  `asset lookup` → `vector extraction`) documented in
  `docs/development-plan.md` Step 9.6.
- **Logi Bolt branding.** App icon and 20pt `MenuBarBolt` template image
  derived from the user-provided `LogiBoltIconResources/`. While charging,
  the menu bar icon composes the logo with an SF Symbol `bolt.fill` corner
  badge plus a 0.75pt destinationOut halo (template-image polarity preserved).
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
- **Documentation.** `docs/architecture.md`, `docs/development-plan.md`,
  `docs/open-decisions.md`, plus a README **Install** section covering the
  Personal Team packaging flow, widget add-to-Notification-Center, login item
  enablement, and log inspection.

### Known limitations

- **Liquid Glass background (Step 7.5, deferred).** macOS Tahoe 26 has a
  beta bug where third-party widgets cannot adopt the system Liquid Glass
  treatment via any public API (`Color.clear`, `.fill.tertiary`,
  `.regularMaterial`, `.glassEffect(.regular)` all render as opaque dark).
  the reference battery widget bypasses via the private `BatteryCenter.framework`.
  This release ships a `Color.black.opacity(0.18)` + gradient fallback. The
  switch to system Liquid Glass is gated on Apple resolving the bug in a
  Tahoe stable release.

[Unreleased]: https://github.com/yuhangrao/Logi-Bolt-Battery/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/yuhangrao/Logi-Bolt-Battery/releases/tag/v0.1.0
