import Foundation
@testable import RizeMobile

/// A queue-of-canned-responses `APIClientProtocol` fake — the "mock
/// transport" `SyncClient`/`AuthService` tests are built against. Each
/// method call consumes the next entry in its results queue (clamped to the
/// last entry once exhausted, so a test can configure "fail once, then
/// succeed forever" with a two-element queue).
final class MockAPIClient: APIClientProtocol, @unchecked Sendable {
    private let lock = NSLock()

    var registerResult: Result<AuthResponse, Error> = .failure(SyncStubError())
    var loginResult: Result<AuthResponse, Error> = .failure(SyncStubError())
    var refreshResults: [Result<AuthResponse, Error>] = [.failure(SyncStubError())]
    var logoutResult: Result<Void, Error> = .success(())
    var pushResults: [Result<SyncPushResponse, Error>] = [.success(SyncPushResponse(results: []))]
    var pullResults: [Result<SyncPullResponse, Error>] = [
        .success(SyncPullResponse(changes: SyncChanges(), nextCursor: nil, hasMore: false)),
    ]

    private(set) var refreshCallCount = 0
    private(set) var logoutCallCount = 0
    private(set) var pushCallCount = 0
    private(set) var pullCallCount = 0
    private(set) var pushedItemBatches: [[SyncPushItem]] = []
    private(set) var pushedAccessTokens: [String] = []
    private(set) var pulledCursors: [String?] = []

    /// Invoked (and awaited) at the start of `pushEvents`, before the canned
    /// result is returned — lets a test simulate a local mutation racing with
    /// an in-flight push (e.g. to exercise the `markSynced` guard) by editing
    /// the record from inside this hook, deterministically between the
    /// batch fetch and the response being applied.
    var onPushEvents: (@Sendable () async -> Void)?

    func register(email _: String, password _: String, device _: DeviceInfo) async throws -> AuthResponse {
        try registerResult.get()
    }

    func login(email _: String, password _: String, device _: DeviceInfo) async throws -> AuthResponse {
        try loginResult.get()
    }

    func refresh(refreshToken _: String, device _: DeviceInfo?) async throws -> AuthResponse {
        lock.lock()
        let index = min(refreshCallCount, refreshResults.count - 1)
        refreshCallCount += 1
        lock.unlock()
        return try refreshResults[index].get()
    }

    func logout(accessToken _: String, refreshToken _: String) async throws {
        lock.lock()
        logoutCallCount += 1
        lock.unlock()
        try logoutResult.get()
    }

    func pushEvents(accessToken: String, deviceId _: String, items: [SyncPushItem]) async throws -> SyncPushResponse {
        lock.lock()
        let index = min(pushCallCount, pushResults.count - 1)
        pushCallCount += 1
        pushedItemBatches.append(items)
        pushedAccessTokens.append(accessToken)
        lock.unlock()
        await onPushEvents?()
        return try pushResults[index].get()
    }

    func pullChanges(accessToken _: String, cursor: String?, limit _: Int) async throws -> SyncPullResponse {
        lock.lock()
        let index = min(pullCallCount, pullResults.count - 1)
        pullCallCount += 1
        pulledCursors.append(cursor)
        lock.unlock()
        return try pullResults[index].get()
    }
}

struct SyncStubError: Error, Equatable {}
