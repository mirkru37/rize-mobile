import Foundation
@testable import RizeMobile

/// A `LocalStoring` fake for `SyncClient` tests: serves a scripted queue of
/// `fetchUnsyncedBatch` results (so a test can simulate "one full page, then
/// an empty page" to exercise the push loop's draining behavior) and records
/// every call for assertions, without touching GRDB.
final class SpyLocalStore: LocalStoring, @unchecked Sendable {
    private let lock = NSLock()

    var unsyncedBatches: [UnsyncedBatch] = [UnsyncedBatch()]
    private var unsyncedBatchCallIndex = 0

    private(set) var fetchUnsyncedBatchLimits: [Int] = []
    private(set) var markSyncedCalls: [(events: [SyncedEventSnapshot], sessions: [SyncedSessionSnapshot])] = []
    private(set) var appliedEventChanges: [(upserts: [ActivityEventRecord], tombstoneIds: [UUID])] = []
    private(set) var appliedSessionChanges: [(upserts: [FocusSessionRecord], tombstoneIds: [UUID])] = []
    private(set) var wipeAllDataCallCount = 0

    func startSession(
        kind _: FocusSessionKind,
        projectId _: UUID?,
        plannedDurationS _: Int?,
        note _: String?
    ) async throws -> FocusSessionRecord {
        fatalError("not used by SyncClient tests")
    }

    func stopSession(id _: UUID, status _: FocusSessionStatus) async throws -> FocusSessionRecord {
        fatalError("not used by SyncClient tests")
    }

    func editSession(id _: UUID, projectId _: UUID??, note _: String??) async throws -> FocusSessionRecord {
        fatalError("not used by SyncClient tests")
    }

    func deleteSession(id _: UUID) async throws -> FocusSessionRecord {
        fatalError("not used by SyncClient tests")
    }

    func recordApproximateEvent(
        startedAt _: Date,
        endedAt _: Date,
        appBundleId _: String?,
        categoryId _: UUID?,
        projectId _: UUID?
    ) async throws -> ActivityEventRecord {
        fatalError("not used by SyncClient tests")
    }

    func fetchTodayData() async throws -> TodayData {
        TodayData()
    }

    func fetchActiveRunningSession() async throws -> FocusSessionRecord? {
        nil
    }

    func fetchUnsyncedBatch(limit: Int) async throws -> UnsyncedBatch {
        lock.lock()
        fetchUnsyncedBatchLimits.append(limit)
        let index = min(unsyncedBatchCallIndex, unsyncedBatches.count - 1)
        unsyncedBatchCallIndex += 1
        lock.unlock()
        return unsyncedBatches[index]
    }

    func markSynced(events: [SyncedEventSnapshot], sessions: [SyncedSessionSnapshot]) async throws {
        lock.lock()
        markSyncedCalls.append((events, sessions))
        lock.unlock()
    }

    func applyEventChanges(upserts: [ActivityEventRecord], tombstoneIds: [UUID]) async throws {
        lock.lock()
        appliedEventChanges.append((upserts, tombstoneIds))
        lock.unlock()
    }

    func applySessionChanges(upserts: [FocusSessionRecord], tombstoneIds: [UUID]) async throws {
        lock.lock()
        appliedSessionChanges.append((upserts, tombstoneIds))
        lock.unlock()
    }

    func wipeAllData() async throws {
        lock.lock()
        wipeAllDataCallCount += 1
        lock.unlock()
    }
}
