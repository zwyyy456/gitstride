import SwiftUI

struct MyWorkView: View {
    @Bindable var model: GitStrideModel
    let filter: MyWorkFilter
    let showItemDetail: (ItemInspectorReference) -> Void
    let didOpenProject: () -> Void
    @State private var operationErrorMessage: String?
    @State private var selectedID: String?
    @State private var selectedIDs: Set<String> = []
    @State private var isSelecting = false
    @State private var isBulkWorking = false
    @State private var searchText = ""
    @State private var searchPresented = false

    private var items: [MyWorkItem] {
        model.myWorkItems(for: filter).filter {
            ![$0.item].matching(searchText, currentUserLogin: model.projectStore.currentUserLogin).isEmpty
        }
    }

    private var selectableIDs: [String] {
        items.filter { model.projectStore.pendingCreationState(for: $0.item.id) == nil }.map(\.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let errorMessage = operationErrorMessage ?? model.myWorkErrorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(errorMessage)
                        .font(.caption)
                    Spacer()
                }
                .padding(12)
                .background(Color.orange.opacity(0.12))
            }

            if model.myWorkStore.followedProjects.isEmpty {
                ContentUnavailableView(
                    "No Projects in My Work",
                    systemImage: "briefcase",
                    description: Text("Open a Project and click Add to My Work in the toolbar.")
                )
            } else if model.projectStore.isLoadingFollowedProjects && model.myWorkProjects.isEmpty {
                ProgressView("Loading My Work…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                ContentUnavailableView(
                    "Nothing in \(filter.title)",
                    systemImage: filter.icon,
                    description: Text("No items in My Work match this filter.")
                )
            } else {
                ScrollViewReader { proxy in
                    List(selection: listSelection) {
                        ForEach(items) { workItem in
                            MyWorkRow(
                                workItem: workItem,
                                model: model,
                                showDetails: {
                                    selectedID = workItem.id
                                    if isSelecting {
                                        guard selectableIDs.contains(workItem.id) else { return }
                                        if selectedIDs.contains(workItem.id) { selectedIDs.remove(workItem.id) }
                                        else { selectedIDs.insert(workItem.id) }
                                    } else { showDetails(workItem) }
                                },
                                openProject: { openProject(workItem.project) },
                                reportError: report
                            )
                            .tag(workItem.id)
                            .overlay {
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(selectedID == workItem.id && (isSelecting || !selectedIDs.contains(workItem.id)) ? Color.accentColor : .clear)
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                    .listStyle(.inset)
                    .itemSelectionKeyboard(ids: selectableIDs, current: $selectedID,
                        selected: $selectedIDs, isSelecting: $isSelecting)
                    .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                        guard !KeyboardInput.isEditingText, press.modifiers.isEmpty else { return .ignored }
                        selectedID = ItemKeyboardNavigation.next(from: selectedID, in: selectableIDs,
                            offset: press.key == .upArrow ? -1 : 1)
                        if !isSelecting { selectedIDs = Set(selectedID.map { [$0] } ?? []) }
                        return .handled
                    }
                    .onKeyPress(.space) {
                        guard !KeyboardInput.isEditingText, isSelecting, let selectedID else { return .ignored }
                        if selectedIDs.contains(selectedID) { selectedIDs.remove(selectedID) }
                        else { selectedIDs.insert(selectedID) }
                        return .handled
                    }
                    .onKeyPress(.return) {
                        guard !KeyboardInput.isEditingText, !isSelecting, let selected = items.first(where: { $0.id == selectedID }) else { return .ignored }
                        showDetails(selected)
                        return .handled
                    }
                    .onChange(of: selectedID) { _, id in if let id { proxy.scrollTo(id) } }
                }
            }
        }
        .frame(minHeight: 560)
        .searchable(text: $searchText, isPresented: $searchPresented, prompt: "Search title, #number, or @assignee")
        .onChange(of: items.map(\.id)) { old, new in
            selectedID = ItemKeyboardNavigation.reconciled(selectedID, old: old, new: new)
            selectedIDs.formIntersection(new)
        }
        .onChange(of: filter) { _, _ in selectedID = nil; selectedIDs = []; isSelecting = false; searchText = "" }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 6) {
                    Label(filter.title, systemImage: filter.icon)
                    Text("\(items.count)")
                        .foregroundStyle(.secondary)
                }
                .help("\(items.count) items in \(filter.title)")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                if isSelecting {
                    Text("\(selectedIDs.count) Selected")
                    Menu("Move To") {
                        ForEach(commandContext.moveSelection) { action in
                            Button(action.title, action: action.perform).disabled(!action.isEnabled)
                        }
                    }.disabled(!canWork || commonStatuses.isEmpty)
                    Button("Archive Selected Items", role: .destructive) { performBulk(status: nil) }
                        .disabled(!canWork)
                    Button("Done Selecting") { isSelecting = false; selectedIDs = [] }
                        .disabled(isBulkWorking)
                }

                Menu {
                    ForEach(model.myWorkStore.followedProjects) { reference in
                        let title = followedProjectTitle(reference)
                        Button("Remove \(title) from My Work", role: .destructive) {
                            stopFollowing(reference)
                        }
                    }
                } label: {
                    Label(
                        "Projects \(model.myWorkStore.followedProjects.count)",
                        systemImage: "briefcase"
                    )
                }
                .disabled(model.myWorkStore.followedProjects.isEmpty)
                .help("Manage My Work Projects")

                if model.projectStore.isLoadingFollowedProjects {
                    ProgressView()
                        .controlSize(.small)
                        .help("Refreshing My Work")
                } else {
                    Button("Refresh My Work", systemImage: "arrow.clockwise", action: refresh)
                        .labelStyle(.iconOnly)
                        .help("Refresh My Work")
                }
            }
        }
        .focusedSceneValue(\.workspaceCommandContext, commandContext)
    }

    private var commandContext: WorkspaceCommandContext {
        var context = WorkspaceCommandContext(
            find: .init(id: "find", title: WorkspaceShortcut.find.title, shortcut: .find,
                        symbol: "magnifyingglass", perform: { searchPresented = true }),
            itemReference: !isSelecting ? items.first(where: { $0.id == selectedID }).map {
                ItemInspectorReference(projectID: $0.project.id, itemID: $0.item.id)
            } : nil,
            refresh: .init(
                id: "refresh-my-work",
                title: String(localized: "Refresh My Work"),
                isEnabled: model.projectStore.isLoadingFollowedProjects == false,
                keywords: "r refresh reload 刷新", shortcut: .refresh, symbol: "arrow.clockwise", perform: refresh
            ),
            stopFollowing: model.myWorkStore.followedProjects.map { reference in
                .init(
                    id: "stop-following-\(reference.id)",
                    title: String(localized: "Remove \(followedProjectTitle(reference)) from My Work"),
                    keywords: "follow 关注 我的工作", symbol: "briefcase", perform: { stopFollowing(reference) }
                )
            }
        )
        context.toggleSelection = .init(id: "toggle-selection",
            title: isSelecting ? String(localized: "Done Selecting") : String(localized: "Select Items"),
            isEnabled: !isBulkWorking, keywords: "select 选择", symbol: "checkmark.circle", perform: { isSelecting.toggle(); selectedIDs = [] })
        if isSelecting {
            context.moveSelection = commonStatuses.map { name in
                .init(id: "move-selection-" + name, title: name, isEnabled: canWork,
                      symbol: "arrow.right.circle", group: .itemActions, perform: { performBulk(status: name) })
            }
            context.archiveSelection = .init(id: "archive-selection", title: String(localized: "Archive Selected Items"),
                isEnabled: canWork, keywords: "archive 归档", isDestructive: true, symbol: "archivebox", group: .itemActions, perform: { performBulk(status: nil) })
        }
        return context
    }

    private var listSelection: Binding<Set<String>> {
        Binding(get: { selectedIDs }, set: { ids in
            let ids = ids.intersection(selectableIDs)
            let added = ids.subtracting(selectedIDs)
            selectedIDs = ids
            if let lastAdded = items.last(where: { added.contains($0.id) }) { selectedID = lastAdded.id }
            else if ids.count == 1 { selectedID = ids.first }
            if ids.count > 1 { isSelecting = true }
        })
    }

    private var selectedItems: [MyWorkItem] { items.filter { selectedIDs.contains($0.id) } }
    private var canWork: Bool {
        !isBulkWorking && !selectedItems.isEmpty
            && selectedItems.allSatisfy { model.projectStore.canEditProject(id: $0.project.id) }
    }
    private var commonStatuses: [String] {
        guard let first = selectedItems.first else { return [] }
        return first.project.statusOptions.map(\.name).filter { name in
            selectedItems.allSatisfy { $0.project.statusOptions.contains { $0.name == name } }
        }
    }

    private func performBulk(status: String?) {
        guard canWork else { return }
        let targets = selectedItems
        let store = model.projectStore
        isBulkWorking = true
        operationErrorMessage = nil
        Task { @MainActor in
            defer { isBulkWorking = false }
            do {
                for target in targets {
                    let reference = ItemInspectorReference(projectID: target.project.id, itemID: target.item.id)
                    guard let item = store.item(for: reference) else { throw ProjectStoreError.itemUnavailable }
                    if let status {
                        guard let option = store.project(id: target.project.id)?.statusOptions.first(where: { $0.name == status })
                        else { throw ProjectStoreError.itemUnavailable }
                        try await store.moveItem(item, toStatus: option, in: target.project.id)
                    } else {
                        try await store.archiveItem(item, in: target.project.id)
                    }
                    selectedIDs.remove(target.id)
                }
                if selectedIDs.isEmpty { isSelecting = false }
            } catch { report(error) }
        }
    }

    private func followedProjectTitle(_ reference: FollowedProject) -> String {
        model.projectStore.followedProject(id: reference.id)?.title
            ?? reference.displayTitle
            ?? reference.owner.login
    }

    private func refresh() {
        Task { await model.refreshMyWork() }
    }

    private func stopFollowing(_ reference: FollowedProject) {
        Task { await model.stopFollowing(reference) }
    }

    private func openProject(_ project: Project) {
        Task {
            await model.openProject(project)
            didOpenProject()
        }
    }

    private func showDetails(_ workItem: MyWorkItem) {
        showItemDetail(
            ItemInspectorReference(
                projectID: workItem.project.id,
                itemID: workItem.item.id
            )
        )
    }

    private func report(_ error: Error) {
        guard (error is CancellationError) == false else { return }
        operationErrorMessage = error.localizedDescription
    }
}

private struct MyWorkRow: View {
    let workItem: MyWorkItem
    @Bindable var model: GitStrideModel
    let showDetails: () -> Void
    let openProject: () -> Void
    let reportError: (Error) -> Void

    var body: some View {
        Button(action: showDetails) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: workItem.item.contentType == .pullRequest
                    ? "arrow.triangle.pull"
                    : "record.circle")
                    .foregroundStyle(workItem.item.contentType == .pullRequest ? .purple : .green)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 5) {
                    Text(workItem.item.displayTitle)
                        .font(.body.weight(.medium))
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Text(workItem.project.owner.login)
                        Text("/")
                        Text(workItem.project.title)
                        if let number = workItem.item.number {
                            Text("#\(number)")
                        }
                        if let status = workItem.item.status {
                            Text(status)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(.secondary.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    EngineeringSignalsView(item: workItem.item)
                }

                Spacer()
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 5)
        .accessibilityHint("Shows item details")
        .contextMenu {
            Button("Show Details", systemImage: "sidebar.right", action: showDetails)

            Button("Open Project", systemImage: "rectangle.split.3x1") {
                openProject()
            }

            if let urlString = workItem.item.url, let url = URL(string: urlString) {
                Link("Open in GitHub", destination: url)
            }

            if workItem.project.viewerCanUpdate {
                Divider()

                if let statusField = workItem.project.fields.first(where: { $0.name == "Status" }) {
                    Menu("Status") {
                        ForEach(statusField.options) { option in
                            Button(option.name) {
                                Task {
                                    do {
                                        try await model.updateMyWorkField(
                                            on: workItem,
                                            field: statusField,
                                            value: .singleSelect(optionId: option.id, name: option.name)
                                        )
                                    } catch {
                                        reportError(error)
                                    }
                                }
                            }
                        }
                    }
                }

                if let priorityField = workItem.project.fields.first(where: {
                    $0.kind == .singleSelect && $0.name.caseInsensitiveCompare("Priority") == .orderedSame
                }) {
                    Menu("Priority") {
                        ForEach(priorityField.options) { option in
                            Button(option.name) {
                                Task {
                                    do {
                                        try await model.updateMyWorkField(
                                            on: workItem,
                                            field: priorityField,
                                            value: .singleSelect(optionId: option.id, name: option.name)
                                        )
                                    } catch {
                                        reportError(error)
                                    }
                                }
                            }
                        }
                    }
                }

                Divider()

                Button("Archive from Project", systemImage: "archivebox") {
                    Task {
                        do {
                            try await model.archiveMyWorkItem(workItem)
                        } catch {
                            reportError(error)
                        }
                    }
                }
            }
        }
    }
}
