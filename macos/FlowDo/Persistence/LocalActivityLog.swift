import Foundation

/// Ordered, append-only UTF-8 JSON Lines; all file I/O runs on one utility queue.
/// Merely constructing this object creates no directory or log file.
final class LocalActivityLog: ActivityLogSink {
    let url: URL
    var onError: ((String) -> Void)?
    private let queue = DispatchQueue(label: "com.flowdo.activity-log", qos: .utility)

    init(url: URL) { self.url = url }

    func append(_ event: ActivityLogEvent) {
        queue.async { [self] in
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.sortedKeys]
                var bytes = try encoder.encode(event)
                bytes.append(0x0A)
                let directory = url.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700])
                if !FileManager.default.fileExists(atPath: url.path) {
                    guard FileManager.default.createFile(atPath: url.path, contents: nil,
                                                         attributes: [.posixPermissions: 0o600]) else {
                        throw CocoaError(.fileWriteUnknown)
                    }
                }
                let handle = try FileHandle(forUpdating: url)
                defer { try? handle.close() }
                let end = try handle.seekToEnd()
                if end > 0 {
                    try handle.seek(toOffset: end - 1)
                    let lastByte = try handle.read(upToCount: 1)
                    try handle.seekToEnd()
                    // Keep a crash-truncated record separate from the next valid event.
                    if lastByte != Data([0x0A]) { try handle.write(contentsOf: Data([0x0A])) }
                }
                try handle.write(contentsOf: bytes)
                try handle.synchronize()
            } catch {
                onError?("Activity log could not be written. Check the Logs folder’s permissions and available space.")
            }
        }
    }

    /// Drain queued boundary events before normal quit or after turning logging off.
    func flush() { queue.sync {} }
}
