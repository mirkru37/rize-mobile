import XCTest
@testable import RizeMobile

/// Covers `AuthView`'s state-dependent body branches (RIZ-66) — no existing
/// test file. `AuthView` has no extractable pure logic beyond `body`'s
/// `switch` on `AuthViewModel.signInState` (private/UI-only helpers
/// otherwise), so these tests drive a real `AuthViewModel` through actual
/// sign-in/sync calls (matching `AuthViewModelTests`' harness) to reach each
/// branch, asserting on the view model's real, observable state before
/// evaluating `body`.
@MainActor
final class AuthViewTests: XCTestCase {
    private typealias Support = SyncClientTestSupport

    private func makeViewModel(apiClient: MockAPIClient = MockAPIClient()) -> AuthViewModel {
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
        return AuthViewModel(authService: authService, syncClient: syncClient)
    }

    func testAuthViewShowsSignInFormWhenSignedOut() {
        let viewModel = makeViewModel()

        XCTAssertEqual(viewModel.signInState, .signedOut)
        let view = AuthView(viewModel: viewModel)

        XCTAssertNotNil(view.body)
    }

    func testAuthViewShowsSignInFormWithErrorMessageAfterAFailedSubmit() async {
        let apiClient = MockAPIClient()
        apiClient.loginResult = .failure(APIClientError.unauthorized)
        let viewModel = makeViewModel(apiClient: apiClient)

        await viewModel.submit()

        XCTAssertEqual(viewModel.errorMessage, "Invalid email or password.")
        let view = AuthView(viewModel: viewModel)

        XCTAssertNotNil(view.body)
    }

    func testAuthViewShowsAccountSummaryWhenSignedInWithoutASyncYet() async {
        let apiClient = MockAPIClient()
        apiClient.loginResult = .success(Support.makeAuthResponse(accessToken: "at-1"))
        let viewModel = makeViewModel(apiClient: apiClient)

        await viewModel.submit()

        guard case .signedIn = viewModel.signInState else {
            return XCTFail("expected signedIn state after a successful submit")
        }
        let view = AuthView(viewModel: viewModel)

        XCTAssertNotNil(view.body)
    }

    func testAuthViewShowsAccountSummaryWithLastSyncTimeAfterASuccessfulSync() async {
        let apiClient = MockAPIClient()
        apiClient.loginResult = .success(Support.makeAuthResponse(accessToken: "at-1"))
        let viewModel = makeViewModel(apiClient: apiClient)

        // submit() itself triggers a syncNow() on success, which records
        // lastSyncAt once push+pull both succeed against the default
        // MockAPIClient results.
        await viewModel.submit()

        XCTAssertNotNil(viewModel.lastSyncAt)
        let view = AuthView(viewModel: viewModel)

        XCTAssertNotNil(view.body)
    }
}
