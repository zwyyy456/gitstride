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
        }
        .navigationTitle("GitHub")
    }
}

struct MobileSettingsView: View {
    @Bindable var model: GitStrideModel

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    MobileAccountView(model: model)
                } label: {
                    LabeledContent("GitHub Account", value: model.projectStore.currentUserLogin.map { "@" + $0 } ?? String(localized: "Not connected"))
                }
                NavigationLink {
                    MobileAutomationView(model: model)
                } label: {
                    LabeledContent("Automation", value: automationStatus)
                }
            }
            Section {
                NavigationLink {
                    MobileAboutView()
                } label: {
                    LabeledContent("About", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                }
            }
        }
        .navigationTitle("Settings")
    }

    private var automationStatus: String {
        let setup = model.automationSetup
        if setup.phase == .loadingConnection { return String(localized: "Loading…") }
        if setup.errorMessage != nil || setup.phase == .connectionLoadFailed {
            return String(localized: "Needs attention")
        }
        if setup.automations.isEmpty { return String(localized: "Not configured") }
        if setup.automations.contains(where: { !["ACTIVE", "CONTENT_VISIBILITY_UNVERIFIED"].contains($0.healthState) }) {
            return String(localized: "Needs attention")
        }
        return setup.automations.contains(where: \.enabled) ? String(localized: "Enabled") : String(localized: "Paused")
    }
}

private struct MobileAutomationView: View {
    @Bindable var model: GitStrideModel

    var body: some View {
        Form { AutomationSettingsView(setup: model.automationSetup) }
            .navigationTitle("Automation")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: Binding(get: { model.automationSetup.isPresentingSetup }, set: { _ in })) {
                AutomationSetupSheet(setup: model.automationSetup)
            }
            .task(id: model.automationSetup.setupSessionID) { await model.automationSetup.observeSetup() }
    }
}

private struct MobileAboutView: View {
    var body: some View {
        Form {
            LabeledContent("GitStride", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
            NavigationLink("License") {
                ScrollView {
                    Text(licenseText).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding()
                }.navigationTitle("License")
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var licenseText: String {
        guard let url = Bundle.main.url(forResource: "LICENSE", withExtension: nil) else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
}
