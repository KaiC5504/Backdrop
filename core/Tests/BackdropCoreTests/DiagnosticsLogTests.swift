import Foundation
import Testing
@testable import BackdropCore

@Suite struct DiagnosticsLogTests {
    private func tempFile() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("backdrop-log-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("diagnostics.log")
    }

    private var fixedClock: @Sendable () -> Date {
        let utc = TimeZone(identifier: "UTC")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let date = calendar.date(from: DateComponents(year: 2026, month: 8, day: 23, hour: 14, minute: 5, second: 9))!
        return { date }
    }

    @Test func linesAreTimestampedAndAppended() {
        let log = DiagnosticsLog(fileURL: tempFile(), clock: fixedClock, timeZone: TimeZone(identifier: "UTC")!)
        log.log("engine.load a")
        log.log("engine.play")
        #expect(log.contents() == "14:05:09.000 engine.load a\n14:05:09.000 engine.play\n")
    }

    @Test func clearEmptiesTheFile() {
        let log = DiagnosticsLog(fileURL: tempFile(), clock: fixedClock, timeZone: TimeZone(identifier: "UTC")!)
        log.log("x")
        log.clear()
        #expect(log.contents() == "")
        log.log("y")
        #expect(log.contents().hasSuffix(" y\n"))
    }

    @Test func trimsToRecentLinesWhenOverBudget() {
        let log = DiagnosticsLog(fileURL: tempFile(), maxBytes: 200, clock: fixedClock, timeZone: TimeZone(identifier: "UTC")!)
        for i in 0..<40 {
            log.log("line \(i)")
        }
        let text = log.contents()
        #expect(text.utf8.count <= 200)
        #expect(text.hasSuffix("line 39\n"))
        #expect(!text.contains("line 0\n"))
        // every surviving line is whole
        #expect(text.hasPrefix("14:05:09.000 "))
    }

    @Test func survivesMissingFileOnRead() {
        let log = DiagnosticsLog(fileURL: tempFile(), clock: fixedClock, timeZone: TimeZone(identifier: "UTC")!)
        #expect(log.contents() == "")
    }
}
