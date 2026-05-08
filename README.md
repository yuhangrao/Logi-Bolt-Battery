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

`BoltHIDPP` Swift package — IOKit binding scaffold (Step 2 of the plan).

- `swift build` / `swift test` / `swift run bolt-battery-swift`
- Library target `BoltHIDPP` exposes `public actor BoltClient` with `init() throws` / `ping() async throws -> UInt8` / `close()`. `ping()` issues HID++ 2.0 `root.GetProtocolVersion(devIdx=1, pingdata=0xAA)` and returns the echoed byte (`0xAA`) — same value `bolt_battery.py --debug` shows in the first response frame
- Business protocol layer (battery / name / firmware / device discovery) is deferred to Step 3

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
- For the upcoming widget (Step 4+): full Xcode 14+ install, plus an Apple ID added to Xcode → Settings → Accounts (Personal Team is sufficient — see `docs/open-decisions.md` D8)
