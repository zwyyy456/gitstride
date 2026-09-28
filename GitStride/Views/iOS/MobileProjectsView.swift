import SwiftUI

struct MobileProjectsView: View {
    @Bindable var model: GitStrideModel
    @State private var search = ""
    @State private var creatingProject = false
    private var store: ProjectStore { model.projectStore }

    var body: some View {
        NavigationSplitView {
            List {
                Section {
                    Picker(
                        "Owner",
                        selection: Binding(
                            get: { store.selectedOwnerId },
                            set: { id in
                                if let owner = store.owners.first(where: { $0.id == id }) {
                                    Task { await store.selectOwner(owner) }
                                }
                            }
                        )
                    ) {
                        ForEach(store.owners) { Text($0.login).tag(Optional($0.id)) }
                    }
                }
                Section("Projects") {
                    ForEach(
                        store.projects.filter {
                            search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)
                        }
                    ) { project in
                        NavigationLink {
                            MobileProjectView(model: model, projectID: project.id)
                        } label: {
                            HStack {
                                Text(project.title)
                                Spacer()
                                if model.myWorkStore.isFollowing(project.id) {
                                    Image(systemName: "star.fill").foregroundStyle(.secondary)
                                        .accessibilityLabel("Following")
                                }
                            }
                        }
                        .swipeActions {
                            Button {
                                Task { await model.toggleFollowing(project) }
                            } label: {
                                Label(
                                    model.myWorkStore.isFollowing(project.id)
                                        ? String(localized: "Unfollow")
                                        : String(localized: "Follow"),
                                    systemImage: "star")
                            }
                            .tint(.orange)
                        }
                    }
                }
                if store.isLoading { ProgressView("Loading projects…") }
                if let error = store.error {
                    Text(error.localizedDescription).foregroundStyle(.red)
                }
            }
            .navigationTitle("Projects")
            .toolbar {
                Button {
                    creatingProject = true
                } label: {
                    Label("New Project", systemImage: "plus")
                }
                .disabled(store.selectedOwner == nil)
            }
            .sheet(isPresented: $creatingProject) { MobileProjectManagement(model: model) }
            .searchable(text: $search)
            .refreshable { await store.loadProjects() }
        } detail: {
            ContentUnavailableView("Select a Project", systemImage: "rectangle.stack")
        }
    }
}
