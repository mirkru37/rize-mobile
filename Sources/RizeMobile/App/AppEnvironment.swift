import Foundation

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
    let authService: AuthService
    let syncClient: SyncClient
    let authViewModel: AuthViewModel

    private init(
        database: AppDatabase,
        deviceId: String,
        backendConfig: BackendConfig,
        keychain: KeychainStoring
    ) {
        self.database = database
        let store = GRDBLocalStore(database: database, deviceId: deviceId)
        self.store = store

        let apiClient = APIClient(config: backendConfig)
        let authService = AuthService(
            apiClient: apiClient,
            keychain: keychain,
            localStore: store,
            deviceInfoProvider: { DeviceInfoProvider.current(deviceId: deviceId) }
        )
        authService.bootstrap()
        self.authService = authService

        let syncClient = SyncClient(
            apiClient: apiClient,
            authService: authService,
            store: store,
            cursorStore: UserDefaultsSyncCursorStore(),
            deviceId: deviceId
        )
        self.syncClient = syncClient
        authViewModel = AuthViewModel(authService: authService, syncClient: syncClient)

        sessionEngine = SessionEngine(
            store: store,
            clockStateStore: UserDefaultsSessionClockStore(),
            // RIZ-46: trigger a sync pass once a session completes, in
            // addition to the app-foreground trigger, so a just-finished
            // session doesn't wait for the next relaunch/foreground to push.
            onSessionCompleted: { Task { await syncClient.syncNow() } }
        )
        dashboardViewModel = DashboardViewModel(
            store: store,
            observer: GRDBTodayDataObserver(database: database)
        )
        historyViewModel = SessionHistoryViewModel(store: store)
    }

    /// The production environment: an on-disk database under the app's
    /// Application Support directory.
    ///
    /// Failing to open/migrate the on-disk store is surfaced as a `.failure`
    /// rather than crashing: there is no sync/offline-cache fallback
    /// strategy yet, so continuing in-memory would silently drop the
    /// durability guarantee the rest of the app assumes without any
    /// user-visible warning — instead the caller (`RootView`) renders a
    /// full-screen error state so the user at least sees what happened
    /// rather than the app terminating outright.
    static func live() -> Result<AppEnvironment, Error> {
        Result {
            let database = try AppDatabase.onDisk(path: onDiskDatabasePath())
            return AppEnvironment(
                database: database,
                deviceId: DeviceIdProvider.currentDeviceId(),
                backendConfig: BackendConfigProvider.resolve(),
                keychain: KeychainStore()
            )
        }
    }

    /// An isolated, ephemeral environment for SwiftUI previews and tests, so
    /// they never share or persist state across runs or touch the on-disk
    /// database or the real Keychain.
    static func inMemory() -> AppEnvironment {
        do {
            let database = try AppDatabase.inMemory()
            return AppEnvironment(
                database: database,
                deviceId: "preview-device",
                backendConfig: BackendConfig(baseURL: BackendConfigProvider.developmentFallback),
                keychain: InMemoryKeychainStore()
            )
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
}
