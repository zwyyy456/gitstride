import SwiftUI

struct MobileAccountView: View {
    @Bindable var model: GitStrideModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section("Account") {
                if let account = model.projectStore.currentAccount, !model.isConnecting {
                    LabeledContent("GitHub", value: "@\(account.login)")
                    Button("Disconnect GitStride", role: .destructive) {
                        Task { await model.disconnectGitHub() }
                    }
                } else if let progress = model.connectionProgress {
                    if let code = model.deviceAuthorization {
                        LabeledContent("Device code") {
                            Text(code.userCode).font(.title3.monospaced().bold()).textSelection(.enabled)
                        }
                        Button("Copy Code and Open GitHub") {
                            UIPasteboard.general.string = code.userCode
                            openURL(code.verificationURL)
                        }
                    }
                    ProgressView {
                        switch progress {
                        case .connecting: Text("Connecting…")
                        case .authorizing(.waitingForAuthorization): Text("Waiting for authorization…")
                        case .authorizing(.retrying): Text("GitHub request timed out. Retrying…")
                        case .authorizing(.verifyingAccount): Text("Verifying GitHub account…")
                        case .loadingProjects: Text("Loading projects…")
                        case .disconnecting: Text("Disconnecting…")
                        }
                    }
                    if progress != .disconnecting {
                        Button("Cancel") { model.cancelGitHubLogin() }
                    }
                } else if model.projectStore.isLoading {
                    ProgressView("Checking GitHub connection…")
                } else {
                    Button("Log In to GitHub…") { model.connectGitHub(using: .oauth) }
                    Text("Connect your GitHub account to view and edit your Projects.")
                        .foregroundStyle(.secondary)
                }
            }
            if let error = model.authenticationError ?? model.projectStore.error?.localizedDescription {
                Section { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            }
            Section {
                Text("Login credentials are stored in this device’s Keychain.")
                Text("Requests access to Projects, organization membership, and read/write access to repository code, including private repositories.")
            }
            .foregroundStyle(.secondary)
        }
        .navigationTitle("GitHub")
    }
}
