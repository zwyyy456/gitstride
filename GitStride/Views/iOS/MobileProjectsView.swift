import SwiftUI

struct MobileProjectsView: View {
    @Bindable var model: GitStrideModel
    @State private var search = ""
    @State private var creatingOwner: ProjectOwner?
    @State private var selectedOwnerID: String?
    @State private var catalogError: String?
    @Binding var selectedProjectID: String?
    private var store: ProjectStore { model.projectStore }

    private var owner: ProjectOwner? { store.owners.first { $0.id == selectedOwnerID } }
    private var projects: [Project] { selectedOwnerID.map { store.projects(ownerID: $0) } ?? [] }
    private var isLoading: Bool { selectedOwnerID.map { store.isLoadingProjects(ownerID: $0) } ?? store.isLoading }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedProjectID) {
                Section {
                    ForEach(projects.filter(matches)) { project in projectLink(project) }
                    if isLoading { ProgressView("Loading projects…") }
                    if !isLoading && projects.filter(matches).isEmpty {
                        Text(search.isEmpty ? String(localized: "No projects") : String(localized: "No Results"))
                            .foregroundStyle(.secondary)
                    }
                    if let catalogError { Text(catalogError).foregroundStyle(.red) }
                } header: {
                    if let owner { Text("Projects owned by \(owner.login)") }
                    else { Text("All Projects") }
                }
            }
            .navigationTitle("Projects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Owner", selection: Binding(
                            get: { selectedOwnerID },
                            set: { id in
                                selectedProjectID = nil
                                selectedOwnerID = id
                            }
                        )) {
                            ForEach(store.owners) { Text($0.login).tag(Optional($0.id)) }
                        }
                        .pickerStyle(.inline)
                    } label: { Label("Owner", systemImage: "person.crop.circle") }
                    .accessibilityValue(owner?.login ?? "")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { creatingOwner = owner } label: { Label("New Project", systemImage: "plus") }
                        .disabled(owner == nil)
                }
            }
            .sheet(item: $creatingOwner) { owner in
                MobileProjectManagement(model: model, creationOwner: owner)
            }
            .mobileSearch(text: $search, prompt: "Search projects")
            .refreshable {
                await loadCatalog()
            }
        } detail: {
            NavigationStack {
                if let selectedProjectID {
                    MobileProjectView(model: model, projectID: selectedProjectID)
                        .id(selectedProjectID)
                } else {
                    ContentUnavailableView("Select a Project", systemImage: "rectangle.stack")
                }
            }
        }
        .onChange(of: store.owners, initial: true) { _, owners in
            if !owners.contains(where: { $0.id == selectedOwnerID }) {
                selectedOwnerID = owners.first { $0.id == store.selectedOwnerId }?.id ?? owners.first?.id
                selectedProjectID = nil
            }
        }
        .task(id: selectedOwnerID) { await loadCatalog() }
    }

    private func loadCatalog() async {
        guard let owner else { return }
        catalogError = nil
        do {
            try await store.loadProjectCatalog(for: owner)
            guard !Task.isCancelled, selectedOwnerID == owner.id else { return }
            if let selectedProjectID, store.project(id: selectedProjectID) == nil {
                self.selectedProjectID = nil
            }
        } catch {
            guard !Task.isCancelled, selectedOwnerID == owner.id else { return }
            catalogError = error.localizedDescription
        }
    }

    private func matches(_ project: Project) -> Bool {
        search.isEmpty || project.title.localizedCaseInsensitiveContains(search)
            || project.owner.login.localizedCaseInsensitiveContains(search)
    }

    private func projectLink(_ project: Project) -> some View {
        NavigationLink(value: project.id) {
            HStack {
                ProjectIcon(projectID: project.id)
                Text(project.title)
                Spacer()
                if model.myWorkStore.isFollowing(project.id) {
                    Image(systemName: "star.fill").foregroundStyle(.secondary).accessibilityLabel("Following")
                }
            }
        }
        .swipeActions {
            Button { Task { await model.toggleFollowing(project) } } label: {
                Label(model.myWorkStore.isFollowing(project.id) ? String(localized: "Unfollow") : String(localized: "Follow"), systemImage: "star")
            }
            .tint(.orange)
        }
    }
}
