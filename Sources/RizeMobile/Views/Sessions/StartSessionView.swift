import SwiftUI

/// Lets the user start a manual timer or focus session (Tier C), per
/// [[architecture-mobile.md]] §Tier C.
///
/// Per §6 (UX Honesty Requirement) this screen's copy must not imply the app
/// automatically tracks all iOS activity — a manual session is exact only
/// because the user explicitly starts and stops it, unlike desktop's
/// continuous observation.
struct StartSessionView: View {
    var engine: SessionEngine

    @State private var kind: FocusSessionKind = .focus
    @State private var note: String = ""
    @State private var plannedMinutesText: String = ""
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Picker("Type", selection: $kind) {
                    ForEach(FocusSessionKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                TextField("Label (optional)", text: $note)
                plannedDurationField
            } footer: {
                Text(
                    "Manual sessions only track the time you explicitly start and stop " +
                        "— this app does not automatically track all iOS activity."
                )
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }

            Button("Start Session") {
                start()
            }
        }
        .navigationTitle("New Session")
    }

    private var plannedDurationField: some View {
        TextField("Planned minutes (optional)", text: $plannedMinutesText)
        #if os(iOS)
            .keyboardType(.numberPad)
        #endif
    }

    private func start() {
        let plannedDurationS = Int(plannedMinutesText).map { $0 * 60 }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let capturedKind = kind

        Task {
            do {
                try await engine.start(
                    kind: capturedKind,
                    plannedDurationS: plannedDurationS,
                    note: trimmedNote.isEmpty ? nil : trimmedNote
                )
                errorMessage = nil
            } catch {
                errorMessage = "Couldn't start the session. Please try again."
            }
        }
    }
}
