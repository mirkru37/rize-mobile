import XCTest
@testable import RizeMobile

final class UserDefaultsSessionClockStoreTests: XCTestCase {
    private func makeSubject() -> UserDefaultsSessionClockStore {
        let suiteName = "com.rizeclone.mobile.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return UserDefaultsSessionClockStore(defaults: defaults)
    }

    func testLoadReturnsNilWhenNothingIsPersisted() {
        let subject = makeSubject()

        XCTAssertNil(subject.load(sessionId: UUID()))
    }

    func testSaveThenLoadRoundTripsForTheSameSessionId() {
        let subject = makeSubject()
        let sessionId = UUID()
        let state = SessionClockState(startedAt: Date(timeIntervalSince1970: 1_735_689_600), accumulatedPauseS: 30)

        subject.save(state, sessionId: sessionId)

        XCTAssertEqual(subject.load(sessionId: sessionId), state)
    }

    func testLoadReturnsNilForADifferentSessionId() {
        let subject = makeSubject()
        let state = SessionClockState(startedAt: Date())
        subject.save(state, sessionId: UUID())

        XCTAssertNil(subject.load(sessionId: UUID()))
    }

    func testClearRemovesThePersistedState() {
        let subject = makeSubject()
        let sessionId = UUID()
        subject.save(SessionClockState(startedAt: Date()), sessionId: sessionId)

        subject.clear()

        XCTAssertNil(subject.load(sessionId: sessionId))
    }
}
