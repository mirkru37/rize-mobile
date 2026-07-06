import Foundation
import GRDB

/// Owns the GRDB connection to the on-device local store and applies
/// migrations at initialization. See `LocalStoring`/`GRDBLocalStore` for the
/// higher-level session/event API built on top of this.
public final class AppDatabase: Sendable {
    let dbWriter: DatabaseWriter

    public init(dbWriter: DatabaseWriter) throws {
        self.dbWriter = dbWriter
        try AppDatabaseMigrator.makeMigrator().migrate(dbWriter)
    }

    /// An isolated, ephemeral database — used by tests and previews so
    /// runs never share or persist state across each other.
    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(dbWriter: DatabaseQueue())
    }

    /// The on-device, file-backed database used in production.
    ///
    /// Per `rize-mobile/CLAUDE.md` and [[security]], the local store must use
    /// `completeUntilFirstUserAuthentication` file protection rather than the
    /// default.
    public static func onDisk(path: String) throws -> AppDatabase {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        let queue = try DatabaseQueue(path: path, configuration: configuration)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: path
        )
        return try AppDatabase(dbWriter: queue)
    }
}
