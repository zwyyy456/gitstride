import SwiftUI

struct MobileWorkspaceView: View {
    enum Scope { case projects, workspace }
    private enum Destination: Hashable {
        case project(String)
        case myWork(MyWorkFilter)
        case settings
    }

    let scope: Scope
    @State private var destination: Destination?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    @Bindable var model: GitStrideModel
    @State private var search = ""
    @State private var creatingOwner: ProjectOwner?
    @State private var selectedOwnerID: String?
    @State private var catalogError: String?
    private var selectedProjectID: String? {
        if case .project(let id) = destination { return id }
        return nil
    }
    private var store: ProjectStore { model.projectStore }

    private var owner: ProjectOwner? { store.owners.first { $0.id == selectedOwnerID } }
    private var projects: [Project] { selectedOwnerID.map { store.projects(ownerID: $0) } ?? [] }
    private var isLoading: Bool { selectedOwnerID.map { store.isLoadingProjects(ownerID: $0) } ?? store.isLoading }

    init(model: GitStrideModel, scope: Scope) {
        self.model = model
        self.scope = scope
        _destination = State(initialValue: scope == .workspace ? .myWork(.assigned) : nil)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $destination) {
                if scope == .workspace {
                    Section("Owner") {
                        ownerPicker
                            .disabled(store.owners.isEmpty)
                    }
                }
                Section {
                    ForEach(projects.filter(matches)) { project in projectLink(project) }
                    if isLoading { ProgressView("Loading projects…") }
                    if !isLoading && projects.filter(matches).isEmpty {
                        Text(search.isEmpty ? String(localized: "No projects") : String(localized: "No Results"))
                            .foregroundStyle(.secondary)
                    }
                    if let catalogError {
                        Text(catalogError).foregroundStyle(.red)
                        Button("Retry") { Task { await loadCatalog() } }
                    }
                } header: {
                    if scope == .projects, let owner {
                        Text("Projects owned by \(owner.login)")
                    } else {
                        Text("Projects")
                    }
                }
                if scope == .workspace {
                    Section("My Work") {
                        ForEach(MyWorkFilter.personalCases) { filter in
                            NavigationLink(value: Destination.myWork(filter)) {
                                Label(filter.title, systemImage: filter.icon)
                            }
                        }
                    }
                    Section("Followed Projects") {
                        ForEach(model.myWorkStore.filters) { filter in
                            NavigationLink(value: Destination.myWork(filter)) {
                                Label(filter.title, systemImage: filter.icon)
                            }
                        }
                    }
                    Section {
                        NavigationLink(value: Destination.settings) {
                            Label("Settings", systemImage: "gear")
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle(scope == .workspace ? Text("GitStride") : Text("Projects"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if scope == .workspace {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Refresh", systemImage: "arrow.clockwise") { Task { await loadCatalog() } }
                            .disabled(isLoading || owner == nil)
                    }
                } else {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            ownerPicker.pickerStyle(.inline)
                        } label: {
                            Label("Owner", systemImage: "person.crop.circle")
                        }
                        .accessibilityValue(owner?.login ?? "")
                    }
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
            .refreshable { await loadCatalog() }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            NavigationStack {
                switch destination {
                case .project(let id):
                    MobileProjectView(model: model, projectID: id)
                case .myWork(let filter):
                    if filter.isPersonal {
                        PersonalWorkView(store: store, filter: workFilterBinding(filter), showsScopePicker: false)
                    } else {
                        MobileFollowedWorkView(model: model, filter: workFilterBinding(filter),
                                               showsScopePicker: false, browseProjects: browseProjects)
                    }
                case .settings:
                    MobileSettingsView(model: model)
                case nil:
                    ContentUnavailableView("Select a Project", systemImage: "rectangle.stack")
                }
            }
            .id(destination)
        }
        .navigationSplitViewStyle(.balanced)
        .projectUsage(store: store, projectIDs: Set(selectedProjectID.map { [$0] } ?? []))
        .onChange(of: store.owners, initial: true) { _, owners in
            if !owners.contains(where: { $0.id == selectedOwnerID }) {
                selectedOwnerID = owners.first { $0.id == store.selectedOwnerId }?.id ?? owners.first?.id
                if selectedProjectID != nil { destination = nil }
            }
        }
        .task(id: selectedOwnerID) { await loadCatalog() }
    }

    private var ownerPicker: some View {
        Picker("Owner", selection: Binding(
            get: { selectedOwnerID },
            set: { id in
                if selectedProjectID != nil { destination = nil }
                selectedOwnerID = id
            }
        )) {
            if selectedOwnerID == nil { Text("Select an owner").tag(String?.none) }
            ForEach(store.owners) { Text($0.login).tag(Optional($0.id)) }
        }
    }

    private func workFilterBinding(_ current: MyWorkFilter) -> Binding<MyWorkFilter> {
        Binding(get: {
            if case .myWork(let filter) = destination { return filter }
            return current
        }, set: { destination = .myWork($0) })
    }

    private func browseProjects() {
        search = ""
        destination = nil
        columnVisibility = .all
    }

    private func loadCatalog() async {
        guard let owner else { return }
        catalogError = nil
        do {
            try await store.loadProjectCatalog(for: owner)
            guard !Task.isCancelled, selectedOwnerID == owner.id else { return }
            if let selectedProjectID, store.project(id: selectedProjectID) == nil {
                destination = nil
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
        NavigationLink(value: Destination.project(project.id)) {
            HStack {
                ProjectIcon(projectID: project.id)
                Text(project.title).lineLimit(1)
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
