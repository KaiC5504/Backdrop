import Foundation

/// Append-only, flushed per line. The case worth capturing is the process being
/// suspended without warning, and a buffered line is a lost line.
public final class DiagnosticsLog: @unchecked Sendable {
    public let fileURL: URL
    private let maxBytes: Int
    private let clock: @Sendable () -> Date
    private let timeFormatter: DateFormatter
    private let lock = NSLock()
    private var approximateSize: Int

    public init(
        fileURL: URL,
        maxBytes: Int = 1_000_000,
        clock: @escaping @Sendable () -> Date = { Date() },
        timeZone: TimeZone = .current
    ) {
        self.fileURL = fileURL
        self.maxBytes = maxBytes
        self.clock = clock
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm:ss.SSS"
        timeFormatter = formatter
        approximateSize = (try? Data(contentsOf: fileURL))?.count ?? 0
    }

    public static func defaultURL(fileManager: FileManager = .default) throws -> URL {
        let base = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                       appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("Backdrop", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("diagnostics.log")
    }

    public func log(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        let line = "\(timeFormatter.string(from: clock())) \(message)\n"
        let data = Data(line.utf8)
        let manager = FileManager.default
        if !manager.fileExists(atPath: fileURL.path) {
            manager.createFile(atPath: fileURL.path, contents: nil)
            approximateSize = 0
        }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            return
        }
        approximateSize += data.count
        if approximateSize > maxBytes {
            trim()
        }
    }

    public func contents() -> String {
        lock.lock()
        defer { lock.unlock() }
        return (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: fileURL)
        approximateSize = 0
    }

    /// Keeps the newest half of the budget, cut on a line boundary. Called with the
    /// lock held.
    private func trim() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let keep = maxBytes / 2
        guard data.count > keep else {
            approximateSize = data.count
            return
        }
        var start = data.count - keep
        if let newline = data[start...].firstIndex(of: UInt8(ascii: "\n")) {
            start = newline + 1
        }
        let kept = data[start...]
        try? Data(kept).write(to: fileURL, options: .atomic)
        approximateSize = kept.count
    }
}
