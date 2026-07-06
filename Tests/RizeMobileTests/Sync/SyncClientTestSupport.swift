import XCTest
@testable import RizeMobile

/// Shared fixtures for `SyncClientPushTests`/`SyncClientPullTests`, factored
/// out to keep each test file focused and under this repo's file-length
/// convention.
enum SyncClientTestSupport {
    /// Builds an `AuthService` already holding a valid in-memory access
    /// token (`"access-1"`), via a one-time login against `apiClient`, so a
    /// test's first authorized call doesn't itself trigger an incidental
    /// refresh. Overwrites `apiClient.loginResult` — call this before
    /// configuring the push/pull/refresh results the test actually cares
    /// about.
    @MainActor
    static func makeAuthService(
        apiClient: MockAPIClient,
        store: LocalStoring,
        cursorStore: SyncCursorStoring = InMemorySyncCursorStore()
    ) async throws -> AuthService {
        let keychain = InMemoryKeychainStore()
        let service = AuthService(
            apiClient: apiClient,
            keychain: keychain,
            localStore: store,
            cursorStore: cursorStore,
            deviceInfoProvider: {
                DeviceInfo(platform: "ios", name: "Test", model: "Test", osVersion: "17.0", appVersion: "1.0")
            }
        )
        apiClient.loginResult = .success(makeAuthResponse(accessToken: "access-1"))
        try await service.login(email: "user@example.com", password: "password123")
        return service
    }

    static func makeAuthResponse(accessToken: String) -> AuthResponse {
        AuthResponse(
            accessToken: accessToken,
            refreshToken: "rt_1",
            tokenType: "Bearer",
            expiresIn: 900,
            user: AuthUser(id: "usr_1", email: "user@example.com", role: "user"),
            device: DeviceInfo(
                id: "dev_1",
                platform: "ios",
                name: "Test",
                model: "Test",
                osVersion: "17.0",
                appVersion: "1.0"
            )
        )
    }

    static func makeSyncClient(
        apiClient: MockAPIClient,
        store: LocalStoring,
        authService: AuthService,
        cursorStore: SyncCursorStoring = InMemorySyncCursorStore(),
        clock: Clock = TestClock(),
        sleeper: FakeSleeper = FakeSleeper(),
        maxRetryAttempts: Int = 3,
        pushBatchLimit: Int = 500
    ) -> SyncClient {
        SyncClient(
            apiClient: apiClient,
            authService: authService,
            store: store,
            cursorStore: cursorStore,
            deviceId: "device-1",
            backoff: ExponentialBackoff(baseDelay: 1, multiplier: 2, maxDelay: 10),
            sleeper: sleeper,
            clock: clock,
            maxRetryAttempts: maxRetryAttempts,
            pushBatchLimit: pushBatchLimit
        )
    }

    static func makeEvent(id: UUID = UUID()) -> ActivityEventRecord {
        ActivityEventRecord(
            eventId: id,
            deviceId: "device-1",
            startedAt: Date(timeIntervalSince1970: 1000),
            endedAt: Date(timeIntervalSince1970: 1060),
            appBundleId: "com.example.app",
            insertedAt: Date(timeIntervalSince1970: 1000)
        )
    }

    static func makeSession(
        id: UUID = UUID(),
        updatedAt: Date = Date(timeIntervalSince1970: 2000)
    ) -> FocusSessionRecord {
        FocusSessionRecord(
            id: id,
            deviceId: "device-1",
            kind: .focus,
            startedAt: Date(timeIntervalSince1970: 1000),
            status: .completed,
            createdAt: Date(timeIntervalSince1970: 1000),
            updatedAt: updatedAt
        )
    }
}
