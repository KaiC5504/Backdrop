import Foundation
import Testing
@testable import BackdropCore

@Suite struct ResumePolicyTests {
    @Test func finishedWindowIsFiveSecondsOrFivePercent() {
        #expect(ResumePolicy.isFinished(position: 95, duration: 100))
        #expect(!ResumePolicy.isFinished(position: 94.9, duration: 100))
        // short video: 5 s wins over 5 %
        #expect(ResumePolicy.isFinished(position: 15, duration: 20))
        #expect(!ResumePolicy.isFinished(position: 14, duration: 20))
        // long video: 5 % wins over 5 s
        #expect(ResumePolicy.isFinished(position: 950, duration: 1000))
        #expect(!ResumePolicy.isFinished(position: 949, duration: 1000))
        #expect(!ResumePolicy.isFinished(position: 10, duration: 0))
    }

    @Test func startTimeIgnoresShortAndFinishedPositions() {
        #expect(ResumePolicy.startTime(savedPosition: nil, duration: 100) == 0)
        #expect(ResumePolicy.startTime(savedPosition: 4.9, duration: 100) == 0)
        #expect(ResumePolicy.startTime(savedPosition: 5, duration: 100) == 5)
        #expect(ResumePolicy.startTime(savedPosition: 42, duration: 100) == 42)
        #expect(ResumePolicy.startTime(savedPosition: 96, duration: 100) == 0)
    }

    @Test func positionToStoreDropsTrivialAndFinished() {
        #expect(ResumePolicy.positionToStore(position: 2, duration: 100) == nil)
        #expect(ResumePolicy.positionToStore(position: 50, duration: 100) == 50)
        #expect(ResumePolicy.positionToStore(position: 96, duration: 100) == nil)
        // unknown duration: keep the position, nothing to judge it against
        #expect(ResumePolicy.positionToStore(position: 50, duration: 0) == 50)
    }
}
