import SwiftUI

/// Top-level Tier C screen: shows the start-session form when idle or the
/// running/paused session when active, with a toolbar link to today's
/// session history.
///
/// Composition root note: this view takes its `SessionEngine` and
/// `SessionHistoryViewModel` as parameters rather than constructing a
/// `GRDBLocalStore` itself — wiring a concrete `LocalStoring`/device id into
/// the app shell is left to the app's composition root, which has not yet
/// been built (RIZ-43 introduced the store without wiring it into
/// `RizeMobileApp` either).
struct SessionsView: View {
    var engine: SessionEngine
    var historyViewModel: SessionHistoryViewModel

    var body: some View {
        NavigationStack {
            activeContent
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        NavigationLink("History") {
                            SessionHistoryView(viewModel: historyViewModel)
                        }
                    }
                }
        }
        .task {
            try? await engine.recoverRunningSession()
            try? await historyViewModel.refresh()
        }
    }

    @ViewBuilder
    private var activeContent: some View {
        switch engine.state {
        case .idle:
            StartSessionView(engine: engine)
        case let .running(snapshot):
            RunningSessionView(engine: engine, snapshot: snapshot, isPaused: false)
        case let .paused(snapshot):
            RunningSessionView(engine: engine, snapshot: snapshot, isPaused: true)
        }
    }
}
