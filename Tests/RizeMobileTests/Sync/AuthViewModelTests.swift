import XCTest
@testable import RizeMobile

/// Covers `AuthViewModel` (RIZ-66) — no existing test file. Builds a real
/// `AuthService`/`SyncClient` pair against `MockAPIClient`/`SpyLocalStore`,
/// matching the pattern `AuthServiceTests`/`SyncClientPushTests` already use.
@MainActor
final class AuthViewModelTests: XCTestCase {
    private typealias Support = SyncClientTestSupport

    private struct Harness {
        let viewModel: AuthViewModel
        let apiClient: MockAPIClient
        let syncClient: SyncClient
    }

    private func makeHarness(apiClient: MockAPIClient = MockAPIClient()) -> Harness {
        let store = SpyLocalStore()
        let authService = AuthService(
            apiClient: apiClient,
            keychain: InMemoryKeychainStore(),
            localStore: store,
            cursorStore: InMemorySyncCursorStore(),
            deviceInfoProvider: {
                DeviceInfo(platform: "ios", name: "Test", model: "Test", osVersion: "17.0", appVersion: "1.0")
            }
        )
        let syncClient = Support.makeSyncClient(apiClient: apiClient, store: store, authService: authService)
        let viewModel = AuthViewModel(authService: authService, syncClient: syncClient)
        return Harness(viewModel: viewModel, apiClient: apiClient, syncClient: syncClient)
    }

    // MARK: submit() — sign in

    func testSubmitSignInSuccessSignsInAndClearsPassword() async {
        let harness = makeHarness()
        harness.apiClient.loginResult = .success(Support.makeAuthResponse(accessToken: "at-1"))
        harness.viewModel.mode = .signIn
        harness.viewModel.email = "user@example.com"
        harness.viewModel.password = "secret123"

        await harness.viewModel.submit()

        XCTAssertEqual(harness.viewModel.password, "")
        XCTAssertNil(harness.viewModel.errorMessage)
        XCTAssertEqual(harness.viewModel.signInState, .signedIn(email: "user@example.com"))
        XCTAssertFalse(harness.viewModel.isSubmitting)
    }

    // MARK: submit() — sign up

    func testSubmitSignUpSuccessSignsInAndTriggersSync() async {
        let harness = makeHarness()
        harness.apiClient.registerResult = .success(Support.makeAuthResponse(accessToken: "at-1"))
        harness.viewModel.mode = .signUp
        harness.viewModel.email = "new@example.com"
        harness.viewModel.password = "secret123"

        await harness.viewModel.submit()

        XCTAssertEqual(harness.viewModel.password, "")
        XCTAssertEqual(harness.apiClient.pullCallCount, 1, "syncNow() should run a pull as part of the sync cycle")
    }

    // MARK: submit() — error mapping

    func testSubmitMapsProblemErrorToItsDetailMessageAndKeepsPassword() async {
        let harness = makeHarness()
        let problem = ProblemDetail(type: "about:blank", title: "Bad Request", status: 400, detail: "Email taken")
        harness.apiClient.loginResult = .failure(APIClientError.problem(problem))
        harness.viewModel.password = "secret123"

        await harness.viewModel.submit()

        XCTAssertEqual(harness.viewModel.errorMessage, "Email taken")
        XCTAssertEqual(harness.viewModel.password, "secret123", "password is only cleared on success")
        XCTAssertEqual(harness.viewModel.signInState, .signedOut)
    }

    func testSubmitMapsUnauthorizedErrorToAFixedMessage() async {
        let harness = makeHarness()
        harness.apiClient.loginResult = .failure(APIClientError.unauthorized)

        await harness.viewModel.submit()

        XCTAssertEqual(harness.viewModel.errorMessage, "Invalid email or password.")
    }

    func testSubmitMapsUnknownErrorToAGenericMessage() async {
        let harness = makeHarness()
        harness.apiClient.loginResult = .failure(SyncStubError())

        await harness.viewModel.submit()

        XCTAssertEqual(harness.viewModel.errorMessage, "Something went wrong. Please try again.")
    }

    // MARK: Re-entrancy guard

    func testSubmitIsANoOpWhileAPreviousSubmitIsInFlight() async {
        let harness = makeHarness()
        harness.apiClient.loginResult = .success(Support.makeAuthResponse(accessToken: "at-1"))

        async let first: Void = harness.viewModel.submit()
        async let second: Void = harness.viewModel.submit()
        _ = await (first, second)

        // A second overlapping submit while the first is in flight must not
        // issue its own login call — exactly one login should have happened.
        XCTAssertEqual(harness.apiClient.loginCallCount, 1)
    }

    // MARK: signOut / syncNow passthrough

    func testSignOutClearsSignedInState() async {
        let harness = makeHarness()
        harness.apiClient.loginResult = .success(Support.makeAuthResponse(accessToken: "at-1"))
        harness.viewModel.password = "secret123"
        await harness.viewModel.submit()

        await harness.viewModel.signOut()

        XCTAssertEqual(harness.viewModel.signInState, .signedOut)
    }

    func testSyncNowDelegatesToSyncClient() async {
        let harness = makeHarness()
        // A sync cycle's pull step needs a valid access token, which
        // requires having signed in first — otherwise `SyncClient.syncNow()`
        // fails at the auth step before ever reaching the pull, and
        // `syncNow()` swallows that failure by design (see `SyncClient`).
        harness.apiClient.loginResult = .success(Support.makeAuthResponse(accessToken: "at-1"))
        await harness.viewModel.submit()
        let pullCallCountAfterSubmit = harness.apiClient.pullCallCount

        await harness.viewModel.syncNow()

        XCTAssertEqual(harness.apiClient.pullCallCount, pullCallCountAfterSubmit + 1)
    }

    // MARK: Mode.submitTitle

    func testModeSubmitTitles() {
        XCTAssertEqual(AuthViewModel.Mode.signIn.submitTitle, "Sign In")
        XCTAssertEqual(AuthViewModel.Mode.signUp.submitTitle, "Sign Up")
    }
}
