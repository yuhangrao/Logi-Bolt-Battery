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

`BoltBattery` menu bar host app — Steps 4–5 of the plan.

- Lives under `app/`. Project is declared in `app/project.yml` (XcodeGen) and signed with the Personal Team locked in `docs/open-decisions.md` D8.
- Build: `brew install xcodegen` once, then `cd app && xcodegen generate && xcodebuild -scheme BoltBattery -configuration Debug build`. Open the resulting `BoltBattery.app` to see `⌨ N%` in the menu bar — the app polls the Bolt receiver every 5 minutes via `BoltHIDPP` and updates the title plus a small drop-down (`MX Keys S — N% (state)`, `Last sampled X ago`, `Quit`). It also wakes from `NSWorkspace.didWakeNotification` for an immediate post-sleep sample.
- After every successful sample the app writes a `BatterySnapshot` (`app/Shared/BatterySnapshot.swift`) into the App Group `YOUR_TEAM_ID.industries.stark.boltbattery` via `SnapshotStore.shared.write(...)`. Inspect with `/usr/libexec/PlistBuddy -c "Print :snapshot" ~/Library/Group\ Containers/YOUR_TEAM_ID.industries.stark.boltbattery/Library/Preferences/YOUR_TEAM_ID.industries.stark.boltbattery.plist` (a non-entitled `defaults read <group>` will say "Domain does not exist" — that's expected for App Group plists on macOS).

`BoltBatteryWidget` widget extension — Step 6 of the plan.

- Embedded inside `BoltBattery.app/Contents/PlugIns/BoltBatteryWidget.appex`. Bundle ID `industries.stark.boltbattery.widget`, sandboxed, sharing the same App Group as the host so it can read `BatterySnapshot`.
- `app/BoltBatteryWidget/BoltBatteryWidget.swift` is a `@main` `Widget` exposing one `.systemSmall` configuration. The `TimelineProvider` reads `SnapshotStore.shared.read()` and emits a single entry with `policy: .never`; the host app calls `WidgetCenter.shared.reloadAllTimelines()` after each successful sample so the widget always reflects the latest snapshot. Visual is a placeholder (ring + percent + device name) — Step 7 will polish it to match the reference battery widget.
- After building, drag *Bolt Battery* from Notification Center → Edit Widgets to add it. The same `cd app && xcodegen generate && xcodebuild ...` command builds both targets in one go.

## Planned: independent macOS widget

Apple's built-in Batteries widget is fed by the private `com.apple.BatteryCenter` framework, which only sees devices that publish a `BatteryPercent` property in IORegistry. The Bolt receiver presents itself to macOS as a generic USB HID composite device, hiding the real keyboard/mouse battery behind Logitech's HID++ protocol — so it can't be merged into Apple's widget without virtualizing a BLE peripheral (impossible on macOS userspace) or shipping a DriverKit DEXT (entitlement-gated, brittle).

Instead this repo will ship a **standalone Notification Center widget** that pulls its data from our HID++ probe and renders next to Apple's widget with the same visual language.

### Widget spec

- **Form factor:** macOS small widget (single rectangle), visual style matching Apple's built-in Batteries widget — rounded dark background, circular progress ring, device glyph in the center, identical color ramp (green / yellow / red)
- **Primary readout:** current battery percentage + charging state, matching Apple's widget behavior (ring fills clockwise, ring color reflects level, glyph shows charging bolt when applicable)
- **Footer line:** small English text — `Last charged <duration> ago to <percent>%` (e.g. `Last charged 3h ago to 100%`)

### Implementation

Designed, not coded yet. The widget and its menu-bar host app will live in this repo (single-repo layout, see `docs/open-decisions.md` D9). Implementation is broken into 10 independent steps — see:

- [`docs/architecture.md`](docs/architecture.md) — three-tier architecture (HID++ producer → App Group snapshot → widget extension), refresh strategy, macOS-specific App Group quirks
- [`docs/development-plan.md`](docs/development-plan.md) — Step 0–10 with scope, acceptance criteria, and explicit non-goals per step
- [`docs/open-decisions.md`](docs/open-decisions.md) — pending decisions (data pathway, language, sampling frequency, bundle ID, etc.)

## Requirements

- macOS Apple Silicon (tested on Darwin 25.5)
- A Logi Bolt receiver (`VID 0x046D`, `PID 0xC548`) plugged in
- Python 3 with stdlib (no pip installs needed for `bolt_battery.py`)
- For the Swift package (Step 2+): Xcode Command Line Tools (`xcode-select --install`); Swift 5.9+ toolchain. Tested on Swift 6.3.1 / Xcode 26
- For the menu bar app and the upcoming widget (Step 4+): full Xcode 14+ install, plus an Apple ID added to Xcode → Settings → Accounts (Personal Team is sufficient — see `docs/open-decisions.md` D8). Also `brew install xcodegen` for regenerating `app/BoltBattery.xcodeproj` from `app/project.yml`.
