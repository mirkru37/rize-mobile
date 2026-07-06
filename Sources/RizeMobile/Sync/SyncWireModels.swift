import Foundation

// MARK: - Auth wire types (documentation/api-reference.md §Auth)

/// The `device` object required on `register`/`login`, optional on `refresh`.
/// `id` is omitted by the client when registering a brand-new device and
/// populated by the server in the echoed response, per the worked examples in
/// [[api-reference]].
public struct DeviceInfo: Codable, Equatable, Sendable {
    public var id: String?
    public var platform: String
    public var name: String
    public var model: String
    public var osVersion: String
    public var appVersion: String

    public init(
        id: String? = nil,
        platform: String,
        name: String,
        model: String,
        osVersion: String,
        appVersion: String
    ) {
        self.id = id
        self.platform = platform
        self.name = name
        self.model = model
        self.osVersion = osVersion
        self.appVersion = appVersion
    }
}

public struct AuthUser: Codable, Equatable, Sendable {
    public var id: String
    public var email: String
    public var role: String

    public init(id: String, email: String, role: String) {
        self.id = id
        self.email = email
        self.role = role
    }
}

/// The shared response shape of `register`/`login`/`refresh`, per
/// [[api-reference]]'s §Auth worked examples.
public struct AuthResponse: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var tokenType: String
    public var expiresIn: Int
    public var user: AuthUser
    public var device: DeviceInfo

    public init(
        accessToken: String,
        refreshToken: String,
        tokenType: String,
        expiresIn: Int,
        user: AuthUser,
        device: DeviceInfo
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenType = tokenType
        self.expiresIn = expiresIn
        self.user = user
        self.device = device
    }
}

struct RegisterOrLoginRequest: Codable {
    var email: String
    var password: String
    var device: DeviceInfo
}

struct RefreshRequest: Codable {
    var refreshToken: String
    var device: DeviceInfo?
}

struct LogoutRequest: Codable {
    var refreshToken: String
}

/// The RFC 7807-style error body every non-2xx response carries, per
/// [[api-reference]] §Conventions.
public struct ProblemDetail: Codable, Equatable, Error, Sendable {
    public var type: String
    public var title: String
    public var status: Int
    public var detail: String

    public init(type: String, title: String, status: Int, detail: String) {
        self.type = type
        self.title = title
        self.status = status
        self.detail = detail
    }
}

/// Errors `APIClient` surfaces that don't correspond to a decoded
/// `ProblemDetail` body.
public enum APIClientError: Error, Equatable, Sendable {
    /// The response wasn't an `HTTPURLResponse`, or its body couldn't be
    /// decoded as either the expected success shape or a `ProblemDetail`.
    case invalidResponse
    /// A non-2xx response whose body carried a decodable `ProblemDetail`.
    case problem(ProblemDetail)
    /// A `401 Unauthorized` response to an authenticated request — the only
    /// status `AuthService`'s single-flight refresh-and-retry reacts to.
    case unauthorized
}

// MARK: - Sync wire types (documentation/sync-protocol.md)

/// A single item in a `POST /v1/sync/events` push batch. Mobile only ever
/// pushes the two entity types its local store owns (`activity_event`,
/// `focus_session`); the `data` payload is one of `ActivityEventPushData` /
/// `FocusSessionPushData` depending on `entityType`.
public struct SyncPushItem: Encodable, Sendable {
    public enum Payload: Sendable {
        case activityEvent(ActivityEventPushData)
        case focusSession(FocusSessionPushData)
    }

    public var payload: Payload

    public init(_ payload: Payload) {
        self.payload = payload
    }

    private enum CodingKeys: String, CodingKey {
        case entityType
        case data
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch payload {
        case let .activityEvent(data):
            try container.encode("activity_event", forKey: .entityType)
            try container.encode(data, forKey: .data)
        case let .focusSession(data):
            try container.encode("focus_session", forKey: .entityType)
            try container.encode(data, forKey: .data)
        }
    }
}

/// Wire payload for an `activity_event` push item, per [[sync-protocol]]
/// §Push. `windowTitle` is always omitted by mobile (Tier B events never
/// carry one).
public struct ActivityEventPushData: Codable, Sendable {
    public var eventId: String
    public var startedAt: Date
    public var endedAt: Date
    public var appBundleId: String?
    public var categoryId: String?
    public var projectId: String?
    public var precision: String
    public var deleted: Bool

    public init(from record: ActivityEventRecord) {
        eventId = record.eventId.uuidString
        startedAt = record.startedAt
        endedAt = record.endedAt
        appBundleId = record.appBundleId
        categoryId = record.categoryId?.uuidString
        projectId = record.projectId?.uuidString
        precision = ActivityEventRecord.precision
        deleted = record.deleted
    }
}

/// Wire payload for a `focus_session` push item, per [[sync-protocol]]
/// §Push.
///
/// Assumption: [[sync-protocol]]'s worked JSON example for `focus_session`
/// shows only `id`/`updated_at`/`started_at`/`ended_at`/`project_id`/`label`/
/// `deleted` — omitting `kind`/`status`, which the server needs to create a
/// row that matches [[database-schema]]'s `focus_sessions` columns, and using
/// `label` where [[database-schema]] names the column `note`. Since the
/// example is illustrative rather than an exhaustive field list, this payload
/// follows [[database-schema]]'s column names/set (the schema being the
/// canonical contract for what the server persists) rather than the
/// example's abbreviated field list verbatim.
public struct FocusSessionPushData: Codable, Sendable {
    public var id: String
    public var updatedAt: Date
    public var startedAt: Date
    public var endedAt: Date?
    public var projectId: String?
    public var kind: String
    public var plannedDurationS: Int?
    public var status: String
    public var note: String?
    public var deleted: Bool

    public init(from record: FocusSessionRecord) {
        id = record.id.uuidString
        updatedAt = record.updatedAt
        startedAt = record.startedAt
        endedAt = record.endedAt
        projectId = record.projectId?.uuidString
        kind = record.kind.rawValue
        plannedDurationS = record.plannedDurationS
        status = record.status.rawValue
        note = record.note
        deleted = record.deletedAt != nil
    }
}

struct SyncPushRequest: Encodable {
    var deviceId: String
    var items: [SyncPushItem]
}

/// One entry of `POST /v1/sync/events`'s per-item response, per
/// [[sync-protocol]] §Push.
public struct SyncPushResult: Decodable, Equatable, Sendable {
    public enum Status: String, Decodable, Sendable {
        case applied
        case duplicate
        case invalid
    }

    public var index: Int
    public var entityType: String
    public var eventId: String?
    public var id: String?
    public var status: Status
    public var serverSeq: Int?
}

public struct SyncPushResponse: Decodable, Equatable, Sendable {
    public var results: [SyncPushResult]
}

/// One entity type's page of upserts/tombstones inside a `GET
/// /v1/sync/changes` response, per [[sync-protocol]] §Pull. Mobile only
/// applies `activity_events` and `focus_sessions`; other entity types
/// (`projects`, `tags`, `user_app_settings`, `aggregates`) are decoded and
/// currently ignored, since no local table exists yet for them.
public struct SyncPullEventChange: Decodable, Sendable {
    public var eventId: String
    public var startedAt: Date
    public var endedAt: Date
    public var appBundleId: String?
    public var category: String?
    public var precision: String?
    public var serverSeq: Int
}

public struct SyncPullEventTombstone: Decodable, Sendable {
    public var eventId: String
    public var serverSeq: Int
}

public struct SyncPullSessionChange: Decodable, Sendable {
    public var id: String
    public var updatedAt: Date
    public var startedAt: Date
    public var endedAt: Date?
    public var projectId: String?
    public var kind: String?
    public var plannedDurationS: Int?
    public var status: String?
    public var note: String?
    public var serverSeq: Int
}

public struct SyncPullSessionTombstone: Decodable, Sendable {
    public var id: String
    public var serverSeq: Int
}

public struct SyncEntityChangePage<Upsert: Decodable & Sendable, Tombstone: Decodable & Sendable>: Decodable, Sendable {
    public var upserts: [Upsert]
    public var tombstones: [Tombstone]
}

public struct SyncChanges: Decodable, Sendable {
    public var activityEvents: SyncEntityChangePage<SyncPullEventChange, SyncPullEventTombstone>?
    public var focusSessions: SyncEntityChangePage<SyncPullSessionChange, SyncPullSessionTombstone>?
}

public struct SyncPullResponse: Decodable, Sendable {
    public var changes: SyncChanges
    public var nextCursor: String?
    public var hasMore: Bool
}
