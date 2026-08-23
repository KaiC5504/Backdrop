import Foundation
import Testing
@testable import BackdropCore

@Suite struct VideoTitleFormatterTests {
    private let utc = TimeZone(identifier: "UTC")!
    private var formatter: VideoTitleFormatter {
        VideoTitleFormatter(locale: Locale(identifier: "en_US_POSIX"), timeZone: utc)
    }

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    private func item(date: Date?, album: String? = nil) -> VideoItem {
        VideoItem(id: "x", source: .photos(localIdentifier: "x"), duration: 10,
                  creationDate: date, pixelWidth: 1920, pixelHeight: 1080, albumTitle: album)
    }

    @Test func titleIsWeekdayDateAndTime() {
        #expect(formatter.title(for: item(date: date(2026, 8, 23, 14, 5))) == "Sun 23 Aug 2026, 14:05")
    }

    @Test func titleWithoutDateIsGeneric() {
        #expect(formatter.title(for: item(date: nil)) == "Video")
    }

    @Test func subtitleIsAlbumOrPhotos() {
        #expect(formatter.subtitle(for: item(date: nil, album: "Gym")) == "Gym")
        #expect(formatter.subtitle(for: item(date: nil)) == "Photos")
    }

    @Test func durationLabels() {
        #expect(VideoTitleFormatter.durationLabel(5) == "0:05")
        #expect(VideoTitleFormatter.durationLabel(65) == "1:05")
        #expect(VideoTitleFormatter.durationLabel(3723) == "1:02:03")
        #expect(VideoTitleFormatter.durationLabel(59.9) == "0:59")
        #expect(VideoTitleFormatter.durationLabel(-3) == "0:00")
    }

    @Test func aspectRatioFallsBackToWidescreen() {
        #expect(item(date: nil).aspectRatio == 1920.0 / 1080.0)
        let square = VideoItem(id: "s", source: .photos(localIdentifier: "s"), duration: 1,
                               creationDate: nil, pixelWidth: 0, pixelHeight: 0)
        #expect(square.aspectRatio == 16.0 / 9.0)
    }
}
