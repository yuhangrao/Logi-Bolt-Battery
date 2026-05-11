# Bolt Battery

An Apple-like macOS battery widget for keyboards paired with a Logitech Bolt receiver.

Apple's built-in Batteries widget can't see Bolt-paired devices — the receiver
presents itself to macOS as a generic USB HID composite device, hiding the
real keyboard battery behind Logitech's proprietary HID++ protocol. Bolt
Battery talks HID++ 2.0 directly to the receiver and renders the result as a
compact widget, with no Logi Options+, no Solaar, and no third-party runtime
dependencies.

```
━━━ MX Keys S ━━━
  Battery:   35% [discharging]   (UnifiedBattery 0x1004)
  Firmware:  RBK v81.01.B0015
```

## Features

- **Apple-like macOS widget** — small `.systemSmall` card with a circular
  progress ring, large percentage readout, and a charge-history footer
  (`Last charged: N% · 5 min ago`). Two-tier color rule: green when charging
  or above 20%, red at or below 20%.
- **Menu bar status item** — image-only logo, drop-down with the most recent
  reading, connection status, "Last sampled" timestamp, *Show Logs…*,
  *Open at Login*, and *Quit*.
- **Adaptive sampling** — every 5 minutes while discharging, every 1 minute
  while charging or on external power. Immediate refresh on launch, wake-from-
  sleep, charging-cable plug/unplug, keyboard wake/reconnect/disconnect, and
  receiver USB-C unplug/replug — all driven by unsolicited HID++ reports and
  IOKit events rather than blind high-frequency polling.
- **Graceful degradation** — receiver-disconnected, keyboard-offline, stale
  (>30 min), and HID++ error states each have distinct, structured snapshots
  so the widget never shows a stale percentage as if it were fresh.
- **Login item** — one-toggle launch-at-login via `SMAppService.mainApp`,
  jumping to *System Settings → Login Items* the first time approval is
  required.
- **Structured logging** — every sample, charging event, and login-item
  transition flows through `os.Logger`. *Show Logs…* dumps the last 6 hours
  to a `/tmp/BoltBattery-<timestamp>.log` and opens it in your default log
  viewer.
- **Standalone Python CLI** — `bolt_battery.py` is a stdlib-only HID++ probe
  that ships alongside the app for ad-hoc inspection and protocol debugging.

## Requirements

- macOS 13 (Ventura) or later, Apple Silicon
- A Logitech Bolt receiver (`VID 0x046D`, `PID 0xC548`) plugged in, with a
  keyboard already paired (use Logi Options+ once to pair, or any Bolt-aware
  pairing tool — Bolt Battery is read-only)
- Xcode 14+ (for the menu bar app and widget extension)
- An Apple ID added to Xcode → Settings → Accounts (a free Personal Team is
  enough for personal use; the app is signed with an Apple Development
  certificate, not notarized)
- [`xcodegen`](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

For the Python CLI alone, only Python 3 with stdlib is required — no Xcode,
no pip installs, no entitlements.

## Quick start (Python CLI)

```bash
python3 bolt_battery.py            # human-readable output
python3 bolt_battery.py --json     # JSON payload
python3 bolt_battery.py --json --device-type keyboard | jq '.socPercent'
python3 bolt_battery.py --debug    # raw HID++ frames to stderr
```

Sample output:

```
━━━ Device #1 ━━━
  HID++ protocol: 4.5 (echo 0xaa)
  Type:           Keyboard
  Name:           MX Keys S
  Battery:        35% [discharging]  (UnifiedBattery (0x1004))
  Firmware:       Bootloader BL1 v88.01.B0015
  Firmware:       MainApp    RBK v81.01.B0015
```

## Build (menu bar app + widget)

### 1. Configure your Team ID

The app uses an [App Group](https://developer.apple.com/documentation/xcode/configuring-app-groups)
to share a battery snapshot between the menu bar host and the widget
extension. On macOS, App Group identifiers **must** start with your 10-
character Apple Developer Team ID — there is no way to omit it.

Replace every `YOUR_TEAM_ID` placeholder with your own team ID. You can find
your team ID in [Apple Developer → Membership](https://developer.apple.com/account/#MembershipDetailsCard),
or via `security find-identity -p codesigning -v` (look at the parentheses
after `Apple Development:` entries).

Files to edit:

- `app/project.yml` — `DEVELOPMENT_TEAM` setting + both
  `application-groups` entries
- `app/BoltBattery/BoltBattery.entitlements` — the `application-groups` array
- `app/BoltBatteryWidget/BoltBatteryWidget.entitlements` — the
  `application-groups` array
- `app/Shared/BatterySnapshot.swift` — the `AppGroup.id` constant

```bash
# Quick one-liner (BSD sed on macOS):
git grep -l YOUR_TEAM_ID | xargs sed -i '' 's/YOUR_TEAM_ID/ABCDEF1234/g'
```

### 2. Provide menu bar / app icons

This repository ships **empty imagesets** for the menu bar logo and the app
icon. To avoid redistributing third-party brand assets, no PNGs are included.

Drop your own art into:

- `app/BoltBattery/Assets.xcassets/AppIcon.appiconset/` — supply
  `icon_16x16.png` through `icon_512x512@2x.png` (10 PNGs total, names listed
  in the imageset's `Contents.json`)
- `app/BoltBattery/Assets.xcassets/MenuBarBolt.imageset/` — supply three
  `menu_bar_bolt_template{,@2x,@3x}.png` template PNGs (20pt design size, pure
  black on transparent — they're rendered as template images so the menu bar
  inverts polarity for you)

Provide at least placeholder PNGs before building; Xcode's asset compiler
expects the filenames listed in each imageset's `Contents.json` to exist.

### 3. Build

```bash
cd app
xcodegen generate
xcodebuild -scheme BoltBattery -configuration Release \
  -derivedDataPath /tmp/boltbat-build build
```

The product is `Bolt Battery.app` (with a literal space — the `PRODUCT_NAME`
is set that way so Finder, Spotlight, Login Items, and the application menu
all read "Bolt Battery"). The widget extension is embedded at
`Bolt Battery.app/Contents/PlugIns/BoltBatteryWidget.appex`.

### 4. Install

```bash
mkdir -p dist
cp -R "/tmp/boltbat-build/Build/Products/Release/Bolt Battery.app" "dist/Bolt Battery.app"
cp -R "dist/Bolt Battery.app" /Applications/
open "/Applications/Bolt Battery.app"
```

Optional DMG:

```bash
rm -rf /tmp/boltbat-dmg
mkdir -p "/tmp/boltbat-dmg/Bolt Battery"
cp -R "dist/Bolt Battery.app" "/tmp/boltbat-dmg/Bolt Battery/Bolt Battery.app"
ln -s /Applications "/tmp/boltbat-dmg/Bolt Battery/Applications"
hdiutil create -volname "Bolt Battery" \
  -srcfolder "/tmp/boltbat-dmg/Bolt Battery" \
  -ov -format UDZO "dist/Bolt-Battery-0.1.0.dmg"
```

## Usage

### Menu bar

Click the menu bar logo:

- First row: most recent successful reading, e.g. `MX Keys S — 64% (discharging)`
- `Status:` — current connection state (`Connected`, `Reconnecting…`,
  `Receiver disconnected`, `Keyboard offline`, or `Error: 0xNN`)
- `Last sampled` — relative time since the last successful read
- *Show Logs…* — dump the last 6 hours of `os.Logger` output and open it
- *Open at Login* — toggle launch-at-login via `SMAppService.mainApp`
- *Quit*

### Widget

Add **Bolt Battery** from macOS **Edit Widgets**.

The widget reads its data from the App Group snapshot; it does no HID++ work
of its own and won't drain battery life on the keyboard side.

### Inspecting the App Group snapshot

```bash
/usr/libexec/PlistBuddy -c "Print :snapshot" \
  ~/Library/Group\ Containers/YOUR_TEAM_ID.industries.stark.boltbattery/Library/Preferences/YOUR_TEAM_ID.industries.stark.boltbattery.plist
```

A non-entitled `defaults read <group>` reports "Domain does not exist" — that's
expected for App Group plists on macOS.

### Uninstall

Quit from the menu bar logo, drag `/Applications/Bolt Battery.app` to the
trash, then optionally clear the App Group snapshot:

```bash
defaults delete YOUR_TEAM_ID.industries.stark.boltbattery
```

## Architecture

Three-tier producer / store / consumer:

```
┌─────────────────────┐    ┌─────────────────────┐    ┌─────────────────────┐
│  Menu bar host app  │──▶│   App Group plist   │──▶│  Widget extension   │
│  (HID++ producer)   │    │  (BatterySnapshot)  │    │  (read-only render) │
└─────────────────────┘    └─────────────────────┘    └─────────────────────┘
```

- The **host app** owns the long-lived `BoltClient` and is the only process
  doing HID++ I/O. It samples on a schedule plus on a small set of OS / HID
  events (wake from sleep, charging-cable plug/unplug, wireless-status report,
  receiver USB-C presence change).
- Each successful sample is written as a `BatterySnapshot`
  (`app/Shared/BatterySnapshot.swift`) into a UserDefaults suite keyed by the
  App Group ID. Failed samples preserve the previous battery/device fields
  and set a structured `status` / `statusCode` instead of fabricating a
  reading.
- The **widget extension** has its own short-lived sandbox and only reads
  from the App Group. The host calls `WidgetCenter.shared.reloadAllTimelines()`
  after every sample so the widget reflects the latest data within a frame
  or two. The provider also schedules a `sampledAt + 30 min` entry so the
  widget can degrade to `Updated <X> ago` even if the host app stops running.

## Repository layout

```
.
├── bolt_battery.py            # Python HID++ probe / protocol reference
├── Package.swift              # Swift Package manifest (BoltHIDPP library)
├── Sources/
│   ├── BoltHIDPP/             # HID++ 2.0 actor-based client
│   └── bolt-battery-swift/    # Swift CLI executable
├── Tests/
│   └── BoltHIDPPTests/        # Protocol + ping unit tests
├── app/
│   ├── project.yml            # XcodeGen project (source of truth)
│   ├── BoltBattery/           # Menu bar host app
│   ├── BoltBatteryWidget/     # WidgetKit extension
│   └── Shared/                # BatterySnapshot + SnapshotStore
├── CHANGELOG.md
├── LICENSE
└── README.md
```

The `BoltHIDPP` Swift package is independently usable: `swift build`,
`swift test`, and `swift run bolt-battery-swift [--json] [--device-type any|keyboard]`
all work from a checkout with only Xcode Command Line Tools installed.

## Troubleshooting

- **Menu bar icon never appears.** The app is `LSUIElement` (no Dock icon).
  Check `~/Library/Logs/` and try *Show Logs…* from a second build, or run
  the binary directly from Terminal to surface `stderr`.
- **Widget shows "Open Bolt Battery to start".** No snapshot has been
  written yet — either the host app hasn't launched, or the App Group ID in
  the widget entitlements doesn't match the host. Re-run `xcodegen generate`
  after editing entitlements and rebuild both targets.
- **Widget shows "Receiver disconnected" or "Keyboard offline".** Run
  `python3 bolt_battery.py --debug` to confirm the receiver is enumerated
  and the keyboard responds. The Python CLI is the canonical protocol probe.
- **Login item: "Approve in Settings…"** macOS requires explicit approval on
  first registration. Clicking the menu item again opens *System Settings →
  General → Login Items*; flip the toggle on once and subsequent registrations
  are silent.
- **Liquid Glass background looks flat.** macOS Tahoe 26 currently has a beta
  bug where third-party widgets cannot adopt the system Liquid Glass
  treatment; the app ships a gradient fallback until the bug is fixed.

## License

Bolt Battery is released under the GNU General Public License v3.0. See
[LICENSE](LICENSE) for the full text.

This project is not affiliated with, endorsed by, or sponsored by Logitech.
"Logitech" and "Logi Bolt" are trademarks of their respective owners.
