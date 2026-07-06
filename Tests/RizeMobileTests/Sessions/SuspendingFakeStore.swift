import Foundation
@testable import RizeMobile

/// A `LocalStoring` fake whose `startSession`/`fetchTodayData` suspend until
/// the test explicitly releases them, so tests can deterministically land a
/// second call inside the window where a first call is still awaiting the
/// store — the exact reentrancy window `SessionEngine`'s `isMutating` guard
/// closes. Only the methods exercised by the reentrancy/recovery tests are
/// implemented for real; the rest are unused stubs.
final class SuspendingFakeStore: LocalStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var fetchContinuation: CheckedContinuation<Void, Never>?

    private(set) var startCallCount = 0
    private(set) var fetchCallCount = 0
    var recordToReturn = FocusSessionRecord(
        id: UUID(),
        deviceId: "test-device",
        kind: .focus,
        startedAt: Date(),
        status: .running,
        createdAt: Date(),
        updatedAt: Date()
    )
    var todayDataToReturn = TodayData()

    /// Resumes a `startSession` call currently suspended inside this fake.
    func releaseStart() {
        lock.lock()
        let continuation = startContinuation
        startContinuation = nil
        lock.unlock()
        continuation?.resume()
    }

    /// Resumes a `fetchTodayData` call currently suspended inside this fake.
    func releaseFetch() {
        lock.lock()
        let continuation = fetchContinuation
        fetchContinuation = nil
        lock.unlock()
        continuation?.resume()
    }

    func startSession(
        kind _: FocusSessionKind,
        projectId _: UUID?,
        plannedDurationS _: Int?,
        note _: String?
    ) async throws -> FocusSessionRecord {
        lock.lock()
        startCallCount += 1
        lock.unlock()
        await withCheckedContinuation { continuation in
            lock.lock()
            startContinuation = continuation
            lock.unlock()
        }
        return recordToReturn
    }

    func stopSession(id _: UUID, status _: FocusSessionStatus) async throws -> FocusSessionRecord {
        recordToReturn
    }

    func editSession(id _: UUID, projectId _: UUID??, note _: String??) async throws -> FocusSessionRecord {
        recordToReturn
    }

    func deleteSession(id _: UUID) async throws -> FocusSessionRecord {
        recordToReturn
    }

    func recordApproximateEvent(
        startedAt _: Date,
        endedAt _: Date,
        appBundleId _: String?,
        categoryId _: UUID?,
        projectId _: UUID?
    ) async throws -> ActivityEventRecord {
        fatalError("not used by SuspendingFakeStore tests")
    }

    func fetchTodayData() async throws -> TodayData {
        lock.lock()
        fetchCallCount += 1
        lock.unlock()
        await withCheckedContinuation { continuation in
            lock.lock()
            fetchContinuation = continuation
            lock.unlock()
        }
        return todayDataToReturn
    }

    func fetchUnsyncedBatch(limit _: Int) async throws -> UnsyncedBatch {
        UnsyncedBatch()
    }

    func markSynced(eventIds _: [UUID], sessionIds _: [UUID]) async throws {}
}
