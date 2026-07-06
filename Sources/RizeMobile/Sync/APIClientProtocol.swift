import Foundation

/// The backend HTTP API surface `AuthService`/`SyncClient` depend on, per
/// [[api-reference]] §Auth and §Sync and [[sync-protocol]].
///
/// This is the seam `SyncClient` and `AuthService` are built against so both
/// are testable with a mock conforming to this protocol, without a real
/// network or `URLSession` — the "mock transport" referred to by this
/// ticket's test requirements.
public protocol APIClientProtocol: Sendable {
    func register(email: String, password: String, device: DeviceInfo) async throws -> AuthResponse
    func login(email: String, password: String, device: DeviceInfo) async throws -> AuthResponse
    func refresh(refreshToken: String, device: DeviceInfo?) async throws -> AuthResponse
    func logout(accessToken: String, refreshToken: String) async throws

    func pushEvents(
        accessToken: String,
        deviceId: String,
        items: [SyncPushItem]
    ) async throws -> SyncPushResponse

    func pullChanges(
        accessToken: String,
        cursor: String?,
        limit: Int
    ) async throws -> SyncPullResponse
}
