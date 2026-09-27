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
                            Text(code.userCode).font(.title3.monospaced().bold()).textSelection(
                                .enabled)
                        }
                        Button("Copy Code and Open GitHub") {
                            UIPasteboard.general.string = code.userCode
                            openURL(code.verificationURL)
                        }
                    }
                    ProgressView {
                        switch progress {
                        case .connecting: Text("Connecting…")
                        case .authorizing(.waitingForAuthorization):
                            Text("Waiting for authorization…")
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
            if let error = model.authenticationError
                ?? model.projectStore.error?.localizedDescription
            {
                Section { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            }
            Section {
                Text("Login credentials are stored in this device’s Keychain.")
                Text(
                    "Requests access to Projects, organization membership, and read/write access to repository code, including private repositories."
                )
            }
            .foregroundStyle(.secondary)
            AutomationSettingsView(setup: model.automationSetup)
            Section("About") {
                LabeledContent(
                    "GitStride",
                    value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
                        as? String
                        ?? "")
                NavigationLink("License") {
                    ScrollView {
                        Text(licenseText).textSelection(.enabled).frame(
                            maxWidth: .infinity, alignment: .leading
                        ).padding()
                    }.navigationTitle("License")
                }
            }
        }
        .sheet(
            isPresented: Binding(get: { model.automationSetup.isPresentingSetup }, set: { _ in })
        ) {
            AutomationSetupSheet(setup: model.automationSetup)
        }
        .task(id: model.automationSetup.setupSessionID) {
            await model.automationSetup.observeSetup()
        }
        .navigationTitle("GitHub")
    }
    private var licenseText: String {
        guard let url = Bundle.main.url(forResource: "LICENSE", withExtension: nil) else {
            return ""
        }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

}
