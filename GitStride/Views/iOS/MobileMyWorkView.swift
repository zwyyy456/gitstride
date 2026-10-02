import SwiftUI

struct MobileFollowedWorkView: View {
    @Bindable var model: GitStrideModel
    @State private var filter: MyWorkFilter = .allOpen
    @State private var groupByProject = true
    let browseProjects: () -> Void
    @State private var search = ""
    @State private var selection = Set<ItemInspectorReference>()
    @State private var selecting = false

    private var items: [MyWorkItem] {
        model.followedItems(for: filter).filter {
            ![$0.item].matching(search, currentUserLogin: model.projectStore.currentUserLogin)
                .isEmpty
        }
    }

    private var projectIDs: Set<String> {
        Set(model.myWorkStore.followedProjects.map(\.id))
    }

    private var hasPendingOperations: Bool {
        model.projectStore.pendingCreationList.contains { projectIDs.contains($0.projectID) }
            || model.projectStore.pendingEditList.contains {
                guard let projectID = $0.reference?.projectID else { return false }
                return projectIDs.contains(projectID)
            }
    }

    private var hasActiveFilter: Bool { filter != .allOpen || !search.isEmpty }

    var body: some View {
        Group {
            if projectIDs.isEmpty {
                ContentUnavailableView {
                    Label("No followed projects", systemImage: "star")
                } description: {
                    Text("Follow projects to see their items here.")
                } actions: {
                    Button("Browse Projects", action: browseProjects)
                        .buttonStyle(.borderedProminent)
                }
            } else {
                followedList
                    .mobileSearch(text: $search)
            }
        }
        .navigationTitle(String(localized: "Following Tab", defaultValue: "Following"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !projectIDs.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    if selecting {
                        Button("Done") {
                            selecting = false
                            selection.removeAll()
                        }
                    } else {
                        Menu {
                            Section {
                                Picker("Scope", selection: $filter) {
                                    ForEach(MyWorkFilter.followedCases) {
                                        Label($0.title, systemImage: $0.icon).tag($0)
                                    }
                                }
                            }
                            Section {
                                Toggle("Group by Project", isOn: $groupByProject)
                            }
                            Section {
                                Button("Select items") { selecting = true }
                                    .disabled(items.isEmpty)
                                Button("Browse Projects", action: browseProjects)
                            }
                        } label: { Label("More", systemImage: "ellipsis.circle") }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if selecting && !projectIDs.isEmpty {
                MobileBatchActions(store: model.projectStore, items: items, selection: $selection)
            }
        }
        .onChange(of: items.map(\.id)) { _, _ in
            let visible = Set(
                items.map { ItemInspectorReference(projectID: $0.project.id, itemID: $0.item.id) })
            selection.formIntersection(visible)
            if items.isEmpty { selecting = false }
        }
    }

    private var followedList: some View {
        List {
            MobilePendingOperations(store: model.projectStore, projectIDs: projectIDs)
            if !items.isEmpty || hasPendingOperations {
                if let error = model.followedProjectsErrorMessage {
                    Section {
                        Text(error).foregroundStyle(.secondary)
                        Button("Retry") { refresh() }
                    }
                }
                if model.projectStore.isLoadingFollowedProjects {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            if groupByProject {
                ForEach(model.followedProjects) { project in
                    let projectItems = items.filter { $0.project.id == project.id }
                    if !projectItems.isEmpty {
                        Section {
                            ForEach(projectItems) { work in row(work) }
                        } header: {
                            HStack(spacing: 8) {
                                ProjectIcon(projectID: project.id)
                                Text(project.title)
                                if model.followedProjects.filter({ $0.title == project.title }).count > 1 {
                                    Text(project.owner.login)
                                }
                            }
                            .font(.subheadline).foregroundStyle(.secondary)
                            .textCase(nil)
                        }
                    }
                }
            } else {
                ForEach(items) { work in row(work) }
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(.compact)
        .overlay {
            if items.isEmpty && !hasPendingOperations { emptyContent }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if hasActiveFilter {
                HStack {
                    Text(filter == .allOpen ? String(localized: "Search results") : filter.title)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") { clearFilters() }
                }
                .font(.subheadline)
                .padding(.horizontal).padding(.vertical, 8)
                .background(.background)
            }
        }
        .refreshable { await model.refreshFollowedProjects() }
    }

    @ViewBuilder
    private var emptyContent: some View {
        if model.projectStore.isLoadingFollowedProjects {
            ProgressView("Loading…")
        } else if let error = model.followedProjectsErrorMessage {
            ContentUnavailableView {
                Label("Couldn’t load followed projects", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") { refresh() }.buttonStyle(.bordered)
            }
        } else if hasActiveFilter {
            ContentUnavailableView {
                Label("No matching items", systemImage: "magnifyingglass")
            } description: {
                Text("Try another search or clear the filters.")
            } actions: {
                Button("Clear filters") { clearFilters() }.buttonStyle(.bordered)
            }
        } else {
            ContentUnavailableView(
                "No open items", systemImage: "checkmark.circle",
                description: Text("Your followed projects have no open items."))
        }
    }

    private func clearFilters() {
        filter = .allOpen
        search = ""
    }

    private func refresh() {
        Task { await model.refreshFollowedProjects() }
    }

    private func itemRow(_ work: MyWorkItem) -> some View {
        MobileItemRow(
            item: work.item,
            statusOption: work.project.statusOptions.first { $0.id == work.item.statusOptionId }
        ) {
            if !groupByProject {
                Text(work.project.title).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func row(_ work: MyWorkItem) -> some View {
        if selecting {
            Button {
                let reference = ItemInspectorReference(
                    projectID: work.project.id, itemID: work.item.id)
                if !selection.insert(reference).inserted { selection.remove(reference) }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(
                        systemName: selection.contains(
                            ItemInspectorReference(
                                projectID: work.project.id, itemID: work.item.id))
                            ? "checkmark.circle.fill" : "circle")
                        .frame(height: 32)
                    itemRow(work)
                }
            }
            .accessibilityAddTraits(selection.contains(
                ItemInspectorReference(projectID: work.project.id, itemID: work.item.id))
                ? .isSelected : [])
        } else {
            NavigationLink {
                MobileItemDetailView(
                    store: model.projectStore,
                    reference: ItemInspectorReference(
                        projectID: work.project.id, itemID: work.item.id))
            } label: { itemRow(work) }
        }
    }
}

struct MobileMyWorkView: View {
    @Bindable var model: GitStrideModel
    @AppStorage("mobileMyWorkFilter") private var filter: MyWorkFilter = .assigned
    var body: some View {
        PersonalWorkView(store: model.projectStore, filter: $filter)
    }
}
