import XCTest
@testable import RizeMobile

/// Covers the `SyncWireModels` Codable contracts not already exercised
/// incidentally by `SyncClientPushTests`/`SyncClientPullTests` (RIZ-66):
/// `SyncPushItem`'s hand-written `encode(to:)`, `ActivityEventPushData`/
/// `FocusSessionPushData`'s `init(from:)` record mapping, `ProblemDetail`
/// decoding, and `SyncPullResponse`/`SyncChanges` decoding with absent pages.
final class SyncWireModelsTests: XCTestCase {
    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    // MARK: SyncPushItem.encode(to:)

    func testSyncPushItemEncodesActivityEventWithEntityTypeTag() throws {
        let record = SyncClientTestSupport.makeEvent()
        let item = SyncPushItem(.activityEvent(ActivityEventPushData(from: record)))

        let json = try encodeToDictionary(item)

        XCTAssertEqual(json["entity_type"] as? String, "activity_event")
        XCTAssertNotNil(json["data"])
    }

    func testSyncPushItemEncodesFocusSessionWithEntityTypeTag() throws {
        let record = SyncClientTestSupport.makeSession()
        let item = SyncPushItem(.focusSession(FocusSessionPushData(from: record)))

        let json = try encodeToDictionary(item)

        XCTAssertEqual(json["entity_type"] as? String, "focus_session")
        XCTAssertNotNil(json["data"])
    }

    private func encodeToDictionary(_ item: SyncPushItem) throws -> [String: Any] {
        let data = try makeEncoder().encode(item)
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }

    // MARK: ActivityEventPushData.init(from:)

    func testActivityEventPushDataMapsRecordFields() {
        let eventId = UUID()
        let record = ActivityEventRecord(
            eventId: eventId,
            deviceId: "device-1",
            startedAt: Date(timeIntervalSince1970: 1000),
            endedAt: Date(timeIntervalSince1970: 1060),
            appBundleId: "com.example.app",
            deleted: true,
            insertedAt: Date(timeIntervalSince1970: 1000)
        )

        let payload = ActivityEventPushData(from: record)

        XCTAssertEqual(payload.eventId, eventId.uuidString)
        XCTAssertEqual(payload.appBundleId, "com.example.app")
        XCTAssertEqual(payload.precision, ActivityEventRecord.precision)
        XCTAssertTrue(payload.deleted)
    }

    // MARK: FocusSessionPushData.init(from:)

    func testFocusSessionPushDataMarksDeletedWhenDeletedAtIsSet() {
        let record = FocusSessionRecord(
            id: UUID(),
            deviceId: "device-1",
            kind: .meeting,
            startedAt: Date(timeIntervalSince1970: 1000),
            status: .abandoned,
            createdAt: Date(timeIntervalSince1970: 1000),
            updatedAt: Date(timeIntervalSince1970: 2000),
            deletedAt: Date(timeIntervalSince1970: 2500)
        )

        let payload = FocusSessionPushData(from: record)

        XCTAssertTrue(payload.deleted)
        XCTAssertEqual(payload.kind, "meeting")
        XCTAssertEqual(payload.status, "abandoned")
    }

    func testFocusSessionPushDataNotDeletedWhenDeletedAtIsNil() {
        let record = SyncClientTestSupport.makeSession()

        let payload = FocusSessionPushData(from: record)

        XCTAssertFalse(payload.deleted)
    }

    // MARK: ProblemDetail

    func testProblemDetailDecodesFromSnakeCaseJSON() throws {
        let json = """
        {"type":"about:blank","title":"Unauthorized","status":401,"detail":"Invalid credentials"}
        """
        let problem = try makeDecoder().decode(ProblemDetail.self, from: Data(json.utf8))

        XCTAssertEqual(problem.status, 401)
        XCTAssertEqual(problem.detail, "Invalid credentials")
    }

    // MARK: SyncPullResponse / SyncChanges

    func testSyncPullResponseDecodesWithBothChangePagesAbsent() throws {
        let json = """
        {"changes":{},"next_cursor":null,"has_more":false}
        """
        let response = try makeDecoder().decode(SyncPullResponse.self, from: Data(json.utf8))

        XCTAssertNil(response.changes.activityEvents)
        XCTAssertNil(response.changes.focusSessions)
        XCTAssertNil(response.nextCursor)
        XCTAssertFalse(response.hasMore)
    }

    func testSyncPullResponseDecodesWithBothChangePagesPresent() throws {
        let json = """
        {
          "changes": {
            "activity_events": {
              "upserts": [{
                "event_id": "\(UUID().uuidString)",
                "started_at": "2024-01-01T00:00:00Z",
                "ended_at": "2024-01-01T00:01:00Z",
                "app_bundle_id": "com.example.app",
                "precision": "approximate",
                "server_seq": 1
              }],
              "tombstones": []
            },
            "focus_sessions": {
              "upserts": [],
              "tombstones": [{"id": "\(UUID().uuidString)", "server_seq": 2}]
            }
          },
          "next_cursor": "cursor-1",
          "has_more": true
        }
        """
        let response = try makeDecoder().decode(SyncPullResponse.self, from: Data(json.utf8))

        XCTAssertEqual(response.changes.activityEvents?.upserts.count, 1)
        XCTAssertEqual(response.changes.focusSessions?.tombstones.count, 1)
        XCTAssertEqual(response.nextCursor, "cursor-1")
        XCTAssertTrue(response.hasMore)
    }
}
