import Foundation
import Observation

/// Drives the minimal auth screen: email/password sign-in and sign-up,
/// surfacing `AuthService`'s signed-in state and last-sync time, plus a
/// manual "sync now" action. Depends only on `AuthService` and `SyncClient`
/// (both already protocol-free-of-UIKit types), per this repo's MVVM
/// convention.
@MainActor
@Observable
public final class AuthViewModel {
    public enum Mode: Equatable {
        case signIn
        case signUp

        var submitTitle: String {
            switch self {
            case .signIn: "Sign In"
            case .signUp: "Sign Up"
            }
        }
    }

    public var mode: Mode = .signIn
    public var email: String = ""
    public var password: String = ""
    public private(set) var isSubmitting = false
    public private(set) var errorMessage: String?

    private let authService: AuthService
    private let syncClient: SyncClient

    public init(authService: AuthService, syncClient: SyncClient) {
        self.authService = authService
        self.syncClient = syncClient
    }

    public var signInState: AuthService.SignInState {
        authService.state
    }

    public var lastSyncAt: Date? {
        authService.lastSyncAt
    }

    /// Submits the sign-in/sign-up form. A no-op (per the app's UX honesty
    /// convention: no double-submission, no fake progress) while a previous
    /// submission is already in flight.
    public func submit() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            switch mode {
            case .signIn:
                try await authService.login(email: email, password: password)
            case .signUp:
                try await authService.register(email: email, password: password)
            }
            password = ""
            await syncClient.syncNow()
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    public func signOut() async {
        await authService.logout()
    }

    public func syncNow() async {
        await syncClient.syncNow()
    }

    private static func userFacingMessage(for error: Error) -> String {
        switch error {
        case let APIClientError.problem(problem):
            problem.detail
        case APIClientError.unauthorized:
            "Invalid email or password."
        default:
            "Something went wrong. Please try again."
        }
    }
}
