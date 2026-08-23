import Foundation
import Testing
@testable import BackdropCore

@Suite struct PlaybackStoreTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("backdrop-store-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("state.json")
    }

    private func prepared() -> URL {
        let url = tempURL()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return url
    }

    @Test func freshStoreHasDefaults() {
        let store = PlaybackStore(fileURL: prepared())
        #expect(store.speed == 1)
        #expect(store.loop == false)
        #expect(store.position(for: "v") == nil)
        #expect(store.loadError == nil)
    }

    @Test func positionsSpeedAndLoopRoundTrip() {
        let url = prepared()
        let store = PlaybackStore(fileURL: url)
        store.setPosition(42.5, for: "v1")
        store.setPosition(7, for: "v2")
        store.speed = 1.5
        store.loop = true
        #expect(store.lastWriteError == nil)

        let reloaded = PlaybackStore(fileURL: url)
        #expect(reloaded.position(for: "v1") == 42.5)
        #expect(reloaded.position(for: "v2") == 7)
        #expect(reloaded.speed == 1.5)
        #expect(reloaded.loop == true)
    }

    @Test func nilRemovesPosition() {
        let url = prepared()
        let store = PlaybackStore(fileURL: url)
        store.setPosition(10, for: "v")
        store.setPosition(nil, for: "v")
        #expect(store.position(for: "v") == nil)
        #expect(PlaybackStore(fileURL: url).position(for: "v") == nil)
    }

    @Test func corruptFileStartsEmptyAndReportsIt() throws {
        let url = prepared()
        try Data("not json".utf8).write(to: url)
        let store = PlaybackStore(fileURL: url)
        #expect(store.loadError != nil)
        #expect(store.speed == 1)
        #expect(store.snapshot.positions.isEmpty)
    }

    @Test func missingDirectoryIsReportedNotFatal() {
        let url = tempURL() // parent never created
        let store = PlaybackStore(fileURL: url)
        store.setPosition(10, for: "v")
        #expect(store.lastWriteError != nil)
        #expect(store.position(for: "v") == 10)
    }
}
