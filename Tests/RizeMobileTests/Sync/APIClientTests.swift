import XCTest
@testable import RizeMobile

/// Covers `APIClient` — the production `APIClientProtocol` implementation
/// that every other sync/auth test bypasses via `MockAPIClient` (RIZ-66).
/// Exercised against `StubHTTPTransport`, a canned-response fake of the
/// lower-level `HTTPTransport` seam, so these tests drive real request
/// building and response parsing without a network or `URLProtocol`.
final class APIClientTests: XCTestCase {
    private func makeConfig() throws -> BackendConfig {
        try BackendConfig(baseURL: XCTUnwrap(URL(string: "https://api.example.com")))
    }

    private func makeResponse(statusCode: Int) throws -> HTTPURLResponse {
        try XCTUnwrap(HTTPURLResponse(
            url: XCTUnwrap(URL(string: "https://api.example.com")),
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        ))
    }

    // MARK: Success round-trips

    func testRegisterSendsPOSTAndDecodesAuthResponse() async throws {
        let responseJSON = """
        {"access_token":"at","refresh_token":"rt","token_type":"Bearer","expires_in":900,
         "user":{"id":"u1","email":"a@b.com","role":"user"},
         "device":{"id":"d1","platform":"ios","name":"n","model":"m","os_version":"17","app_version":"1.0"}}
        """
        let transport = try StubHTTPTransport(result: .success((
            Data(responseJSON.utf8),
            makeResponse(statusCode: 200)
        )))
        let client = try APIClient(config: makeConfig(), transport: transport)
        let device = DeviceInfo(platform: "ios", name: "n", model: "m", osVersion: "17", appVersion: "1.0")

        let response = try await client.register(email: "a@b.com", password: "secret123", device: device)

        XCTAssertEqual(response.accessToken, "at")
        let request = try XCTUnwrap(transport.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/v1/auth/register")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testLogoutSendsAuthorizationHeaderAndNoDecoding() async throws {
        let transport = try StubHTTPTransport(result: .success((Data(), makeResponse(statusCode: 204))))
        let client = try APIClient(config: makeConfig(), transport: transport)

        try await client.logout(accessToken: "token-1", refreshToken: "rt-1")

        let request = try XCTUnwrap(transport.lastRequest)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-1")
        XCTAssertEqual(request.url?.path, "/v1/auth/logout")
    }

    func testPullChangesBuildsQueryStringWithCursorAndLimit() async throws {
        let responseJSON = """
        {"changes":{},"next_cursor":null,"has_more":false}
        """
        let transport = try StubHTTPTransport(result: .success((
            Data(responseJSON.utf8),
            makeResponse(statusCode: 200)
        )))
        let client = try APIClient(config: makeConfig(), transport: transport)

        _ = try await client.pullChanges(accessToken: "token-1", cursor: "cursor-a", limit: 50)

        let request = try XCTUnwrap(transport.lastRequest)
        XCTAssertEqual(request.httpMethod, "GET")
        let components = try URLComponents(url: XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
        let queryItems = try XCTUnwrap(components?.queryItems)
        XCTAssertTrue(queryItems.contains(URLQueryItem(name: "limit", value: "50")))
        XCTAssertTrue(queryItems.contains(URLQueryItem(name: "cursor", value: "cursor-a")))
    }

    func testPullChangesOmitsCursorQueryItemWhenNil() async throws {
        let responseJSON = """
        {"changes":{},"next_cursor":null,"has_more":false}
        """
        let transport = try StubHTTPTransport(result: .success((
            Data(responseJSON.utf8),
            makeResponse(statusCode: 200)
        )))
        let client = try APIClient(config: makeConfig(), transport: transport)

        _ = try await client.pullChanges(accessToken: "token-1", cursor: nil, limit: 50)

        let request = try XCTUnwrap(transport.lastRequest)
        let components = try URLComponents(url: XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
        let queryItems = try XCTUnwrap(components?.queryItems)
        XCTAssertFalse(queryItems.contains { $0.name == "cursor" })
    }

    // MARK: throwIfNotSuccessful branches

    func testUnauthorizedStatusThrowsUnauthorizedRegardlessOfBody() async throws {
        let transport = try StubHTTPTransport(result: .success((Data(), makeResponse(statusCode: 401))))
        let client = try APIClient(config: makeConfig(), transport: transport)

        await XCTAssertThrowsErrorAsync({
            try await client.pullChanges(accessToken: "t", cursor: nil, limit: 10)
        }) { error in
            XCTAssertEqual(error as? APIClientError, .unauthorized)
        }
    }

    func testNonSuccessStatusWithDecodableProblemBodyThrowsProblem() async throws {
        let problemJSON = """
        {"type":"about:blank","title":"Bad Request","status":400,"detail":"email is required"}
        """
        let transport = try StubHTTPTransport(result: .success((Data(problemJSON.utf8), makeResponse(statusCode: 400))))
        let client = try APIClient(config: makeConfig(), transport: transport)

        await XCTAssertThrowsErrorAsync({
            try await client.pullChanges(accessToken: "t", cursor: nil, limit: 10)
        }) { error in
            guard case let .problem(detail) = error as? APIClientError else {
                return XCTFail("expected .problem, got \(error)")
            }
            XCTAssertEqual(detail.status, 400)
            XCTAssertEqual(detail.detail, "email is required")
        }
    }

    func testNonSuccessStatusWithUndecodableBodyThrowsInvalidResponse() async throws {
        let transport = try StubHTTPTransport(result: .success((Data("not json".utf8), makeResponse(statusCode: 500))))
        let client = try APIClient(config: makeConfig(), transport: transport)

        await XCTAssertThrowsErrorAsync({
            try await client.pullChanges(accessToken: "t", cursor: nil, limit: 10)
        }) { error in
            XCTAssertEqual(error as? APIClientError, .invalidResponse)
        }
    }

    func testTransportFailurePropagates() async throws {
        let transport = StubHTTPTransport(result: .failure(SyncStubError()))
        let client = try APIClient(config: makeConfig(), transport: transport)

        await XCTAssertThrowsErrorAsync({
            try await client.pullChanges(accessToken: "t", cursor: nil, limit: 10)
        }) { error in
            XCTAssertTrue(error is SyncStubError)
        }
    }
}

/// A canned-response `HTTPTransport` fake — records the last request it was
/// asked to send and returns a fixed result, letting `APIClientTests` drive
/// `APIClient`'s request-building and response-parsing without a network.
private final class StubHTTPTransport: HTTPTransport, @unchecked Sendable {
    private let result: Result<(Data, HTTPURLResponse), Error>
    private(set) var lastRequest: URLRequest?

    init(result: Result<(Data, HTTPURLResponse), Error>) {
        self.result = result
    }

    func send(_ request: URLRequest) async throws -> (data: Data, response: HTTPURLResponse) {
        lastRequest = request
        let (data, response) = try result.get()
        return (data, response)
    }
}

/// A small `async`-aware `XCTAssertThrowsError` shim, since the stdlib macro
/// doesn't support `await`ing the expression directly. Takes an explicit
/// closure (rather than `@autoclosure`) so its own internal `await` can't be
/// hoisted by SwiftFormat into the call site, which would otherwise strip it
/// from this file's `async` expressions and fail to compile.
private func XCTAssertThrowsErrorAsync(
    _ operation: () async throws -> some Any,
    _ errorHandler: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await operation()
        XCTFail("expected an error to be thrown", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
