import SwiftUI

struct MobileProjectsView: View {
    @Bindable var model: GitStrideModel
    @State private var search = ""
    @State private var creatingProject = false
    @State private var selectedProjectID: String?
    private var store: ProjectStore { model.projectStore }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedProjectID) {
                Section {
                    ForEach(store.projects.filter(matches)) { project in projectLink(project) }
                    if store.isLoading { ProgressView("Loading projects…") }
                    if !store.isLoading && store.projects.filter(matches).isEmpty {
                        Text(search.isEmpty ? String(localized: "No projects") : String(localized: "No Results"))
                            .foregroundStyle(.secondary)
                    }
                    if let error = store.error { Text(error.localizedDescription).foregroundStyle(.red) }
                } header: {
                    if let owner = store.selectedOwner { Text("Projects owned by \(owner.login)") }
                    else { Text("All Projects") }
                }
            }
            .navigationTitle("Projects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Owner", selection: Binding(
                            get: { store.selectedOwnerId },
                            set: { id in
                                guard let owner = store.owners.first(where: { $0.id == id }) else { return }
                                selectedProjectID = nil
                                Task { await store.selectOwner(owner) }
                            }
                        )) {
                            ForEach(store.owners) { Text($0.login).tag(Optional($0.id)) }
                        }
                        .pickerStyle(.inline)
                    } label: { Label("Owner", systemImage: "person.crop.circle") }
                    .accessibilityValue(store.selectedOwner?.login ?? "")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { creatingProject = true } label: { Label("New Project", systemImage: "plus") }
                        .disabled(store.selectedOwner == nil)
                }
            }
            .sheet(isPresented: $creatingProject) { MobileProjectManagement(model: model) }
            .mobileSearch(text: $search, prompt: "Search projects")
            .refreshable {
                await store.loadProjects()
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
