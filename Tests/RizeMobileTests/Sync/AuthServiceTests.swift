import XCTest
@testable import RizeMobile

@MainActor
final class AuthServiceTests: XCTestCase {
    private func makeService(
        apiClient: MockAPIClient = MockAPIClient(),
        keychain: InMemoryKeychainStore = InMemoryKeychainStore(),
        store: SpyLocalStore = SpyLocalStore()
    ) -> (AuthService, MockAPIClient, InMemoryKeychainStore, SpyLocalStore) {
        let service = AuthService(
            apiClient: apiClient,
            keychain: keychain,
            localStore: store,
            deviceInfoProvider: {
                DeviceInfo(platform: "ios", name: "Test", model: "Test", osVersion: "17.0", appVersion: "1.0")
            }
        )
        return (service, apiClient, keychain, store)
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
        let (service, apiClient, keychain, _) = makeService()
        apiClient.loginResult = .success(makeAuthResponse(email: "a@b.com"))

        try await service.login(email: "a@b.com", password: "password123")

        XCTAssertEqual(service.state, .signedIn(email: "a@b.com"))
        XCTAssertEqual(keychain.read(key: "com.rizeclone.mobile.refreshToken"), "rt_1")
        let token = try await service.validAccessToken()
        XCTAssertEqual(token, "access-1")
    }

    func testRegisterAppliesTokensAndSetsSignedInState() async throws {
        let (service, apiClient, _, _) = makeService()
        apiClient.registerResult = .success(makeAuthResponse(email: "new@user.com"))

        try await service.register(email: "new@user.com", password: "password123")

        XCTAssertEqual(service.state, .signedIn(email: "new@user.com"))
    }

    // MARK: Bootstrap

    func testBootstrapRestoresSignedInStateFromKeychain() {
        let keychain = InMemoryKeychainStore()
        keychain.write("rt_existing", key: "com.rizeclone.mobile.refreshToken")
        keychain.write("existing@user.com", key: "com.rizeclone.mobile.signedInEmail")
        let (service, _, _, _) = makeService(keychain: keychain)

        service.bootstrap()

        XCTAssertEqual(service.state, .signedIn(email: "existing@user.com"))
    }

    func testBootstrapLeavesSignedOutWhenNoRefreshTokenIsPersisted() {
        let (service, _, _, _) = makeService()

        service.bootstrap()

        XCTAssertEqual(service.state, .signedOut)
    }

    // MARK: Logout

    func testLogoutClearsAccessTokenKeychainAndWipesLocalData() async throws {
        let (service, apiClient, keychain, store) = makeService()
        apiClient.loginResult = .success(makeAuthResponse())
        try await service.login(email: "a@b.com", password: "password123")

        await service.logout()

        XCTAssertEqual(service.state, .signedOut)
        XCTAssertNil(keychain.read(key: "com.rizeclone.mobile.refreshToken"))
        XCTAssertEqual(store.wipeAllDataCallCount, 1)
        XCTAssertEqual(apiClient.logoutCallCount, 1)
    }

    func testLogoutIsBestEffortEvenIfTheServerCallFails() async throws {
        let (service, apiClient, keychain, store) = makeService()
        apiClient.loginResult = .success(makeAuthResponse())
        try await service.login(email: "a@b.com", password: "password123")
        apiClient.logoutResult = .failure(SyncStubError())

        await service.logout()

        // Local sign-out must complete regardless of the network outcome.
        XCTAssertEqual(service.state, .signedOut)
        XCTAssertNil(keychain.read(key: "com.rizeclone.mobile.refreshToken"))
        XCTAssertEqual(store.wipeAllDataCallCount, 1)
    }

    // MARK: Refresh

    func testValidAccessTokenRefreshesLazilyWhenNoneHeldInMemory() async throws {
        let keychain = InMemoryKeychainStore()
        keychain.write("rt_existing", key: "com.rizeclone.mobile.refreshToken")
        let (service, apiClient, _, _) = makeService(keychain: keychain)
        apiClient.refreshResults = [.success(makeAuthResponse(accessToken: "fresh-token"))]
        service.bootstrap()

        let token = try await service.validAccessToken()

        XCTAssertEqual(token, "fresh-token")
        XCTAssertEqual(apiClient.refreshCallCount, 1)
    }

    /// Concurrent callers landing on `refreshAccessToken()` while a refresh
    /// is already in flight must all observe the *same* refresh rather than
    /// each triggering their own `POST /v1/auth/refresh` call.
    func testRefreshAccessTokenIsSingleFlightForConcurrentCallers() async throws {
        let keychain = InMemoryKeychainStore()
        keychain.write("rt_existing", key: "com.rizeclone.mobile.refreshToken")
        let (service, apiClient, _, _) = makeService(keychain: keychain)
        apiClient.refreshResults = [.success(makeAuthResponse(accessToken: "fresh-token"))]

        async let first = service.refreshAccessToken()
        async let second = service.refreshAccessToken()
        let (firstToken, secondToken) = try await (first, second)

        XCTAssertEqual(firstToken, "fresh-token")
        XCTAssertEqual(secondToken, "fresh-token")
        XCTAssertEqual(apiClient.refreshCallCount, 1)
    }

    func testFailedRefreshWithUnauthorizedLogsOutAndWipesData() async {
        let keychain = InMemoryKeychainStore()
        keychain.write("rt_existing", key: "com.rizeclone.mobile.refreshToken")
        let (service, apiClient, _, store) = makeService(keychain: keychain)
        apiClient.refreshResults = [.failure(APIClientError.unauthorized)]
        service.bootstrap()

        await XCTAssertThrowsErrorAsync {
            try await service.refreshAccessToken()
        }

        XCTAssertEqual(service.state, .signedOut)
        XCTAssertNil(keychain.read(key: "com.rizeclone.mobile.refreshToken"))
        XCTAssertEqual(store.wipeAllDataCallCount, 1)
    }

    /// A transient/malformed-response failure must never sign the user out
    /// or wipe local data — only a definitive rejection of the refresh token
    /// itself does. See `AuthService.performRefresh`'s doc comment.
    func testFailedRefreshWithATransientErrorDoesNotLogOutOrWipeData() async {
        let keychain = InMemoryKeychainStore()
        keychain.write("rt_existing", key: "com.rizeclone.mobile.refreshToken")
        let (service, apiClient, _, store) = makeService(keychain: keychain)
        apiClient.refreshResults = [.failure(APIClientError.invalidResponse)]
        service.bootstrap()

        await XCTAssertThrowsErrorAsync {
            try await service.refreshAccessToken()
        }

        // Still signed in — the refresh token itself was never rejected.
        XCTAssertEqual(service.state, .signedIn(email: ""))
        XCTAssertNotNil(keychain.read(key: "com.rizeclone.mobile.refreshToken"))
        XCTAssertEqual(store.wipeAllDataCallCount, 0)
    }
}
