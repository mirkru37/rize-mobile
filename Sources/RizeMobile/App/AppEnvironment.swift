import Foundation
#if canImport(UIKit)
    import UIKit
#endif

/// The app's composition root: builds the on-device local store once, at
/// launch, and wires the view models/engine layered on top of it.
///
/// `RizeMobileApp` (production) uses `AppEnvironment.live()`, which points at
/// the on-disk database. SwiftUI previews and tests must never touch that
/// on-disk file, so they use `AppEnvironment.inMemory()` instead — both
/// factories share the same wiring via the private designated initializer.
@MainActor
struct AppEnvironment {
    let database: AppDatabase
    let store: LocalStoring
    let sessionEngine: SessionEngine
    let dashboardViewModel: DashboardViewModel
    let historyViewModel: SessionHistoryViewModel

    private init(database: AppDatabase, deviceId: String) {
        self.database = database
        let store = GRDBLocalStore(database: database, deviceId: deviceId)
        self.store = store
        sessionEngine = SessionEngine(store: store, clockStateStore: UserDefaultsSessionClockStore())
        dashboardViewModel = DashboardViewModel(
            store: store,
            observer: GRDBTodayDataObserver(database: database)
        )
        historyViewModel = SessionHistoryViewModel(store: store)
    }

    /// The production environment: an on-disk database under the app's
    /// Application Support directory.
    ///
    /// Failing to open/migrate the on-disk store is treated as fatal rather
    /// than silently falling back to an in-memory database: there is no
    /// sync/offline-cache fallback strategy yet, so continuing in-memory
    /// would silently drop the durability guarantee the rest of the app
    /// assumes without any user-visible warning.
    static func live() -> AppEnvironment {
        do {
            let database = try AppDatabase.onDisk(path: onDiskDatabasePath())
            return AppEnvironment(database: database, deviceId: currentDeviceId())
        } catch {
            fatalError("Failed to open the on-disk local store: \(error)")
        }
    }

    /// An isolated, ephemeral environment for SwiftUI previews and tests, so
    /// they never share or persist state across runs or touch the on-disk
    /// database.
    static func inMemory() -> AppEnvironment {
        do {
            let database = try AppDatabase.inMemory()
            return AppEnvironment(database: database, deviceId: "preview-device")
        } catch {
            fatalError("Failed to open the in-memory local store: \(error)")
        }
    }

    private static func onDiskDatabasePath() -> String {
        let searchDirectory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
        let baseDirectory = searchDirectory ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        return baseDirectory.appendingPathComponent("rize-mobile.sqlite").path
    }

    private static func currentDeviceId() -> String {
        #if canImport(UIKit)
            UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        #else
            UUID().uuidString
        #endif
    }
}
