import SwiftUI

/// Shows the active manual timer / focus session: elapsed time, pause/resume,
/// and stop. Elapsed time is computed from `SessionEngine.elapsed(now:)`
/// against a `TimelineView` tick rather than a `Timer`, so there is no timer
/// object to invalidate/leak and the elapsed value is always a pure function
/// of "now".
struct RunningSessionView: View {
    var engine: SessionEngine
    var snapshot: SessionSnapshot
    var isPaused: Bool

    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            Text(snapshot.kind.displayName)
                .font(.headline)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(Self.format(engine.elapsed(now: context.date)))
                    .font(.system(size: 48, weight: .semibold, design: .monospaced))
            }

            if isPaused {
                Text("Paused")
                    .foregroundStyle(.secondary)
            }

            if let note = snapshot.note, !note.isEmpty {
                Text(note)
                    .foregroundStyle(.secondary)
            }

            controls

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }

            Text("Exact — timed manually, not inferred from device activity.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle("Session")
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Button(isPaused ? "Resume" : "Pause") {
                togglePause()
            }
            Button("Stop", role: .destructive) {
                stop()
            }
        }
    }

    private func togglePause() {
        do {
            if isPaused {
                try engine.resume()
            } else {
                try engine.pause()
            }
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't update the session. Please try again."
        }
    }

    private func stop() {
        Task {
            do {
                _ = try await engine.stop(completed: true)
                errorMessage = nil
            } catch {
                errorMessage = "Couldn't stop the session. Please try again."
            }
        }
    }

    private static func format(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
