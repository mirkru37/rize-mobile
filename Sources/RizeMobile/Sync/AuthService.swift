import Foundation
import Observation

/// Errors surfaced by `AuthService` itself (as opposed to `APIClientError`,
/// which surfaces transport/protocol failures).
public enum AuthError: Error, Equatable, Sendable {
    /// No refresh token is available (never signed in, or already signed
    /// out) — an authorized call was attempted anyway.
    case notAuthenticated
}

/// Owns the client's session: the in-memory access token, the Keychain
/// refresh token, and the signed-in/out UI state the auth screen displays.
///
/// `@MainActor`/`@Observable` per this repo's convention (see
/// `SessionEngine`, `DashboardViewModel`) — the auth screen binds directly to
/// `state`/`lastSyncAt`.
@MainActor
@Observable
public final class AuthService {
    public enum SignInState: Equatable, Sendable {
        case signedOut
        case signedIn(email: String)
    }

    private static let refreshTokenKey = "com.rizeclone.mobile.refreshToken"
    private static let signedInEmailKey = "com.rizeclone.mobile.signedInEmail"

    /// Current sign-in state, restored at launch by `bootstrap()` from
    /// whether a refresh token is present in the Keychain — restoring state
    /// never itself makes a network call; the first authorized request lazily
    /// exchanges the refresh token for a fresh access token.
    public private(set) var state: SignInState = .signedOut

    /// Wall-clock time of the last sync cycle that completed successfully
    /// (push + pull both succeeded), surfaced by the account/sync settings
    /// screen. `nil` until the first successful cycle this launch — this is
    /// in-memory only (not persisted), so it accurately reads "no successful
    /// sync yet this session" after a relaunch rather than showing a stale
    /// time, per the UX honesty requirement in [[architecture-mobile.md]] §6.
    public private(set) var lastSyncAt: Date?

    /// The access token, held in memory only per [[security]] — never
    /// written to Keychain, `UserDefaults`, or disk.
    private var accessToken: String?

    private let apiClient: APIClientProtocol
    private let keychain: KeychainStoring
    private let localStore: LocalStoring
    private let cursorStore: SyncCursorStoring
    private let deviceInfoProvider: @Sendable () -> DeviceInfo
    private var refreshTask: Task<String, Error>?

    public init(
        apiClient: APIClientProtocol,
        keychain: KeychainStoring,
        localStore: LocalStoring,
        cursorStore: SyncCursorStoring,
        deviceInfoProvider: @escaping @Sendable () -> DeviceInfo
    ) {
        self.apiClient = apiClient
        self.keychain = keychain
        self.localStore = localStore
        self.cursorStore = cursorStore
        self.deviceInfoProvider = deviceInfoProvider
    }

    /// Restores `state` from the Keychain. Call once, early in the app's
    /// lifecycle (mirrors `SessionEngine.recoverRunningSession()`'s role for
    /// session state).
    public func bootstrap() {
        guard keychain.read(key: Self.refreshTokenKey) != nil else {
            state = .signedOut
            return
        }
        state = .signedIn(email: keychain.read(key: Self.signedInEmailKey) ?? "")
    }

    public func register(email: String, password: String) async throws {
        let response = try await apiClient.register(
            email: email,
            password: password,
            device: deviceInfoProvider()
        )
        applyAuthResponse(response)
    }

    public func login(email: String, password: String) async throws {
        let response = try await apiClient.login(
            email: email,
            password: password,
            device: deviceInfoProvider()
        )
        applyAuthResponse(response)
    }

    /// Ends the session. Revoking the refresh token server-side is
    /// best-effort: a network failure here must never block the local
    /// sign-out the user asked for, so failures are swallowed after the
    /// local session is cleared regardless of whether the server call
    /// succeeded.
    ///
    /// Per the RIZ-43 M4 orchestrator decision: clears the in-memory access
    /// token and the Keychain refresh token, and wipes the local database
    /// (this app is single-user-per-install, so a signed-out install has no
    /// reason to retain a previous account's tracked activity). The device
    /// id is **not** cleared — it identifies this install, not this account,
    /// and is reused as `device.id` on the next sign-in so the server
    /// recognizes the same physical device rather than registering a new one
    /// every logout/login cycle.
    public func logout() async {
        let refreshToken = keychain.read(key: Self.refreshTokenKey)
        if let accessToken, let refreshToken {
            _ = try? await apiClient.logout(accessToken: accessToken, refreshToken: refreshToken)
        }
        await clearLocalSession()
    }

    /// Returns a usable access token, lazily refreshing if none is held in
    /// memory yet (e.g. right after a cold launch that restored a
    /// signed-in state from the Keychain).
    public func validAccessToken() async throws -> String {
        if let accessToken { return accessToken }
        return try await refreshAccessToken()
    }

    /// Refreshes the access token, rotating the refresh token in the same
    /// call per [[security]].
    ///
    /// **Single-flight**: if a refresh is already in flight, this returns
    /// that same `Task`'s result instead of starting a second
    /// `POST /v1/auth/refresh` call — the check-and-store of `refreshTask`
    /// happens synchronously (no `await` in between), so two calls landing
    /// on this `@MainActor`-isolated method back-to-back can't both pass the
    /// `nil` check before either sets `refreshTask`.
    @discardableResult
    public func refreshAccessToken() async throws -> String {
        if let refreshTask {
            return try await refreshTask.value
        }
        let task = Task { try await self.performRefresh() }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    func recordSyncCompleted(at date: Date) {
        lastSyncAt = date
    }

    private func performRefresh() async throws -> String {
        guard let refreshToken = keychain.read(key: Self.refreshTokenKey) else {
            await clearLocalSession()
            throw AuthError.notAuthenticated
        }

        do {
            let response = try await apiClient.refresh(refreshToken: refreshToken, device: deviceInfoProvider())
            applyAuthResponse(response)
            return response.accessToken
        } catch let error as APIClientError {
            // Only a definitive rejection of the refresh token itself (401 /
            // an RFC 7807 problem body, e.g. `invalid-refresh-token` or
            // `refresh-token-reuse-detected` per [[api-reference]]) means
            // this session can never be renewed, so only those cases log out
            // cleanly. A malformed/undecodable response is treated as
            // transient rather than a hard sign-out, so a flaky backend
            // response can never itself wipe local data — see [[sync-protocol]]
            // §Flow's "never lose local data on any failure path" alongside
            // this method's own "logs out on failed refresh" requirement.
            if case .unauthorized = error {
                await clearLocalSession()
            } else if case .problem = error {
                await clearLocalSession()
            }
            throw error
        }
    }

    private func applyAuthResponse(_ response: AuthResponse) {
        accessToken = response.accessToken
        keychain.write(response.refreshToken, key: Self.refreshTokenKey)
        keychain.write(response.user.email, key: Self.signedInEmailKey)
        state = .signedIn(email: response.user.email)
    }

    private func clearLocalSession() async {
        accessToken = nil
        keychain.delete(key: Self.refreshTokenKey)
        keychain.delete(key: Self.signedInEmailKey)
        state = .signedOut
        lastSyncAt = nil
        // Reset the pull cursor in the same code path as the wipe below —
        // per [[sync-protocol]] §Device Restore, a wiped local store must
        // always be paired with a cleared cursor so the next pull is a full
        // re-pull from the server rather than resuming from a stale
        // `server_seq`, which would otherwise silently drop every row that
        // was already synced before this logout.
        cursorStore.saveCursor(nil)
        // Best-effort: a failure here leaves stale local rows behind rather
        // than crashing the sign-out flow, which must always complete.
        try? await localStore.wipeAllData()
    }
}
