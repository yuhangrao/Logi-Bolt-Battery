import BoltHIDPP
import Foundation

// MARK: - CLI argument parsing

enum DeviceFilter: String {
    case any
    case keyboard
}

struct CLIOptions {
    var json: Bool = false
    var deviceFilter: DeviceFilter = .any
}

func parseArgs() -> CLIOptions {
    var opts = CLIOptions()
    var i = 1
    let args = CommandLine.arguments
    while i < args.count {
        let a = args[i]
        switch a {
        case "--json":
            opts.json = true
        case "--device-type":
            i += 1
            guard i < args.count, let f = DeviceFilter(rawValue: args[i]) else {
                FileHandle.standardError.write(Data("--device-type expects 'any' or 'keyboard'\n".utf8))
                exit(2)
            }
            opts.deviceFilter = f
        case "-h", "--help":
            print("Usage: bolt-battery-swift [--json] [--device-type any|keyboard]")
            exit(0)
        default:
            FileHandle.standardError.write(Data("unknown argument: \(a)\n".utf8))
            exit(2)
        }
        i += 1
    }
    return opts
}

// MARK: - JSON model (mirrors bolt_battery.py output)

struct DeviceSnapshot: Codable {
    var index: Int
    var `protocol`: String
    var ping: Int
    var deviceType: String?
    var deviceName: String?
    var socPercent: Int?
    var chargingState: String?
    var externalPower: Bool?
    var batteryFeature: String?
    var batteryError: String?
    var firmware: [String]
    var sampledAt: String

    enum CodingKeys: String, CodingKey {
        case index, `protocol`, ping
        case deviceType, deviceName
        case socPercent, chargingState, externalPower
        case batteryFeature, batteryError
        case firmware, sampledAt
    }
}

// MARK: - Per-device sampling

func sampleDevice(client: BoltClient, index: UInt8) async -> DeviceSnapshot? {
    let version: ProtocolVersion
    do {
        version = try await client.getProtocolVersion(deviceIndex: index)
    } catch {
        return nil
    }

    var snap = DeviceSnapshot(
        index: Int(index),
        protocol: "\(version.major).\(version.minor)",
        ping: Int(version.ping),
        deviceType: nil,
        deviceName: nil,
        socPercent: nil,
        chargingState: nil,
        externalPower: nil,
        batteryFeature: nil,
        batteryError: nil,
        firmware: [],
        sampledAt: ""
    )

    snap.deviceType = (try? await client.getDeviceType(deviceIndex: index))
    snap.deviceName = (try? await client.getDeviceName(deviceIndex: index))

    do {
        let battery = try await client.getBattery(deviceIndex: index)
        snap.socPercent = battery.socPercent
        snap.chargingState = battery.chargingState
        snap.externalPower = battery.externalPower
        snap.batteryFeature = battery.feature
    } catch {
        snap.batteryError = String(describing: error)
    }

    if let fw = try? await client.getFirmware(deviceIndex: index) {
        snap.firmware = fw.map { $0.description }
    }

    return snap
}

func currentUTCStamp() -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
    f.timeZone = TimeZone(identifier: "UTC")
    f.locale = Locale(identifier: "en_US_POSIX")
    return f.string(from: Date())
}

// MARK: - Output

func emitJSON(_ devices: [DeviceSnapshot], filter: DeviceFilter) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    do {
        let data: Data
        if filter == .keyboard {
            if let first = devices.first {
                data = try encoder.encode(first)
            } else {
                data = "null".data(using: .utf8)!
            }
        } else {
            struct Wrapper: Codable { let devices: [DeviceSnapshot] }
            data = try encoder.encode(Wrapper(devices: devices))
        }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    } catch {
        FileHandle.standardError.write(Data("json encode failed: \(error)\n".utf8))
        exit(1)
    }
}

func emitHuman(_ devices: [DeviceSnapshot]) {
    for d in devices {
        print("━━━ Device #\(d.index) ━━━")
        print(String(format: "  HID++ protocol: %@ (echo 0x%02x)", d.protocol, d.ping))
        print("  Type:           \(d.deviceType ?? "<unknown>")")
        print("  Name:           \(d.deviceName ?? "<unknown>")")
        if let soc = d.socPercent {
            var extras: [String] = []
            if let cs = d.chargingState { extras.append(cs) }
            if d.externalPower == true { extras.append("plugged in") }
            let tail = extras.isEmpty ? "" : " [\(extras.joined(separator: ", "))]"
            let feat = d.batteryFeature ?? ""
            print("  Battery:        \(soc)%\(tail)  (\(feat))")
        } else {
            print("  Battery:        <\(d.batteryError ?? "n/a")>")
        }
        for line in d.firmware {
            print("  Firmware:       \(line)")
        }
        print()
    }
}

// MARK: - Main

let opts = parseArgs()

let client: BoltClient
do {
    client = try BoltClient()
} catch {
    if opts.json {
        let payload = ["error": String(describing: error)]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    } else {
        FileHandle.standardError.write(Data("FAILED: \(error)\n".utf8))
    }
    exit(1)
}

if !opts.json {
    print("✓ Bolt receiver opened\n")
}

var devices: [DeviceSnapshot] = []
for idx: UInt8 in 1...6 {
    guard var snap = await sampleDevice(client: client, index: idx) else { continue }
    if opts.deviceFilter == .keyboard, snap.deviceType != "Keyboard" { continue }
    snap.sampledAt = currentUTCStamp()
    devices.append(snap)
    if opts.deviceFilter == .keyboard { break }
}

await client.close()

if opts.json {
    emitJSON(devices, filter: opts.deviceFilter)
    exit(devices.isEmpty ? 1 : 0)
}

if devices.isEmpty {
    if opts.deviceFilter == .keyboard {
        print("No keyboard found among paired devices. Wake it (touch a key) and re-run.")
    } else {
        print("No paired devices answered. Wake them (touch a key/move the mouse) and re-run.")
    }
    exit(1)
}

emitHuman(devices)
