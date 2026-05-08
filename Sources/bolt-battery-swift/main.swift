import BoltHIDPP
import Foundation

do {
    let client = try BoltClient()
    let echo = try await client.ping()
    await client.close()
    print(String(format: "ping=0x%02x", echo))
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
