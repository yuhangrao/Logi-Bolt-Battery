# Logi-Bolt-Battery

Read battery and device info from a Logitech Bolt receiver and any paired peripheral on macOS, using raw HID++ 2.0 over IOKit. No `Logi Options+`, no Solaar, no third-party libraries.

## Status

`bolt_battery.py` — working CLI probe.

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

Run: `python3 bolt_battery.py` — add `--debug` for raw HID++ frame trace.

## Planned: independent macOS widget

Apple's built-in Batteries widget is fed by the private `com.apple.BatteryCenter` framework, which only sees devices that publish a `BatteryPercent` property in IORegistry. The Bolt receiver presents itself to macOS as a generic USB HID composite device, hiding the real keyboard/mouse battery behind Logitech's HID++ protocol — so it can't be merged into Apple's widget without virtualizing a BLE peripheral (impossible on macOS userspace) or shipping a DriverKit DEXT (entitlement-gated, brittle).

Instead this repo will ship a **standalone Notification Center widget** that pulls its data from our HID++ probe and renders next to Apple's widget with the same visual language.

### Widget spec

- **Form factor:** macOS small widget (single rectangle), visual style matching Apple's built-in Batteries widget — rounded dark background, circular progress ring, device glyph in the center, identical color ramp (green / yellow / red)
- **Primary readout:** current battery percentage + charging state, matching Apple's widget behavior (ring fills clockwise, ring color reflects level, glyph shows charging bolt when applicable)
- **Footer line:** small English text — `Last charged <duration> ago to <percent>%` (e.g. `Last charged 3h ago to 100%`)
- **Refresh cadence:** every ~5 min from a background helper, more aggressive when charging state changes

### Architecture (to be designed)

Tentative:

| Layer | Responsibility |
|---|---|
| Background helper (Swift port of `bolt_battery.py`, or Python launchd job) | Open HID++ vendor interface, poll every N minutes, append samples to local store |
| Local store (App Group container or JSON in `~/Library/Application Support/`) | Latest reading + a rolling window for charge-cycle detection |
| Charge-cycle analyzer | Detect transitions `discharging → charging → discharging` and persist `(end_time, end_soc)` for the footer text |
| WidgetKit extension (SwiftUI) | Read store, render small widget, refresh on `TimelineProvider` schedule |

The polling/charging-cycle logic and the rendering are decoupled so the helper can be swapped (Python ↔ Swift) without touching the UI.

## Requirements

- macOS Apple Silicon (tested on Darwin 25.5)
- Python 3 with stdlib (no pip installs needed for the CLI probe)
- A Logi Bolt receiver (`VID 0x046D`, `PID 0xC548`) plugged in
- For the upcoming widget: Xcode 15+, Apple Developer account for code signing
