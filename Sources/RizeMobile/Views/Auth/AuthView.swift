import SwiftUI

/// The minimal auth / account screen: an email + password sign-in/sign-up
/// form when signed out, or the signed-in account's email, last-sync time,
/// and sign-out/sync-now controls when signed in.
///
/// Reachable from the root as its own tab (`AppTab.account`) rather than a
/// modal gate, since local tracking (dashboard/sessions) works fully offline
/// per this app's offline-first local store — being signed out only means
/// sync is paused, not that the rest of the app is unusable.
struct AuthView: View {
    var viewModel: AuthViewModel

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.signInState {
                case .signedOut:
                    signInForm
                case let .signedIn(email):
                    accountSummary(email: email)
                }
            }
            .navigationTitle("Account")
        }
    }

    private var signInForm: some View {
        Form {
            Picker("Mode", selection: Binding(get: { viewModel.mode }, set: { viewModel.mode = $0 })) {
                Text("Sign In").tag(AuthViewModel.Mode.signIn)
                Text("Sign Up").tag(AuthViewModel.Mode.signUp)
            }
            .pickerStyle(.segmented)

            Section {
                TextField("Email", text: Binding(get: { viewModel.email }, set: { viewModel.email = $0 }))
                #if os(iOS)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                #endif
                SecureField("Password", text: Binding(get: { viewModel.password }, set: { viewModel.password = $0 }))
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }

            Button(viewModel.mode.submitTitle) {
                Task { await viewModel.submit() }
            }
            // Disabled while submitting so the request can never be sent
            // twice for one tap — no fake progress bar, just a disabled
            // control, per this app's UX honesty convention.
            .disabled(viewModel.isSubmitting || viewModel.email.isEmpty || viewModel.password.isEmpty)
        }
    }

    private func accountSummary(email: String) -> some View {
        Form {
            Section("Signed in") {
                Text(email)
            }
            Section("Sync") {
                Text(lastSyncDescription)
                Button("Sync Now") {
                    Task { await viewModel.syncNow() }
                }
            }
            Section {
                Button("Sign Out", role: .destructive) {
                    Task { await viewModel.signOut() }
                }
            }
        }
    }

    /// Accurate, honest sync-status copy: never implies a sync happened
    /// (or is happening) unless it actually did, per
    /// [[architecture-mobile.md]] §6.
    private var lastSyncDescription: String {
        guard let lastSyncAt = viewModel.lastSyncAt else {
            return "Not synced yet this session."
        }
        return "Last synced \(lastSyncAt.formatted(date: .abbreviated, time: .shortened))."
    }
}
