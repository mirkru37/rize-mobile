import XCTest
@testable import RizeMobile

@MainActor
final class SessionHistoryViewModelTests: XCTestCase {
    private func makeStore(clock: TestClock = TestClock()) throws -> GRDBLocalStore {
        let database = try AppDatabase.inMemory()
        return GRDBLocalStore(
            database: database,
            deviceId: "test-device",
            clock: clock,
            uuidGenerator: UUIDv7Generator(clock: clock)
        )
    }

    func testRefreshLoadsTodaysSessionsMostRecentFirst() async throws {
        let clock = TestClock()
        let store = try makeStore(clock: clock)
        let first = try await store.startSession(kind: .focus, projectId: nil, plannedDurationS: nil, note: nil)
        clock.advance(by: 60)
        let second = try await store.startSession(kind: .meeting, projectId: nil, plannedDurationS: nil, note: nil)

        let viewModel = SessionHistoryViewModel(store: store)
        try await viewModel.refresh()

        XCTAssertEqual(viewModel.sessions.map(\.id), [second.id, first.id])
    }

    func testEditSessionUpdatesNoteAndRefreshesTheList() async throws {
        let store = try makeStore()
        let session = try await store.startSession(kind: .focus, projectId: nil, plannedDurationS: nil, note: nil)
        _ = try await store.stopSession(id: session.id, status: .completed)

        let viewModel = SessionHistoryViewModel(store: store)
        try await viewModel.editSession(id: session.id, projectId: nil, note: .some("retro note"))

        XCTAssertEqual(viewModel.sessions.first { $0.id == session.id }?.note, "retro note")
    }

    func testDeleteSessionRemovesItFromTheVisibleList() async throws {
        let store = try makeStore()
        let session = try await store.startSession(kind: .focus, projectId: nil, plannedDurationS: nil, note: nil)

        let viewModel = SessionHistoryViewModel(store: store)
        try await viewModel.refresh()
        XCTAssertTrue(viewModel.sessions.contains { $0.id == session.id })

        try await viewModel.deleteSession(id: session.id)

        XCTAssertFalse(viewModel.sessions.contains { $0.id == session.id })
    }
}
