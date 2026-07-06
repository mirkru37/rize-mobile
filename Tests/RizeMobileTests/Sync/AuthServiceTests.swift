import XCTest
@testable import RizeMobile

/// Bundles a fresh `AuthService` with the test doubles it was built from, so
/// call sites can assert against whichever doubles their scenario needs
/// without `makeService` returning an oversized tuple (SwiftLint
/// `large_tuple`).
@MainActor
private struct AuthServiceTestHarness {
    let service: AuthService
    let apiClient: MockAPIClient
    let keychain: InMemoryKeychainStore
    let store: SpyLocalStore
}

@MainActor
final class AuthServiceTests: XCTestCase {
    private func makeService(
        apiClient: MockAPIClient = MockAPIClient(),
        keychain: InMemoryKeychainStore = InMemoryKeychainStore(),
        store: SpyLocalStore = SpyLocalStore(),
        cursorStore: InMemorySyncCursorStore = InMemorySyncCursorStore()
    ) -> AuthServiceTestHarness {
        let service = AuthService(
            apiClient: apiClient,
            keychain: keychain,
            localStore: store,
            cursorStore: cursorStore,
            deviceInfoProvider: {
                DeviceInfo(platform: "ios", name: "Test", model: "Test", osVersion: "17.0", appVersion: "1.0")
            }
        )
        return AuthServiceTestHarness(service: service, apiClient: apiClient, keychain: keychain, store: store)
    }

    private func makeAuthResponse(
        email: String = "user@example.com",
        accessToken: String = "access-1"
    ) -> AuthResponse {
        AuthResponse(
            accessToken: accessToken,
            refreshToken: "rt_1",
            tokenType: "Bearer",
            expiresIn: 900,
            user: AuthUser(id: "usr_1", email: email, role: "user"),
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

    // MARK: Login / register

    func testLoginAppliesTokensAndSetsSignedInState() async throws {
        let harness = makeService()
        harness.apiClient.loginResult = .success(makeAuthResponse(email: "a@b.com"))

        try await harness.service.login(email: "a@b.com", password: "password123")

        XCTAssertEqual(harness.service.state, .signedIn(email: "a@b.com"))
        XCTAssertEqual(harness.keychain.read(key: "com.rizeclone.mobile.refreshToken"), "rt_1")
        let token = try await harness.service.validAccessToken()
        XCTAssertEqual(token, "access-1")
    }

    func testRegisterAppliesTokensAndSetsSignedInState() async throws {
        let harness = makeService()
        harness.apiClient.registerResult = .success(makeAuthResponse(email: "new@user.com"))

        try await harness.service.register(email: "new@user.com", password: "password123")

        XCTAssertEqual(harness.service.state, .signedIn(email: "new@user.com"))
    }

    // MARK: Bootstrap

    func testBootstrapRestoresSignedInStateFromKeychain() {
        let keychain = InMemoryKeychainStore()
        keychain.write("rt_existing", key: "com.rizeclone.mobile.refreshToken")
        keychain.write("existing@user.com", key: "com.rizeclone.mobile.signedInEmail")
        let harness = makeService(keychain: keychain)

        harness.service.bootstrap()

        XCTAssertEqual(harness.service.state, .signedIn(email: "existing@user.com"))
    }

    func testBootstrapLeavesSignedOutWhenNoRefreshTokenIsPersisted() {
        let harness = makeService()

        harness.service.bootstrap()

        XCTAssertEqual(harness.service.state, .signedOut)
    }

    // MARK: Logout

    func testLogoutClearsAccessTokenKeychainAndWipesLocalData() async throws {
        let harness = makeService()
        harness.apiClient.loginResult = .success(makeAuthResponse())
        try await harness.service.login(email: "a@b.com", password: "password123")

        await harness.service.logout()

        XCTAssertEqual(harness.service.state, .signedOut)
        XCTAssertNil(harness.keychain.read(key: "com.rizeclone.mobile.refreshToken"))
        XCTAssertEqual(harness.store.wipeAllDataCallCount, 1)
        XCTAssertEqual(harness.apiClient.logoutCallCount, 1)
    }

    func testLogoutIsBestEffortEvenIfTheServerCallFails() async throws {
        let harness = makeService()
        harness.apiClient.loginResult = .success(makeAuthResponse())
        try await harness.service.login(email: "a@b.com", password: "password123")
        harness.apiClient.logoutResult = .failure(SyncStubError())

        await harness.service.logout()

        // Local sign-out must complete regardless of the network outcome.
        XCTAssertEqual(harness.service.state, .signedOut)
        XCTAssertNil(harness.keychain.read(key: "com.rizeclone.mobile.refreshToken"))
        XCTAssertEqual(harness.store.wipeAllDataCallCount, 1)
    }

    /// RIZ-46 H1: logout must reset the pull cursor alongside the local
    /// wipe, or the next pull resumes from a stale `server_seq` and silently
    /// drops every previously-synced row — see [[sync-protocol]] §Device
    /// Restore.
    func testLogoutResetsSyncCursor() async throws {
        let cursorStore = InMemorySyncCursorStore()
        cursorStore.saveCursor("cursor-123")
        let harness = makeService(cursorStore: cursorStore)
        harness.apiClient.loginResult = .success(makeAuthResponse())
        try await harness.service.login(email: "a@b.com", password: "password123")

        await harness.service.logout()

        XCTAssertNil(cursorStore.loadCursor())
    }

    /// The cursor reset must happen even when the best-effort server logout
    /// call fails — it lives in `clearLocalSession()`, the same code path as
    /// the local wipe, not gated on the network call succeeding.
    func testLogoutResetsSyncCursorEvenIfTheServerCallFails() async throws {
        let cursorStore = InMemorySyncCursorStore()
        cursorStore.saveCursor("cursor-456")
        let harness = makeService(cursorStore: cursorStore)
        harness.apiClient.loginResult = .success(makeAuthResponse())
        try await harness.service.login(email: "a@b.com", password: "password123")
        harness.apiClient.logoutResult = .failure(SyncStubError())

        await harness.service.logout()

        XCTAssertNil(cursorStore.loadCursor())
    }

    // MARK: Refresh

    func testValidAccessTokenRefreshesLazilyWhenNoneHeldInMemory() async throws {
        let keychain = InMemoryKeychainStore()
        keychain.write("rt_existing", key: "com.rizeclone.mobile.refreshToken")
        let harness = makeService(keychain: keychain)
        harness.apiClient.refreshResults = [.success(makeAuthResponse(accessToken: "fresh-token"))]
        harness.service.bootstrap()

        let token = try await harness.service.validAccessToken()

        XCTAssertEqual(token, "fresh-token")
        XCTAssertEqual(harness.apiClient.refreshCallCount, 1)
    }

    /// Concurrent callers landing on `refreshAccessToken()` while a refresh
    /// is already in flight must all observe the *same* refresh rather than
    /// each triggering their own `POST /v1/auth/refresh` call.
    func testRefreshAccessTokenIsSingleFlightForConcurrentCallers() async throws {
        let keychain = InMemoryKeychainStore()
        keychain.write("rt_existing", key: "com.rizeclone.mobile.refreshToken")
        let harness = makeService(keychain: keychain)
        harness.apiClient.refreshResults = [.success(makeAuthResponse(accessToken: "fresh-token"))]

        async let first = harness.service.refreshAccessToken()
        async let second = harness.service.refreshAccessToken()
        let (firstToken, secondToken) = try await (first, second)

        XCTAssertEqual(firstToken, "fresh-token")
        XCTAssertEqual(secondToken, "fresh-token")
        XCTAssertEqual(harness.apiClient.refreshCallCount, 1)
    }

    func testFailedRefreshWithUnauthorizedLogsOutAndWipesData() async {
        let keychain = InMemoryKeychainStore()
        keychain.write("rt_existing", key: "com.rizeclone.mobile.refreshToken")
        let harness = makeService(keychain: keychain)
        harness.apiClient.refreshResults = [.failure(APIClientError.unauthorized)]
        harness.service.bootstrap()

        await XCTAssertThrowsErrorAsync {
            try await harness.service.refreshAccessToken()
        }

        XCTAssertEqual(harness.service.state, .signedOut)
        XCTAssertNil(harness.keychain.read(key: "com.rizeclone.mobile.refreshToken"))
        XCTAssertEqual(harness.store.wipeAllDataCallCount, 1)
    }

    /// A transient/malformed-response failure must never sign the user out
    /// or wipe local data — only a definitive rejection of the refresh token
    /// itself does. See `AuthService.performRefresh`'s doc comment.
    func testFailedRefreshWithATransientErrorDoesNotLogOutOrWipeData() async {
        let keychain = InMemoryKeychainStore()
        keychain.write("rt_existing", key: "com.rizeclone.mobile.refreshToken")
        let harness = makeService(keychain: keychain)
        harness.apiClient.refreshResults = [.failure(APIClientError.invalidResponse)]
        harness.service.bootstrap()

        await XCTAssertThrowsErrorAsync {
            try await harness.service.refreshAccessToken()
        }

        // Still signed in — the refresh token itself was never rejected.
        XCTAssertEqual(harness.service.state, .signedIn(email: ""))
        XCTAssertNotNil(harness.keychain.read(key: "com.rizeclone.mobile.refreshToken"))
        XCTAssertEqual(harness.store.wipeAllDataCallCount, 0)
    }
}
