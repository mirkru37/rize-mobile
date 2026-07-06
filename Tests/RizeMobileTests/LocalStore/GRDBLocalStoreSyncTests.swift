import XCTest
@testable import RizeMobile

/// Sync-facing `GRDBLocalStore` coverage split out of `GRDBLocalStoreTests`
/// (SwiftLint `type_body_length`/`file_length`, RIZ-65 cleanup): tombstones,
/// `fetchUnsyncedBatch`/`markSynced`, and applying pulled changes. Session
/// lifecycle / today-data / logout coverage stays in `GRDBLocalStoreTests`.
final class GRDBLocalStoreSyncTests: XCTestCase {
    private func makeStore(clock: TestClock = TestClock()) throws -> (GRDBLocalStore, TestClock) {
        let database = try AppDatabase.inMemory()
        let store = GRDBLocalStore(
            database: database,
            deviceId: "test-device",
            clock: clock,
            uuidGenerator: UUIDv7Generator(clock: clock)
        )
        return (store, clock)
    }

    // MARK: Tombstones

    func testDeleteSessionSetsDeletedAtRatherThanRemovingTheRow() async throws {
        let (store, clock) = try makeStore()
        let session = try await store.startSession(kind: .breakTime, projectId: nil, plannedDurationS: nil, note: nil)

        clock.advance(by: 5)
        let deleted = try await store.deleteSession(id: session.id)

        XCTAssertEqual(deleted.deletedAt, clock.now())

        // The row still exists locally (soft delete / tombstone), and is
        // marked pending so the tombstone itself gets pushed on next sync.
        let batch = try await store.fetchUnsyncedBatch(limit: 500)
        XCTAssertTrue(batch.sessions.contains { $0.id == session.id && $0.deletedAt != nil })
    }

    func testTombstonedSessionsAreExcludedFromTodayData() async throws {
        let (store, _) = try makeStore()
        let session = try await store.startSession(kind: .focus, projectId: nil, plannedDurationS: nil, note: nil)
        _ = try await store.deleteSession(id: session.id)

        let today = try await store.fetchTodayData()

        XCTAssertFalse(today.sessions.contains { $0.id == session.id })
    }

    // MARK: Unsynced batch / mark synced

    func testFetchUnsyncedBatchReturnsOnlyPendingRows() async throws {
        let (store, _) = try makeStore()

        let event = try await store.recordApproximateEvent(
            startedAt: Date(),
            endedAt: Date().addingTimeInterval(60),
            appBundleId: "a",
            categoryId: nil,
            projectId: nil
        )
        let session = try await store.startSession(kind: .focus, projectId: nil, plannedDurationS: nil, note: nil)

        var batch = try await store.fetchUnsyncedBatch(limit: 500)
        XCTAssertEqual(batch.count, 2)

        try await store.markSynced(
            events: [SyncedEventSnapshot(eventId: event.eventId, insertedAt: event.insertedAt)],
            sessions: []
        )

        batch = try await store.fetchUnsyncedBatch(limit: 500)
        XCTAssertEqual(batch.events.count, 0)
        XCTAssertEqual(batch.sessions.count, 1)
        XCTAssertEqual(batch.sessions.first?.id, session.id)
    }

    func testFetchUnsyncedBatchRespectsCombinedLimitAcrossEntityTypes() async throws {
        let (store, _) = try makeStore()

        for eventIndex in 0 ..< 3 {
            try await store.recordApproximateEvent(
                startedAt: Date().addingTimeInterval(Double(eventIndex)),
                endedAt: Date().addingTimeInterval(Double(eventIndex) + 60),
                appBundleId: "app-\(eventIndex)",
                categoryId: nil,
                projectId: nil
            )
        }
        for _ in 0 ..< 3 {
            _ = try await store.startSession(kind: .focus, projectId: nil, plannedDurationS: nil, note: nil)
        }

        let batch = try await store.fetchUnsyncedBatch(limit: 4)

        XCTAssertEqual(batch.count, 4)
        XCTAssertEqual(batch.events.count, 3)
        XCTAssertEqual(batch.sessions.count, 1)
    }

    func testMarkSyncedIsIdempotentAndOnlyAffectsGivenIds() async throws {
        let (store, _) = try makeStore()

        let eventA = try await store.recordApproximateEvent(
            startedAt: Date(), endedAt: Date().addingTimeInterval(60), appBundleId: "a", categoryId: nil, projectId: nil
        )
        let eventB = try await store.recordApproximateEvent(
            startedAt: Date(), endedAt: Date().addingTimeInterval(60), appBundleId: "b", categoryId: nil, projectId: nil
        )

        let snapshotA = SyncedEventSnapshot(eventId: eventA.eventId, insertedAt: eventA.insertedAt)
        try await store.markSynced(events: [snapshotA], sessions: [])
        try await store.markSynced(events: [snapshotA], sessions: []) // repeat: no-op, no error

        let batch = try await store.fetchUnsyncedBatch(limit: 500)
        XCTAssertEqual(batch.events.count, 1)
        XCTAssertEqual(batch.events.first?.eventId, eventB.eventId)
    }

    func testMarkSyncedWithNoIdsIsANoOp() async throws {
        let (store, _) = try makeStore()
        try await store.recordApproximateEvent(
            startedAt: Date(), endedAt: Date().addingTimeInterval(60), appBundleId: "a", categoryId: nil, projectId: nil
        )

        try await store.markSynced(events: [], sessions: [])

        let batch = try await store.fetchUnsyncedBatch(limit: 500)
        XCTAssertEqual(batch.count, 1)
    }

    // MARK: markSynced guard (RIZ-46, carried over from RIZ-43 review finding M1)

    func testMarkSyncedDoesNotFlagASessionEditedAfterTheBatchWasFetched() async throws {
        let (store, clock) = try makeStore()
        let session = try await store.startSession(kind: .focus, projectId: nil, plannedDurationS: nil, note: "v1")

        // Snapshot taken "at batch-fetch time" — before the race.
        let staleSnapshot = SyncedSessionSnapshot(id: session.id, updatedAt: session.updatedAt)

        // The row changes locally while a push of the stale snapshot is
        // hypothetically still in flight.
        clock.advance(by: 5)
        _ = try await store.editSession(id: session.id, projectId: nil, note: .some("v2"))

        try await store.markSynced(events: [], sessions: [staleSnapshot])

        let batch = try await store.fetchUnsyncedBatch(limit: 500)
        XCTAssertTrue(
            batch.sessions.contains { $0.id == session.id },
            "a row edited after its batch snapshot was taken must remain pending"
        )
    }

    func testMarkSyncedFlagsASessionUnchangedSinceTheBatchWasFetched() async throws {
        let (store, _) = try makeStore()
        let session = try await store.startSession(kind: .focus, projectId: nil, plannedDurationS: nil, note: nil)
        let snapshot = SyncedSessionSnapshot(id: session.id, updatedAt: session.updatedAt)

        try await store.markSynced(events: [], sessions: [snapshot])

        let batch = try await store.fetchUnsyncedBatch(limit: 500)
        XCTAssertFalse(batch.sessions.contains { $0.id == session.id })
    }

    // MARK: Applying pulled changes

    func testApplyEventChangesUpsertsAndMarksSynced() async throws {
        let (store, clock) = try makeStore()
        let upsert = ActivityEventRecord(
            eventId: UUID(),
            deviceId: "other-device",
            startedAt: clock.now(),
            endedAt: clock.now().addingTimeInterval(60),
            appBundleId: "remote.app",
            insertedAt: clock.now()
        )

        try await store.applyEventChanges(upserts: [upsert], tombstoneIds: [])

        let today = try await store.fetchTodayData()
        XCTAssertTrue(today.events.contains { $0.eventId == upsert.eventId })

        let batch = try await store.fetchUnsyncedBatch(limit: 500)
        XCTAssertFalse(batch.events.contains { $0.eventId == upsert.eventId })
    }

    func testApplyEventChangesTombstonesByEventId() async throws {
        let (store, _) = try makeStore()
        let event = try await store.recordApproximateEvent(
            startedAt: Date(), endedAt: Date().addingTimeInterval(60), appBundleId: "a", categoryId: nil, projectId: nil
        )

        try await store.applyEventChanges(upserts: [], tombstoneIds: [event.eventId])

        let today = try await store.fetchTodayData()
        XCTAssertFalse(today.events.contains { $0.eventId == event.eventId })
    }

    func testApplySessionChangesUpsertsWhenIncomingIsNewer() async throws {
        let (store, clock) = try makeStore()
        let session = try await store.startSession(kind: .focus, projectId: nil, plannedDurationS: nil, note: "v1")

        clock.advance(by: 10)
        var remoteVersion = session
        remoteVersion.note = "v2 from another device"
        remoteVersion.updatedAt = clock.now()

        try await store.applySessionChanges(upserts: [remoteVersion], tombstoneIds: [])

        let today = try await store.fetchTodayData()
        XCTAssertEqual(today.sessions.first { $0.id == session.id }?.note, "v2 from another device")
    }

    func testApplySessionChangesIgnoresAnOlderIncomingVersion() async throws {
        let (store, clock) = try makeStore()
        let session = try await store.startSession(kind: .focus, projectId: nil, plannedDurationS: nil, note: "v1")

        clock.advance(by: 10)
        _ = try await store.editSession(id: session.id, projectId: nil, note: .some("v2 local"))

        // A stale upsert from before the local edit must not clobber it.
        try await store.applySessionChanges(upserts: [session], tombstoneIds: [])

        let today = try await store.fetchTodayData()
        XCTAssertEqual(today.sessions.first { $0.id == session.id }?.note, "v2 local")
    }

    func testApplySessionChangesAppliesTombstones() async throws {
        let (store, _) = try makeStore()
        let session = try await store.startSession(kind: .focus, projectId: nil, plannedDurationS: nil, note: nil)

        try await store.applySessionChanges(upserts: [], tombstoneIds: [session.id])

        let today = try await store.fetchTodayData()
        XCTAssertFalse(today.sessions.contains { $0.id == session.id })
    }
}
