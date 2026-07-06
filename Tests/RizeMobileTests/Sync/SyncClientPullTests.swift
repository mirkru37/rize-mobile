import XCTest
@testable import RizeMobile

/// Covers `SyncClient.pullChanges` (upserts, tombstones, cursor persistence
/// across pages) and `syncNow()`'s overall push-then-pull orchestration. See
/// `SyncClientPushTests` for the push side.
@MainActor
final class SyncClientPullTests: XCTestCase {
    private typealias Support = SyncClientTestSupport

    // MARK: Pull — upserts, tombstones, cursor persistence

    func testPullChangesAppliesUpsertsAndTombstonesAndPersistsCursorAcrossPages() async throws {
        let store = SpyLocalStore()
        let apiClient = MockAPIClient()
        let eventUpsert = SyncPullEventChange(
            eventId: UUID().uuidString,
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 160),
            appBundleId: "remote.app",
            category: "Development",
            precision: "approximate",
            serverSeq: 1
        )
        let sessionTombstone = SyncPullSessionTombstone(id: UUID().uuidString, serverSeq: 2)

        apiClient.pullResults = [
            .success(SyncPullResponse(
                changes: SyncChanges(
                    activityEvents: SyncEntityChangePage(upserts: [eventUpsert], tombstones: []),
                    focusSessions: nil
                ),
                nextCursor: "cursor-page-1",
                hasMore: true
            )),
            .success(SyncPullResponse(
                changes: SyncChanges(
                    activityEvents: nil,
                    focusSessions: SyncEntityChangePage(upserts: [], tombstones: [sessionTombstone])
                ),
                nextCursor: "cursor-page-2",
                hasMore: false
            )),
        ]
        let authService = try await Support.makeAuthService(apiClient: apiClient, store: store)
        let cursorStore = InMemorySyncCursorStore()
        let client = Support.makeSyncClient(
            apiClient: apiClient,
            store: store,
            authService: authService,
            cursorStore: cursorStore
        )

        try await client.pullChanges()

        XCTAssertEqual(apiClient.pullCallCount, 2)
        XCTAssertEqual(apiClient.pulledCursors, [nil, "cursor-page-1"])
        XCTAssertEqual(store.appliedEventChanges.count, 1)
        XCTAssertEqual(store.appliedEventChanges[0].upserts.first?.eventId.uuidString, eventUpsert.eventId)
        XCTAssertEqual(store.appliedSessionChanges.count, 1)
        XCTAssertEqual(store.appliedSessionChanges[0].tombstoneIds.first?.uuidString, sessionTombstone.id)
        XCTAssertEqual(cursorStore.loadCursor(), "cursor-page-2")
    }

    // MARK: syncNow — swallows failures, records last-sync time on success

    func testSyncNowNeverThrowsAndLeavesLastSyncAtUnsetOnFailure() async throws {
        let store = SpyLocalStore()
        store.unsyncedBatches = [UnsyncedBatch()]
        let apiClient = MockAPIClient()
        apiClient.pullResults = [.failure(APIClientError.invalidResponse)]
        let authService = try await Support.makeAuthService(apiClient: apiClient, store: store)
        let client = Support.makeSyncClient(
            apiClient: apiClient,
            store: store,
            authService: authService,
            maxRetryAttempts: 0
        )

        await client.syncNow() // must not throw

        XCTAssertNil(authService.lastSyncAt)
    }

    func testSyncNowRecordsLastSyncAtOnSuccess() async throws {
        let store = SpyLocalStore()
        store.unsyncedBatches = [UnsyncedBatch()]
        let apiClient = MockAPIClient()
        let clock = TestClock(Date(timeIntervalSince1970: 5000))
        let authService = try await Support.makeAuthService(apiClient: apiClient, store: store)
        let client = Support.makeSyncClient(apiClient: apiClient, store: store, authService: authService, clock: clock)

        await client.syncNow()

        XCTAssertEqual(authService.lastSyncAt, Date(timeIntervalSince1970: 5000))
    }
}
