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

    @Test func writeAfterCorruptFileOverwritesIt() throws {
        let url = prepared()
        try Data("not json".utf8).write(to: url)
        let store = PlaybackStore(fileURL: url)
        #expect(store.loadError != nil)
        store.setPosition(42, for: "x")

        let reloaded = PlaybackStore(fileURL: url)
        #expect(reloaded.position(for: "x") == 42)
        #expect(reloaded.loadError == nil)
    }

    @Test func missingDirectoryIsReportedNotFatal() {
        let url = tempURL() // parent never created
        let store = PlaybackStore(fileURL: url)
        store.setPosition(10, for: "v")
        #expect(store.lastWriteError != nil)
        #expect(store.position(for: "v") == 10)
    }

    @Test func favouritesStartEmpty() {
        let store = PlaybackStore(fileURL: prepared())
        #expect(store.favourites.isEmpty)
        #expect(store.isFavourite("v") == false)
    }

    @Test func toggleAddsThenRemovesAndReportsNewState() {
        let url = prepared()
        let store = PlaybackStore(fileURL: url)
        #expect(store.toggleFavourite("a") == true)
        #expect(store.toggleFavourite("b") == true)
        #expect(store.favourites == ["a", "b"])
        #expect(store.isFavourite("a"))
        #expect(store.toggleFavourite("a") == false)
        #expect(store.favourites == ["b"])
        #expect(PlaybackStore(fileURL: url).favourites == ["b"])
    }

    @Test func favouritesKeepOrderAcrossReload() {
        let url = prepared()
        let store = PlaybackStore(fileURL: url)
        for id in ["c", "a", "b"] { store.toggleFavourite(id) }
        #expect(PlaybackStore(fileURL: url).favourites == ["c", "a", "b"])
    }

    @Test func moveFavouriteForwardAndBack() {
        let store = PlaybackStore(fileURL: prepared())
        for id in ["a", "b", "c", "d"] { store.toggleFavourite(id) }
        store.moveFavourite("a", to: 2)   // dragged right, dropped over "c"
        #expect(store.favourites == ["b", "c", "a", "d"])
        store.moveFavourite("d", to: 0)   // dragged left, dropped over "b"
        #expect(store.favourites == ["d", "b", "c", "a"])
    }

    @Test func moveFavouriteIgnoresUnknownAndClamps() {
        let store = PlaybackStore(fileURL: prepared())
        for id in ["a", "b", "c"] { store.toggleFavourite(id) }
        store.moveFavourite("zzz", to: 0)
        #expect(store.favourites == ["a", "b", "c"])
        store.moveFavourite("a", to: 99)
        #expect(store.favourites == ["b", "c", "a"])
        store.moveFavourite("a", to: -5)
        #expect(store.favourites == ["a", "b", "c"])
        store.moveFavourite("b", to: 1)
        #expect(store.favourites == ["a", "b", "c"])
    }

    @Test func stateFileWithoutFavouritesKeyStillLoads() throws {
        let url = prepared()
        try Data(#"{"loop":true,"positions":{"v":12.5},"speed":1.5}"#.utf8).write(to: url)
        let store = PlaybackStore(fileURL: url)
        #expect(store.loadError == nil)
        #expect(store.favourites.isEmpty)
        #expect(store.position(for: "v") == 12.5)
        #expect(store.speed == 1.5)
        #expect(store.loop == true)
    }
}
