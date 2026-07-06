import SwiftUI

/// The app's entry point. Builds the composition root once via
/// `AppEnvironment.live()` (the on-disk local store) and hands it to
/// `RootView`, which hosts the dashboard as the initial screen alongside the
/// Tier C sessions screen — or a full-screen error state if the on-disk
/// store failed to open.
@main
struct RizeMobileApp: App {
    private let environmentResult = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            RootView(environmentResult: environmentResult)
        }
    }
}
