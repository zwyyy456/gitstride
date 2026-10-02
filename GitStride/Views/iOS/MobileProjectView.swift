import SwiftUI

struct MobileProjectView: View {
    @Bindable var model: GitStrideModel
    let projectID: String
    @State private var search = ""
    @State private var filter = ProjectWorkFilter()
    @State private var showingFilters = false
    @State private var showingAdd = false
    @State private var managingProject = false
    @State private var showingDisplay = false
    @State private var savingView = false
    @State private var viewName = ""
    @State private var selectedViewID: String?
    @State private var selection = Set<ItemInspectorReference>()
    @State private var selecting = false
    @State private var errorMessage: String?
    private var preferences = ProjectWorkPreferences()
    private var store: ProjectStore { model.projectStore }
    private var project: Project? { store.project(id: projectID) }
    private var savedView: SavedProjectWorkView? {
        preferences.views.first { $0.id == selectedViewID }
    }
    private var display: ProjectDisplayPreferences {
        ProjectDisplayPreferences(projectID: projectID, viewID: selectedViewID)
    }
    private var layout: ProjectLayout {
        savedView?.layout ?? preferences.layout(projectID: projectID, defaultLayout: .table)
    }
    private var items: [ProjectItem] {
        filter.apply(to: project?.items ?? [], currentUserLogin: store.currentUserLogin)
            .matching(search, currentUserLogin: store.currentUserLogin)
            .filter { store.pendingCreationState(for: $0.id) == nil }
    }
    private var statuses: [StatusOption] {
        guard let project else { return [] }
        return preferences.visibleStatuses(in: project, viewID: selectedViewID)
    }

    var body: some View {
        VStack(spacing: 0) {
            if store.isProjectCached(projectID) {
                Label("Showing cached data", systemImage: "clock").font(.caption).foregroundStyle(
                    .secondary
                ).padding(8)
            }
            if let message = errorMessage ?? store.operationErrorMessage {
                Text(message).font(.callout).foregroundStyle(.red).padding(8)
            }
            if filter.isDelivery, let project { deliverySummary(project) }
            if store.pendingCreationList.contains(where: { $0.projectID == projectID })
                || store.pendingEditList.contains(where: { $0.reference.projectID == projectID })
            {
                DisclosureGroup("Pending Changes") {
                    ScrollView { MobilePendingOperations(store: store, projectID: projectID) }
                        .frame(
                            maxHeight: 180)
                }.padding()
            }
            if store.isLoading && items.isEmpty {
                ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if layout == .board && !selecting {
                board
            } else {
                itemList
            }
        }
        .navigationTitle(savedView?.name ?? project?.title ?? String(localized: "Project"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showingAdd = true
                } label: {
                    Label("Add to Project", systemImage: "plus")
                }
                .disabled(!store.canEditProject(id: projectID))
                Button {
                    showingFilters = true
                } label: {
                    Label(
                        "Filter",
                        systemImage: filter.isActive
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle")
                }
                workspaceMenu
            }
        }
        .safeAreaInset(edge: .bottom) {
            if selecting, let project {
                MobileBatchActions(
                    store: store, items: items.map { MyWorkItem(project: project, item: $0) },
                    selection: $selection)
            }
        }
        .sheet(isPresented: $managingProject) {
            if let project { MobileProjectManagement(model: model, project: project) }
        }
        .sheet(isPresented: $showingAdd) { MobileAddItemView(store: store) }
        .sheet(isPresented: $showingFilters) {
            if let project { MobileFilterView(project: project, filter: $filter) }
        }
        .sheet(isPresented: $showingDisplay) {
            if let project {
                NavigationStack {
                    Form {
                        MobileDisplayFields(project: project, preferenceID: display.id)
                        Section("Board Columns") {
                            ForEach(project.statusOptions) { status in
                                Toggle(
                                    status.name,
                                    isOn: Binding(
                                        get: { statuses.contains { $0.id == status.id } },
                                        set: { visible in
                                            var ids = Set(statuses.map(\.id))
                                            if visible { ids.insert(status.id) }
                                            else { ids.remove(status.id) }
                                            change {
                                                try preferences.setHiddenStatuses(
                                                    Set(project.statusOptions.map(\.id)).subtracting(ids),
                                                    in: project, viewID: selectedViewID)
                                            }
                                        }
                                    ))
                            }
                        }
                    }
                    .navigationTitle("Display Options")
                    .toolbar { Button("Done") { showingDisplay = false } }
                }
            }
        }
        .alert("Save Current View", isPresented: $savingView) {
            TextField("View name", text: $viewName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { saveView() }.disabled(
                viewName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .onChange(of: items.map(\.id)) { _, ids in
            selection = selection.filter { ids.contains($0.itemID) }
        }
        .task(id: projectID) { if let project { await model.openProject(project) } }
    }

    private var itemList: some View {
        List {
            ForEach(items) { item in
                if selecting {
                    Button {
                        let reference = ItemInspectorReference(
                            projectID: projectID, itemID: item.id)
                        if !selection.insert(reference).inserted { selection.remove(reference) }
                    } label: {
                        HStack {
                            Image(
                                systemName: selection.contains(
                                    ItemInspectorReference(projectID: projectID, itemID: item.id))
                                    ? "checkmark.circle.fill" : "circle")
                            row(item)
                        }
                    }
                } else {
                    itemLink(item)
                }
            }
            if store.isLoading { ProgressView() }
            if items.isEmpty && !store.isLoading {
                ContentUnavailableView("No Items", systemImage: "tray")
            }
        }
        .refreshable { await store.loadProjectDetails(id: projectID) }
    }

    private var board: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(statuses) { status in
                        boardColumn(
                            title: status.name,
                            items: items.filter { $0.statusOptionId == status.id },
                            width: min(340, max(240, geometry.size.width - 48)))
                    }
                    if items.contains(where: { $0.statusOptionId == nil }) || statuses.isEmpty {
                        boardColumn(
                            title: String(localized: "No Status"),
                            items: items.filter { $0.statusOptionId == nil },
                            width: min(340, max(240, geometry.size.width - 48)))
                    }
                }
                .padding()
            }
        }
    }

    private func boardColumn(title: String, items: [ProjectItem], width: CGFloat) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text(items.count.formatted()).foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(items) { item in
                        itemLink(item).padding(12).background(
                            Color(uiColor: .secondarySystemGroupedBackground),
                            in: .rect(cornerRadius: 12))
                    }
                }
            }
            .refreshable { await store.loadProjectDetails(id: projectID) }
        }
        .frame(width: width)
    }

    private func row(_ item: ProjectItem) -> some View {
        MobileConfiguredItemRow(item: item, fields: project?.fields ?? [], preferenceID: display.id)
    }

    private func itemLink(_ item: ProjectItem) -> some View {
        NavigationLink {
            MobileItemDetailView(
                store: store,
                reference: ItemInspectorReference(projectID: projectID, itemID: item.id))
        } label: {
            row(item)
        }
        .contextMenu {
            if let project {
                Menu("Status") {
                    ForEach(project.statusOptions) { status in
                        Button(status.name) {
                            Task {
                                do {
                                    if let field = project.statusField {
                                        try await store.moveItemToStatus(
                                            projectID: projectID, itemID: item.id,
                                            fieldID: field.id, optionID: status.id)
                                    }
                                } catch { errorMessage = error.localizedDescription }
                            }
                        }
                    }
                }
                .disabled(
                    store.statusChangeUnavailableReason(
                        ItemInspectorReference(projectID: projectID, itemID: item.id)) != nil)
            }
        }
    }

    private var workspaceMenu: some View {
        Menu {
            Picker(
                "Layout",
                selection: Binding(
                    get: { layout },
                    set: { value in
                        change {
                            try preferences.setLayout(
                                value, projectID: projectID, viewID: selectedViewID)
                        }
                    })
            ) {
                Text("List").tag(ProjectLayout.table)
                Text("Board").tag(ProjectLayout.board)
            }
            Button("Display Options") { showingDisplay = true }
            Button(selecting ? String(localized: "Done") : String(localized: "Select")) {
                selecting.toggle()
                selection.removeAll()
            }
            Button("Refresh") { Task { await store.loadProjectDetails(id: projectID) } }
            Menu("Saved Views") {
                Button("All Items") {
                    selectedViewID = nil
                    filter = ProjectWorkFilter()
                }
                ForEach(preferences.views.filter { $0.projectID == projectID }) { view in
                    Button(view.name) {
                        selectedViewID = view.id
                        filter = view.filter
                        search = ""
                    }
                }
                Button("Save Current View") {
                    viewName = ""
                    savingView = true
                }
                if let savedView {
                    Button("Update Saved Filters") {
                        change { try preferences.setFilter(filter, viewID: savedView.id) }
                    }
                    .disabled(savedView.filter == filter)
                    Button("Delete Saved View", role: .destructive) {
                        change {
                            try preferences.delete(viewID: savedView.id)
                            selectedViewID = nil
                        }
                    }
                }
            }
            if filter.isActive || !search.isEmpty {
                Button("Clear Filters") {
                    filter = ProjectWorkFilter()
                    search = ""
                }
            }
            if let project {
                Button(
                    model.myWorkStore.isFollowing(projectID)
                        ? String(localized: "Unfollow") : String(localized: "Follow")
                ) {
                    Task { await model.toggleFollowing(project) }
                }
                if let url = URL(string: project.url) { Link("Open in GitHub", destination: url) }
            }
            Button("Manage Project") { managingProject = true }.disabled(
                !store.canManageProject(id: projectID))
        } label: {
            Label("More Actions", systemImage: "ellipsis.circle")
        }
    }

    private func deliverySummary(_ project: Project) -> some View {
        let scope = filter.deliveryItems(in: project.items).filter { $0.contentType == .issue }
        let completed = scope.filter(\.isWorkComplete).count
        let blocked = scope.filter { !$0.isWorkComplete && $0.signals.blockedByCount > 0 }.count
        return VStack(alignment: .leading) {
            Text("\(completed) of \(scope.count) completed · \(blocked) blocked").font(.subheadline)
            Picker("Completion", selection: $filter.completion) {
                ForEach(ProjectWorkCompletion.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
            Text(
                "Counts cover this project’s issues in the delivery, before other filters. Completed means closed on GitHub."
            )
            .font(.caption).foregroundStyle(.secondary)
        }.padding()
    }

    private func change(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = error.localizedDescription }
    }

    private func saveView() {
        let view = SavedProjectWorkView(
            projectID: projectID,
            name: viewName.trimmingCharacters(in: .whitespacesAndNewlines), filter: filter,
            layout: layout,
            hiddenStatusIDs: Set(project?.statusOptions.map(\.id) ?? []).subtracting(
                statuses.map(\.id)))
        change {
            try preferences.save(view, copyingDisplayFrom: display.id)
            selectedViewID = view.id
        }
    }
}
struct MobileFilterView: View {
    let project: Project
    @Binding var filter: ProjectWorkFilter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Toggle("Assigned to Me", isOn: $filter.assignedToMe)
                Picker("Completion", selection: $filter.completion) {
                    ForEach(ProjectWorkCompletion.allCases) { Text($0.title).tag($0) }
                }
                Section("Status") {
                    ForEach(project.statusOptions) { status in
                        Toggle(
                            status.name,
                            isOn: Binding(
                                get: { filter.statusIDs.contains(status.id) },
                                set: {
                                    if $0 {
                                        filter.statusIDs.insert(status.id)
                                    } else {
                                        filter.statusIDs.remove(status.id)
                                    }
                                }
                            ))
                    }
                }
                Section {
                    Picker("Label", selection: $filter.labelID) {
                        Text("All").tag(String?.none)
                        ForEach(labels, id: \.id) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Picker("Issue Type", selection: $filter.issueTypeID) {
                        Text("All").tag(String?.none)
                        ForEach(issueTypes) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Picker("Milestone", selection: $filter.milestoneID) {
                        Text("All").tag(String?.none)
                        ForEach(milestones) { Text($0.displayName).tag(Optional($0.id)) }
                    }
                    Picker("Parent Issue", selection: $filter.parentIssueID) {
                        Text("All").tag(String?.none)
                        ForEach(parents) { Text($0.displayName).tag(Optional($0.id)) }
                    }
                }
                Button("Clear Filters") { filter = ProjectWorkFilter() }
            }
            .navigationTitle("Filter")
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    private var labels: [IssueLabel] {
        var seen = Set<String>()
        return project.items.flatMap(\.labels).filter { seen.insert($0.id).inserted }.sorted {
            $0.name < $1.name
        }
    }
    private var issueTypes: [ProjectIssueType] {
        var seen = Set<String>()
        return project.items.compactMap(\.issueType).filter { seen.insert($0.id).inserted }
    }
    private var milestones: [ProjectPlanningReference] {
        var seen = Set<String>()
        return project.items.compactMap(\.milestone).filter { seen.insert($0.id).inserted }
    }
    private var parents: [ProjectPlanningReference] {
        var seen = Set<String>()
        return project.items.compactMap(\.parentIssue).filter { seen.insert($0.id).inserted }
    }
}
