import XCTest
@testable import RizeMobile

final class SessionClockStateTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_735_689_600) // 2025-01-01T00:00:00Z

    func testElapsedWhileRunningIsNowMinusStartedAt() {
        let state = SessionClockState(startedAt: epoch)

        let elapsed = state.elapsed(now: epoch.addingTimeInterval(90))

        XCTAssertEqual(elapsed, 90)
    }

    func testElapsedFreezesAtPauseInstant() {
        var state = SessionClockState(startedAt: epoch)
        state.pause(at: epoch.addingTimeInterval(30))

        let elapsedShortlyAfterPause = state.elapsed(now: epoch.addingTimeInterval(120))

        XCTAssertEqual(elapsedShortlyAfterPause, 30)
    }

    func testResumeFoldsThePausedIntervalIntoAccumulatedPause() {
        var state = SessionClockState(startedAt: epoch)
        state.pause(at: epoch.addingTimeInterval(30))
        state.resume(at: epoch.addingTimeInterval(90)) // paused for 60s

        let elapsed = state.elapsed(now: epoch.addingTimeInterval(150))

        // 150s of wall time minus the 60s pause = 90s active.
        XCTAssertEqual(elapsed, 90)
    }

    func testPauseIsANoOpWhenAlreadyPaused() {
        var state = SessionClockState(startedAt: epoch)
        state.pause(at: epoch.addingTimeInterval(30))
        state.pause(at: epoch.addingTimeInterval(60)) // ignored: already paused

        XCTAssertEqual(state.pausedAt, epoch.addingTimeInterval(30))
    }

    func testResumeIsANoOpWhenNotPaused() {
        var state = SessionClockState(startedAt: epoch)
        state.resume(at: epoch.addingTimeInterval(60))

        XCTAssertEqual(state.accumulatedPauseS, 0)
        XCTAssertNil(state.pausedAt)
    }

    func testSupportsMultiplePauseResumeCycles() {
        var state = SessionClockState(startedAt: epoch)
        state.pause(at: epoch.addingTimeInterval(10)) // active: 10s
        state.resume(at: epoch.addingTimeInterval(20)) // paused: 10s
        state.pause(at: epoch.addingTimeInterval(40)) // active: 20s more
        state.resume(at: epoch.addingTimeInterval(45)) // paused: 5s more

        let elapsed = state.elapsed(now: epoch.addingTimeInterval(60))

        // 60s wall time minus 15s total paused = 45s active.
        XCTAssertEqual(elapsed, 45)
    }
}
