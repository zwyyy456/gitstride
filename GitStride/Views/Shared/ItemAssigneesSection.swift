import SwiftUI

struct ItemAssigneesSection: View {
    let store: ProjectStore
    let item: ProjectItem
    @State private var localError: String?
    @State private var isSaving = false
    let projectID: String
    private var canEdit: Bool { store.canEditProject(id: projectID) }
    @State private var userQuery = ""
    @State private var userResults: [Assignee] = []
    @State private var isSearchingUsers = false
    @State private var hasSearchedUsers = false
    @State private var userSearchGeneration = 0
    @State private var showsAssigneePicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Assignees")
                    .foregroundStyle(.secondary)
                Spacer()
                if canEdit, item.contentType != .draftIssue {
                    Button("Add Assignee…", action: showAssigneePicker)
                    .buttonStyle(.borderless)
                    .disabled(isSaving)
                    .popover(isPresented: $showsAssigneePicker) {
                        assigneePicker(item)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                if item.assignees.isEmpty {
                    Text("No assignees").foregroundStyle(.secondary)
                } else {
                    ItemPropertyTokenLayout {
                        ForEach(item.assignees) { assignee in
                            ItemPropertyToken(
                                title: assignee.name ?? assignee.login,
                                removeLabel: String(localized: "Remove assignee") + ": " + assignee.login,
                                canRemove: canEdit,
                                remove: {
                                    guard !isSaving else { return }
                                    localError = nil
                                    isSaving = true
                                    Task { @MainActor in
                                        defer { isSaving = false }
                                        do {
                                            try await store.removeAssignee(
                                                from: item,
                                                in: projectID,
                                                user: assignee
                                            )
                                        } catch {
                                            report(error)
                                        }
                                    }
                                }
                            ) {
                                AsyncImage(url: URL(string: assignee.avatarUrl)) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    Circle().fill(.secondary.opacity(0.2))
                                }
                                .frame(width: 18, height: 18)
                                .clipShape(Circle())
                            }
                            .disabled(isSaving)
                        }
                    }
                }

                if isSaving { ProgressView().controlSize(.mini).accessibilityLabel("Saving field") }
                if let localError { Text(localError).font(.caption).foregroundStyle(.red) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func assigneePicker(_ item: ProjectItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Assignee")
                .font(.headline)

            HStack {
                TextField("Search GitHub users", text: $userQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { searchUsers() }
                Button("Search", systemImage: "magnifyingglass", action: searchUsers)
                    .labelStyle(.iconOnly)
                    .disabled(
                        userQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || isSearchingUsers
                    )
                    .help("Search GitHub Users")
            }

            if isSearchingUsers {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Searching GitHub users")
            } else if userResults.isEmpty {
                Text(
                    hasSearchedUsers
                        ? String(localized: "No matching users") : String(localized: "Enter a GitHub login or name.")
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(userResults) { user in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(user.name ?? user.login)
                                    if let name = user.name, name != user.login {
                                        Text("@\(user.login)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Button("Add") {
                                    addAssignee(user, to: item)
                                }
                                .disabled(isSaving || item.assignees.contains { $0.id == user.id })
                            }
                        }
                    }
                }
                .frame(maxHeight: 240)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let localError { Text(localError).font(.caption).foregroundStyle(.red).padding() }
            if isSaving { ProgressView().controlSize(.small).padding() }
        }
        .padding()
        .frame(width: 320)
    }

    private func searchUsers() {
        let query = userQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false, isSearchingUsers == false else { return }
        userSearchGeneration += 1
        let generation = userSearchGeneration
        isSearchingUsers = true
        hasSearchedUsers = true
        localError = nil
        Task {
            do {
                let results = try await store.searchUsers(query: query)
                guard generation == userSearchGeneration else { return }
                if query == userQuery.trimmingCharacters(in: .whitespacesAndNewlines) {
                    userResults = results
                }
            } catch {
                guard generation == userSearchGeneration else { return }
                report(error)
            }
            isSearchingUsers = false
        }
    }

    private func showAssigneePicker() {
        userQuery = ""
        userResults = []
        userSearchGeneration += 1
        isSearchingUsers = false
        hasSearchedUsers = false
        showsAssigneePicker = true
    }

    private func addAssignee(_ user: Assignee, to item: ProjectItem) {
        guard !isSaving else { return }
        localError = nil
        isSaving = true
        Task { @MainActor in
            defer { isSaving = false }
            do {
                try await store.addAssignee(
                    to: item,
                    in: projectID,
                    user: user
                )
                userResults.removeAll { $0.id == user.id }
            } catch {
                report(error)
            }
        }
    }

    private func report(_ error: Error) {
        guard (error is CancellationError) == false else { return }
        localError = error.localizedDescription
    }
}
