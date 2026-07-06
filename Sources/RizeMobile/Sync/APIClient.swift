import Foundation

/// Production `APIClientProtocol`: builds requests against
/// `BackendConfig.baseURL` per [[api-reference]]'s route table, and decodes
/// responses per its JSON conventions (snake_case wire fields, ISO 8601
/// dates, RFC 7807-style error bodies).
public struct APIClient: APIClientProtocol {
    private let config: BackendConfig
    private let transport: HTTPTransport

    public init(config: BackendConfig, transport: HTTPTransport = URLSessionHTTPTransport()) {
        self.config = config
        self.transport = transport
    }

    public func register(email: String, password: String, device: DeviceInfo) async throws -> AuthResponse {
        try await send(
            path: "/v1/auth/register",
            body: RegisterOrLoginRequest(email: email, password: password, device: device)
        )
    }

    public func login(email: String, password: String, device: DeviceInfo) async throws -> AuthResponse {
        try await send(
            path: "/v1/auth/login",
            body: RegisterOrLoginRequest(email: email, password: password, device: device)
        )
    }

    public func refresh(refreshToken: String, device: DeviceInfo?) async throws -> AuthResponse {
        try await send(
            path: "/v1/auth/refresh",
            body: RefreshRequest(refreshToken: refreshToken, device: device)
        )
    }

    public func logout(accessToken: String, refreshToken: String) async throws {
        let request = try makeRequest(
            path: "/v1/auth/logout",
            method: "POST",
            body: LogoutRequest(refreshToken: refreshToken),
            accessToken: accessToken
        )
        let (data, response) = try await transport.send(request)
        try Self.throwIfNotSuccessful(data: data, response: response)
    }

    public func pushEvents(
        accessToken: String,
        deviceId: String,
        items: [SyncPushItem]
    ) async throws -> SyncPushResponse {
        try await send(
            path: "/v1/sync/events",
            body: SyncPushRequest(deviceId: deviceId, items: items),
            accessToken: accessToken
        )
    }

    public func pullChanges(
        accessToken: String,
        cursor: String?,
        limit: Int
    ) async throws -> SyncPullResponse {
        let changesURL = config.baseURL.appendingPathComponent("/v1/sync/changes")
        var components = URLComponents(url: changesURL, resolvingAgainstBaseURL: false)
        var queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw APIClientError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await transport.send(request)
        try Self.throwIfNotSuccessful(data: data, response: response)
        return try Self.makeDecoder().decode(SyncPullResponse.self, from: data)
    }

    // MARK: Request building

    private func send<Response: Decodable>(
        path: String,
        body: some Encodable,
        accessToken: String? = nil
    ) async throws -> Response {
        let request = try makeRequest(path: path, method: "POST", body: body, accessToken: accessToken)
        let (data, response) = try await transport.send(request)
        try Self.throwIfNotSuccessful(data: data, response: response)
        return try Self.makeDecoder().decode(Response.self, from: data)
    }

    private func makeRequest(
        path: String,
        method: String,
        body: some Encodable,
        accessToken: String?
    ) throws -> URLRequest {
        var request = URLRequest(url: config.baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try Self.makeEncoder().encode(body)
        return request
    }

    private static func throwIfNotSuccessful(data: Data, response: HTTPURLResponse) throws {
        guard !(200 ..< 300).contains(response.statusCode) else { return }

        if response.statusCode == 401 {
            throw APIClientError.unauthorized
        }
        if let problem = try? makeDecoder().decode(ProblemDetail.self, from: data) {
            throw APIClientError.problem(problem)
        }
        throw APIClientError.invalidResponse
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
