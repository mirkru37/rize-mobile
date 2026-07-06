import XCTest
@testable import RizeMobile

/// Covers `SyncClient.pushOutbox`: batching/cap enforcement, per-item result
/// handling (including partial failure), the `markSynced` guard, the
/// 401 -> single-flight-refresh -> retry path, and bounded/injected backoff.
/// See `SyncClientPullTests` for the pull side and `syncNow()`.
@MainActor
final class SyncClientPushTests: XCTestCase {
    private typealias Support = SyncClientTestSupport

    // MARK: Push — batching, cap, per-item results

    func testPushOutboxSendsPendingItemsAndMarksThemSyncedOnSuccess() async throws {
        let event = Support.makeEvent()
        let session = Support.makeSession()
        let store = SpyLocalStore()
        store.unsyncedBatches = [UnsyncedBatch(events: [event], sessions: [session]), UnsyncedBatch()]
        let apiClient = MockAPIClient()
        let authService = try await Support.makeAuthService(apiClient: apiClient, store: store)
        let client = Support.makeSyncClient(apiClient: apiClient, store: store, authService: authService)

        try await client.pushOutbox()

        XCTAssertEqual(apiClient.pushedItemBatches.count, 1)
        XCTAssertEqual(apiClient.pushedItemBatches[0].count, 2)
        XCTAssertEqual(store.markSyncedCalls.count, 1)
        XCTAssertEqual(store.markSyncedCalls[0].events.map(\.eventId), [event.eventId])
        XCTAssertEqual(store.markSyncedCalls[0].sessions.map(\.id), [session.id])
    }

    func testPushOutboxNeverRequestsMoreThanTheDocumentedFiveHundredItemCap() async throws {
        let store = SpyLocalStore()
        store.unsyncedBatches = [UnsyncedBatch()]
        let apiClient = MockAPIClient()
        let authService = try await Support.makeAuthService(apiClient: apiClient, store: store)
        // Configured well above the sync-protocol cap; SyncClient must clamp it.
        let client = Support.makeSyncClient(
            apiClient: apiClient,
            store: store,
            authService: authService,
            pushBatchLimit: 5000
        )

        try await client.pushOutbox()

        XCTAssertEqual(store.fetchUnsyncedBatchLimits, [500])
    }

    func testPushOutboxDrainsMultiplePagesUntilAShorterThanFullPageArrives() async throws {
        let store = SpyLocalStore()
        store.unsyncedBatches = [
            UnsyncedBatch(events: [Support.makeEvent()], sessions: []), // full page (limit = 1)
            UnsyncedBatch(events: [Support.makeEvent()], sessions: []), // still full
            UnsyncedBatch(events: [], sessions: []), // drained
        ]
        let apiClient = MockAPIClient()
        let authService = try await Support.makeAuthService(apiClient: apiClient, store: store)
        let client = Support.makeSyncClient(
            apiClient: apiClient,
            store: store,
            authService: authService,
            pushBatchLimit: 1
        )

        try await client.pushOutbox()

        XCTAssertEqual(apiClient.pushCallCount, 2)
        XCTAssertEqual(store.markSyncedCalls.count, 2)
    }

    func testPushOutboxHandlesPartialFailureResultsWithoutThrowing() async throws {
        let applied = Support.makeEvent()
        let invalid = Support.makeEvent()
        let duplicate = Support.makeSession()
        let store = SpyLocalStore()
        store.unsyncedBatches = [UnsyncedBatch(events: [applied, invalid], sessions: [duplicate])]
        let apiClient = MockAPIClient()
        apiClient.pushResults = [
            .success(SyncPushResponse(results: [
                SyncPushResult(
                    index: 0,
                    entityType: "activity_event",
                    eventId: applied.eventId.uuidString,
                    id: nil,
                    status: .applied,
                    serverSeq: nil
                ),
                SyncPushResult(
                    index: 1,
                    entityType: "activity_event",
                    eventId: invalid.eventId.uuidString,
                    id: nil,
                    status: .invalid,
                    serverSeq: nil
                ),
                SyncPushResult(
                    index: 2,
                    entityType: "focus_session",
                    eventId: nil,
                    id: duplicate.id.uuidString,
                    status: .duplicate,
                    serverSeq: 1
                ),
            ])),
        ]
        let authService = try await Support.makeAuthService(apiClient: apiClient, store: store)
        let client = Support.makeSyncClient(apiClient: apiClient, store: store, authService: authService)

        try await client.pushOutbox()

        // Partial success never blocks the rest of the batch: the whole
        // batch is durably handled per [[sync-protocol]] §Push.
        XCTAssertEqual(store.markSyncedCalls.count, 1)
        XCTAssertEqual(store.markSyncedCalls[0].events.count, 2)
        XCTAssertEqual(store.markSyncedCalls[0].sessions.count, 1)
    }

    // MARK: markSynced guard, end-to-end against the real GRDB store

    func testPushOutboxDoesNotFlagARowEditedWhileItsPushWasInFlight() async throws {
        let database = try AppDatabase.inMemory()
        let clock = TestClock()
        let store = GRDBLocalStore(database: database, deviceId: "device-1", clock: clock)
        let session = try await store.startSession(kind: .focus, projectId: nil, plannedDurationS: nil, note: "v1")

        let apiClient = MockAPIClient()
        apiClient.pushResults = [
            .success(SyncPushResponse(results: [
                SyncPushResult(
                    index: 0,
                    entityType: "focus_session",
                    eventId: nil,
                    id: session.id.uuidString,
                    status: .applied,
                    serverSeq: 1
                ),
            ])),
        ]
        let authService = try await Support.makeAuthService(apiClient: apiClient, store: store)
        let client = Support.makeSyncClient(apiClient: apiClient, store: store, authService: authService, clock: clock)

        // Simulate the row being edited locally between the batch fetch
        // (inside `pushOutbox`, before this call) and the push response
        // coming back, by editing it from inside the mock transport's
        // `pushEvents` handler — i.e. deterministically *after* `pushOutbox`
        // has already read the pre-edit snapshot for its outbox batch.
        apiClient.onPushEvents = {
            clock.advance(by: 5)
            _ = try? await store.editSession(id: session.id, projectId: nil, note: .some("edited during push"))
        }

        try await client.pushOutbox()

        let pending = try await store.fetchUnsyncedBatch(limit: 10)
        XCTAssertTrue(
            pending.sessions.contains { $0.id == session.id },
            "a row edited after its batch snapshot was taken must remain pending, not be marked synced"
        )
    }

    // MARK: 401 -> single-flight refresh -> retry of the original request

    func testAUnauthorizedPushResponseTriggersARefreshThenRetriesTheSameRequest() async throws {
        let event = Support.makeEvent()
        let store = SpyLocalStore()
        store.unsyncedBatches = [UnsyncedBatch(events: [event], sessions: [])]
        let apiClient = MockAPIClient()
        apiClient.pushResults = [
            .failure(APIClientError.unauthorized),
            .success(SyncPushResponse(results: [
                SyncPushResult(
                    index: 0,
                    entityType: "activity_event",
                    eventId: event.eventId.uuidString,
                    id: nil,
                    status: .applied,
                    serverSeq: nil
                ),
            ])),
        ]
        apiClient.refreshResults = [.success(Support.makeAuthResponse(accessToken: "refreshed-access"))]
        let authService = try await Support.makeAuthService(apiClient: apiClient, store: store)
        let client = Support.makeSyncClient(apiClient: apiClient, store: store, authService: authService)

        try await client.pushOutbox()

        XCTAssertEqual(apiClient.pushCallCount, 2, "the original push must be retried exactly once after refresh")
        XCTAssertEqual(apiClient.refreshCallCount, 1)
        XCTAssertEqual(apiClient.pushedAccessTokens, ["access-1", "refreshed-access"])
        XCTAssertEqual(store.markSyncedCalls.count, 1)
    }

    // MARK: Backoff / bounded retry

    func testATransientPushFailureRetriesWithInjectedBackoffThenSucceeds() async throws {
        let event = Support.makeEvent()
        let store = SpyLocalStore()
        store.unsyncedBatches = [UnsyncedBatch(events: [event], sessions: [])]
        let apiClient = MockAPIClient()
        apiClient.pushResults = [
            .failure(APIClientError.invalidResponse),
            .failure(APIClientError.invalidResponse),
            .success(SyncPushResponse(results: [
                SyncPushResult(
                    index: 0,
                    entityType: "activity_event",
                    eventId: event.eventId.uuidString,
                    id: nil,
                    status: .applied,
                    serverSeq: nil
                ),
            ])),
        ]
        let authService = try await Support.makeAuthService(apiClient: apiClient, store: store)
        let sleeper = FakeSleeper()
        let client = Support.makeSyncClient(
            apiClient: apiClient,
            store: store,
            authService: authService,
            sleeper: sleeper
        )

        try await client.pushOutbox()

        XCTAssertEqual(apiClient.pushCallCount, 3)
        // ExponentialBackoff(baseDelay: 1, multiplier: 2): 1s then 2s.
        XCTAssertEqual(sleeper.requestedDurations, [1, 2])
        XCTAssertEqual(store.markSyncedCalls.count, 1)
    }

    func testARepeatedlyFailingPushGivesUpAfterMaxRetryAttemptsAndLeavesTheOutboxIntact() async throws {
        let event = Support.makeEvent()
        let store = SpyLocalStore()
        store.unsyncedBatches = [UnsyncedBatch(events: [event], sessions: [])]
        let apiClient = MockAPIClient()
        apiClient.pushResults = Array(repeating: .failure(APIClientError.invalidResponse), count: 10)
        let authService = try await Support.makeAuthService(apiClient: apiClient, store: store)
        let sleeper = FakeSleeper()
        let client = Support.makeSyncClient(
            apiClient: apiClient,
            store: store,
            authService: authService,
            sleeper: sleeper,
            maxRetryAttempts: 2
        )

        await XCTAssertThrowsErrorAsync {
            try await client.pushOutbox()
        }

        // Never lose local data on any failure path: nothing was marked
        // synced, so the outbox is untouched for the next sync trigger.
        XCTAssertEqual(store.markSyncedCalls.count, 0)
        XCTAssertEqual(apiClient.pushCallCount, 3) // initial attempt + 2 retries
    }
}
