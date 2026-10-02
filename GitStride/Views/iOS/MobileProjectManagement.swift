import SwiftUI

struct MobileProjectManagement: View {
    let model: GitStrideModel
    var project: Project?
    var creationOwner: ProjectOwner?
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var repositoryID: String?
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var confirmingDelete = false
    private var store: ProjectStore { model.projectStore }
    private var owner: ProjectOwner? { project?.owner ?? creationOwner }
    private var repositories: [ProjectRepository] {
        owner.map { store.repositoryListState(ownerID: $0.id).repositories } ?? []
    }

    var body: some View {
        Group {
            if project == nil { NavigationStack { form } }
            else { form }
        }
    }

    private var form: some View {
        Form {
            if project == nil { TextField("Project name", text: $title) }
            if let owner { LabeledContent("Owner", value: owner.login) }
            Picker("Repository", selection: $repositoryID) {
                Text("None").tag(String?.none)
                ForEach(repositories) { Text($0.nameWithOwner).tag(Optional($0.id)) }
            }
            if let owner {
                switch store.repositoryListState(ownerID: owner.id) {
                case .loading: ProgressView()
                case .failed(let message):
                    Text(message).foregroundStyle(.red)
                    Button("Retry") { Task { await store.loadRepositories(owner: owner) } }
                default: EmptyView()
                }
            }
            if let project {
                Button("Link Repository") {
                    guard let repository = repositories.first(where: { $0.id == repositoryID })
                    else {
                        return
                    }
                    perform { try await store.linkRepository(repository, to: project.id) }
                }
                .disabled(repositoryID == nil)
                Button("Delete Project", role: .destructive) { confirmingDelete = true }
            }
            if isWorking { ProgressView() }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }
        .disabled(isWorking)
        .navigationTitle(
            project == nil
                ? String(localized: "New Project") : String(localized: "Manage Project")
        )
        .toolbar {
            if project == nil {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) {
                if project == nil {
                    Button("Create") {
                        guard let owner else { return }
                        perform {
                            try await store.createProject(
                                owner: owner,
                                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                repository: repositories.first { $0.id == repositoryID })
                        }
                    }
                    .disabled(
                        owner == nil
                            || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || isWorking)
                }
            }
        }
        .confirmationDialog("Delete Project?", isPresented: $confirmingDelete) {
            Button("Delete Project", role: .destructive) {
                if let project { perform { try await model.deleteProject(project) } }
            }
        } message: {
            Text("This deletes the project on GitHub. Issues and pull requests are kept.")
        }
        .task { if let owner { await store.loadRepositories(owner: owner) } }
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        isWorking = true
        errorMessage = nil
        Task {
            defer { isWorking = false }
            do {
                try await operation()
                dismiss()
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
