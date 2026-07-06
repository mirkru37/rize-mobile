import Foundation

/// The lowest-level networking seam: sends a fully-built `URLRequest` and
/// returns its raw response. `APIClient` is the only production consumer;
/// every other sync/auth component depends on `APIClientProtocol`, not this.
///
/// Kept as its own protocol (rather than folding `URLSession` calls directly
/// into `APIClient`) so a test can exercise `APIClient`'s request-building
/// and response-parsing against canned HTTP responses, without a real
/// network or a mock at the higher `APIClientProtocol` level.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (data: Data, response: HTTPURLResponse)
}

/// `URLSession`-backed production `HTTPTransport`.
public struct URLSessionHTTPTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (data: Data, response: HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }
        return (data, httpResponse)
    }
}
