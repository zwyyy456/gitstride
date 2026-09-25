import SwiftUI

struct CommandPaletteNavigation {
    let openProject: (String) -> Void
    let openItem: (ItemInspectorReference) -> Void
    let openMyWork: (MyWorkFilter) -> Void
}

private struct PaletteEditor: Identifiable {
    let reference: ItemInspectorReference
    let detail: ProjectItemDetail
    var id: ItemInspectorReference { reference }
}

private struct PaletteSession: Identifiable {
    let id = UUID()
    let context: WorkspaceCommandContext?
    let roadmap: RoadmapCommandContext?
    let shortcuts: Bool
    var statusTarget: ItemInspectorReference? = nil
}

struct CommandPaletteHost: ViewModifier {
    @Bindable var store: ProjectStore
    let navigation: CommandPaletteNavigation
    var opensWorkspaceForNavigation = false
    @Environment(\.openWindow) private var openWindow
    @Binding var requested: Bool
    @FocusedValue(\.workspaceCommandContext) private var context
    @FocusedValue(\.roadmapCommands) private var roadmap
    @State private var session: PaletteSession?
    @State private var window: NSWindow?
    @State private var previousResponder: NSResponder?
    @State private var pendingAction: (() -> Void)?
    @State private var errorMessage: String?
    @State private var editRequest: ItemInspectorReference?
    @State private var editor: PaletteEditor?

    func body(content: Content) -> some View {
        content
            .background(MenuBarWindowFinder(window: $window))
            .safeAreaInset(edge: .top, spacing: 0) {
                OperationErrorBanner(message: errorMessage, dismiss: { errorMessage = nil })
                if editRequest != nil {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Loading item editor…")
                        Button("Cancel") { editRequest = nil }
                    }.padding(8)
                }
            }
            .focusedSceneValue(
                \.commandPaletteRequest,
                CommandPaletteRequest(
                    show: { show(shortcuts: false) }, showShortcuts: { show(shortcuts: true) },
                    showStatus: { show(shortcuts: false, statusTarget: context?.itemReference) }
                )
            )
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Show Command Palette…", systemImage: "command") { show(shortcuts: false) }
                        .help("Show Command Palette… (⌘K)")
                }
            }
            .sheet(item: $session, onDismiss: finish) { session in
                CommandPaletteView(
                    store: store, context: session.context, roadmap: session.roadmap,
                    navigation: CommandPaletteNavigation(
                        openProject: { id in
                            openWorkspace()
                            navigation.openProject(id)
                        },
                        openItem: { reference in
                            openWorkspace()
                            navigation.openItem(reference)
                        },
                        openMyWork: { filter in
                            openWorkspace()
                            navigation.openMyWork(filter)
                        }
                    ), initiallyShowsShortcuts: session.shortcuts,
                    initialStatusTarget: session.statusTarget,
                    reportError: { errorMessage = $0 },
                    execute: { action in
                        pendingAction = action
                        self.session = nil
                    },
                    changeStatus: changeStatus,
                    editItem: { editRequest = $0 },
                    close: { self.session = nil })
            }
            .sheet(item: $editor) { editor in
                ItemContentEditorView(store: store, reference: editor.reference, detail: editor.detail)
            }
            .task(id: editRequest) {
                guard let reference = editRequest else { return }
                defer { if editRequest == reference { editRequest = nil } }
                guard let item = store.item(for: reference) else {
                    errorMessage = String(localized: "This item is no longer available.")
                    return
                }
                await store.loadItemDetail(for: item)
                guard !Task.isCancelled else { return }
                guard let current = store.item(for: reference),
                    case .loaded(let detail) = store.itemDetailState(for: current)
                else {
                    errorMessage = String(localized: "Couldn’t load the item editor. Refresh the item and try again.")
                    return
                }
                guard store.canEditItemContent(reference) else {
                    errorMessage = String(localized: "This item is read-only.")
                    return
                }
                editor = PaletteEditor(reference: reference, detail: detail)
            }
            .onChange(of: requested, initial: true) { _, value in
                guard value else { return }
                if window != nil {
                    requested = false
                    show(shortcuts: false)
                }
            }
            .onChange(of: window) { _, window in
                guard window != nil, requested else { return }
                requested = false
                show(shortcuts: false)
            }
    }

    private func openWorkspace() {
        if opensWorkspaceForNavigation { openWindow(id: "kanban-board") }
    }

    private func show(shortcuts: Bool, statusTarget: ItemInspectorReference? = nil) {
        guard session == nil, editRequest == nil, let window, window.attachedSheet == nil else { return }
        window.makeKeyAndOrderFront(nil)
        previousResponder = window.firstResponder
        session = PaletteSession(context: context, roadmap: roadmap, shortcuts: shortcuts, statusTarget: statusTarget)
    }

    private func finish() {
        if let previousResponder { window?.makeFirstResponder(previousResponder) }
        previousResponder = nil
        let action = pendingAction
        pendingAction = nil
        action?()
    }

    private func changeStatus(_ reference: ItemInspectorReference, _ statusID: String) {
        // The task uses this connection's store and survives dismissal of the palette.
        Task { @MainActor in
            guard let item = store.item(for: reference),
                let status = store.project(id: reference.projectID)?.statusOptions.first(where: { $0.id == statusID })
            else {
                errorMessage = String(localized: "This item is no longer available.")
                return
            }
            if let reason = store.statusChangeUnavailableReason(reference) {
                errorMessage = reason
                return
            }
            guard item.statusOptionId != status.id else { return }
            do { try await store.moveItem(item, toStatus: status, in: reference.projectID) } catch is CancellationError
            { return } catch { errorMessage = error.localizedDescription }
        }
    }
}

extension View {
    func commandPalette(
        store: ProjectStore, opensWorkspaceForNavigation: Bool = false, navigation: CommandPaletteNavigation,
        requested: Binding<Bool> = .constant(false)
    ) -> some View {
        modifier(
            CommandPaletteHost(
                store: store, navigation: navigation, opensWorkspaceForNavigation: opensWorkspaceForNavigation,
                requested: requested))
    }
}

private enum PaletteScope: String, CaseIterable, Identifiable {
    case all, commands, projects, items
    var id: Self { self }
    var title: String {
        switch self {
        case .all: String(localized: "All")
        case .commands: String(localized: "Commands")
        case .projects: String(localized: "Projects")
        case .items: String(localized: "Loaded Items")
        }
    }
}

private struct PaletteResult: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let scope: PaletteScope
    var keywords = ""
    var shortcut: WorkspaceShortcut? = nil
    var unavailable: String? = nil
    var destructive = false
    var reference: ItemInspectorReference? = nil
    let perform: () -> Void
}

struct CommandPaletteView: View {
    @Bindable var store: ProjectStore
    let context: WorkspaceCommandContext?
    let roadmap: RoadmapCommandContext?
    let navigation: CommandPaletteNavigation
    let initiallyShowsShortcuts: Bool
    let initialStatusTarget: ItemInspectorReference?
    let reportError: (String) -> Void
    let execute: (@escaping () -> Void) -> Void
    let changeStatus: (ItemInspectorReference, String) -> Void
    let editItem: (ItemInspectorReference) -> Void
    let close: () -> Void
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @State private var query = ""
    @State private var scope: PaletteScope = .all
    @State private var selection: String?
    @State private var statusTarget: ItemInspectorReference?
    @State private var showsShortcuts = false
    @State private var confirmation: PaletteResult?

    private var results: [PaletteResult] {
        let candidates = statusTarget.map(statusResults) ?? rootResults
        return candidates.enumerated().compactMap { index, result -> (Int, Int, PaletteResult)? in
            guard statusTarget != nil || scope == .all || result.scope == scope,
                let rank = CommandSearch.rank(
                    query, title: result.title, keywords: result.keywords + " " + result.subtitle)
            else { return nil }
            return (rank, index, result)
        }.sorted {
            let lhsScope = PaletteScope.allCases.firstIndex(of: $0.2.scope) ?? 0
            let rhsScope = PaletteScope.allCases.firstIndex(of: $1.2.scope) ?? 0
            return (lhsScope, $0.0, $0.1) < (rhsScope, $1.0, $1.1)
        }.map(\.2)
    }

    private var selectedResult: PaletteResult? { results.first { $0.id == selection } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if statusTarget != nil || showsShortcuts {
                    Button("Back", systemImage: "chevron.left", action: back).labelStyle(.iconOnly)
                }
                Text(showsShortcuts ? String(localized: "Keyboard Shortcuts") : String(localized: "Command Palette"))
                    .font(.headline)
                Spacer()
                Button("Close", systemImage: "xmark", action: close).labelStyle(.iconOnly)
            }
            .padding(16)
            if showsShortcuts {
                shortcutHelp
            } else {
                CommandSearchField(text: $query, move: move, submit: submit, cancel: back)
                    .frame(height: 28).padding(.horizontal, 16)
                if let target = statusTarget {
                    Text(targetTitle(target)).font(.callout).foregroundStyle(.secondary)
                        .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading).padding(16)
                } else {
                    Picker("Search scope", selection: $scope) {
                        ForEach(PaletteScope.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).padding(16)
                }
                Divider()
                resultList
                Divider()
                HStack {
                    Text("↑↓ Navigate · Return Select · Esc Back")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if let reference = selectedResult?.reference {
                        Button("Change Status…") { showStatuses(reference) }
                            .disabled(store.statusChangeUnavailableReason(reference) != nil)
                    }
                    Button("Keyboard Shortcuts") { showsShortcuts = true }
                        .font(.caption)
                }.padding(12)
            }
        }
        .frame(minWidth: 480, idealWidth: 600, maxWidth: 640)
        .onAppear {
            showsShortcuts = initiallyShowsShortcuts
            statusTarget = initialStatusTarget
            selection = results.first?.id
        }
        .onChange(of: query) { _, _ in selection = results.first?.id }
        .onChange(of: scope) { _, _ in selection = results.first?.id }
        .onChange(of: results.map(\.id)) { old, new in
            selection = ItemKeyboardNavigation.reconciled(selection, old: old, new: new) ?? new.first
        }
        .onExitCommand(perform: back)
        .confirmationDialog(
            "Confirm Action",
            isPresented: Binding(
                get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }
            ), titleVisibility: .visible
        ) {
            if let action = confirmation {
                Button(action.title, role: .destructive) {
                    action.perform()
                    confirmation = nil
                }
            }
            Button("Cancel", role: .cancel) { confirmation = nil }
        }
    }

    private var resultList: some View {
        ScrollViewReader { proxy in
            List(selection: $selection) {
                ForEach(PaletteScope.allCases.filter { $0 != .all }) { group in
                    let groupResults = results.filter { $0.scope == group }
                    if !groupResults.isEmpty {
                        Section(group.title) {
                            ForEach(groupResults) { result in
                                HStack(spacing: 10) {
                                    Image(systemName: result.symbol).frame(width: 20).accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(result.title).lineLimit(1)
                                        Text(result.unavailable ?? result.subtitle).font(.caption)
                                            .foregroundStyle(.secondary).lineLimit(2)
                                    }
                                    Spacer(minLength: 8)
                                    if let shortcut = result.shortcut {
                                        Text(shortcut.label).font(.caption.monospaced()).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                                .opacity(result.unavailable == nil ? 1 : 0.55)
                                .contentShape(Rectangle())
                                .tag(result.id).id(result.id)
                                .onTapGesture {
                                    selection = result.id
                                    activate(result)
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityAddTraits(.isButton)
                                .accessibilityAction { activate(result) }
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
            .frame(height: 310)
            .overlay {
                if results.isEmpty {
                    ContentUnavailableView(
                        "No Results", systemImage: "magnifyingglass",
                        description: Text("Search commands, projects, or items already loaded on this Mac."))
                }
            }
            .onChange(of: selection) { _, id in if let id { proxy.scrollTo(id) } }
            .onKeyPress(.return) {
                submit()
                return .handled
            }
        }
    }

    private var shortcutHelp: some View {
        List {
            ForEach(WorkspaceShortcut.allCases) { shortcut in
                HStack {
                    Text(shortcut.title)
                    Spacer()
                    Text(shortcut.label).monospaced()
                }
            }
            Section("Navigation") {
                Text("Arrow keys navigate items. Return opens details. In selection mode, Space toggles selection.")
                Text("On a board, Left and Right move between visible columns. Tab moves between controls.")
                Text(
                    "Shortcuts apply to the active window. While editing text, typing and arrow keys stay in the editor."
                )
            }
        }.frame(height: 370)
    }

    private func move(_ offset: Int) {
        selection = ItemKeyboardNavigation.next(from: selection, in: results.map(\.id), offset: offset)
    }
    private func submit() { if let selectedResult { activate(selectedResult) } }
    private func activate(_ result: PaletteResult) {
        guard result.unavailable == nil else { return }
        if result.destructive { confirmation = result } else { result.perform() }
    }
    private func back() {
        if showsShortcuts {
            showsShortcuts = false
        } else if statusTarget != nil {
            statusTarget = nil
            query = ""
        } else {
            close()
        }
    }
    private func showStatuses(_ reference: ItemInspectorReference) {
        statusTarget = reference
        query = ""
    }
    private func targetTitle(_ reference: ItemInspectorReference) -> String {
        [store.item(for: reference)?.displayTitle, store.project(id: reference.projectID)?.title]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private func statusResults(_ reference: ItemInspectorReference) -> [PaletteResult] {
        guard let project = store.project(id: reference.projectID), let item = store.item(for: reference) else {
            return []
        }
        return project.statusOptions.map { status in
            PaletteResult(
                id: "status:" + status.id, title: status.name, subtitle: project.title,
                symbol: item.statusOptionId == status.id ? "checkmark.circle" : "circle", scope: .commands,
                unavailable: store.statusChangeUnavailableReason(reference)
            ) {
                execute { changeStatus(reference, status.id) }
            }
        }
    }

    private func layoutKeywords(_ layout: ProjectLayout) -> String {
        switch layout {
        case .board: "layout board kanban 布局 看板"
        case .table: "layout table 布局 表格"
        case .roadmap: "layout roadmap timeline 布局 路线图"
        }
    }

    private var contextIsCurrent: Bool {
        if let projectID = context?.projectID, projectID != store.selectedProjectId { return false }
        if let reference = context?.itemReference, store.item(for: reference) == nil { return false }
        return true
    }

    private var rootResults: [PaletteResult] {
        var values: [PaletteResult] = []
        func add(_ action: WorkspaceCommandContext.Action, contextual: Bool = false) {
            values.append(
                PaletteResult(
                    id: "command:" + action.id, title: action.title,
                    subtitle: String(localized: "Commands"), symbol: "command", scope: .commands,
                    keywords: action.keywords, shortcut: action.shortcut,
                    unavailable: contextual && !contextIsCurrent
                        ? String(localized: "The context changed. Reopen the command palette.")
                        : (action.isEnabled
                            ? nil
                            : (action.disabledReason ?? String(localized: "Unavailable in the current context."))),
                    destructive: action.isDestructive,
                    perform: {
                        execute {
                            guard !contextual || contextIsCurrent else {
                                reportError(String(localized: "The context changed. Reopen the command palette."))
                                return
                            }
                            action.perform()
                        }
                    }))
        }
        if let context {
            context.actions.forEach { add($0, contextual: true) }
            if let layout = context.projectLayout {
                for value in ProjectLayout.allCases {
                    add(
                        .init(
                            id: "layout:" + value.rawValue, title: value.title,
                            keywords: layoutKeywords(value), perform: { layout.wrappedValue = value }), contextual: true
                    )
                }
            }
            for action in context.moveSelection {
                var action = action
                action = .init(
                    id: action.id, title: String(localized: "Move Selected Items: \(action.title)"),
                    isEnabled: action.isEnabled, perform: action.perform)
                add(action, contextual: true)
            }
            if let reference = context.itemReference {
                let reason = store.statusChangeUnavailableReason(reference)
                values.append(
                    PaletteResult(
                        id: "change-status", title: String(localized: "Change Status…"),
                        subtitle: targetTitle(reference), symbol: "arrow.right.circle", scope: .commands,
                        keywords: "status move 状态 移动", unavailable: reason,
                        perform: { showStatuses(reference) }))
                if let item = store.item(for: reference) {
                    add(
                        .init(
                            id: "open-focused-item", title: String(localized: "Open Item Details"),
                            isEnabled: store.pendingCreationState(for: item.id) == nil,
                            perform: { navigation.openItem(reference) }))
                    if context.editItem == nil {
                        add(
                            .init(
                                id: "edit-focused-item", title: String(localized: "Edit Item…"),
                                isEnabled: item.contentId != nil && store.pendingCreationState(for: item.id) == nil,
                                keywords: "edit 编辑", perform: { editItem(reference) }), contextual: true)
                    }
                    if context.openInGitHub?.id != "open-item-in-github", let url = item.url.flatMap(URL.init(string:))
                    {
                        add(
                            .init(
                                id: "open-focused-item-in-github", title: String(localized: "Open Item in GitHub"),
                                keywords: "github 打开", perform: { NSWorkspace.shared.open(url) }), contextual: true)
                    }
                }
            }
        }
        if let roadmap {
            add(.init(id: "roadmap-today", title: String(localized: "Today"), perform: roadmap.today), contextual: true)
            add(.init(id: "roadmap-options", title: String(localized: "Roadmap Options"), perform: roadmap.showOptions), contextual: true)
            for zoom in RoadmapZoom.allCases {
                add(
                    .init(
                        id: "zoom:" + zoom.rawValue, title: zoom.title, keywords: "zoom 缩放",
                        perform: { roadmap.zoom.wrappedValue = zoom }), contextual: true)
            }
        }
        for filter in MyWorkFilter.allCases {
            add(
                .init(
                    id: "mywork:" + filter.rawValue, title: filter.title, keywords: "My Work 我的工作",
                    perform: { navigation.openMyWork(filter) }))
        }
        add(
            .init(
                id: "new-project", title: WorkspaceShortcut.newProject.title, shortcut: .newProject,
                perform: { openWindow(id: "new-project") }))
        add(
            .init(
                id: "quick-add", title: WorkspaceShortcut.addItem.title, shortcut: .addItem,
                perform: { openWindow(id: "quick-add") }))
        add(
            .init(
                id: "refresh-projects", title: WorkspaceShortcut.refreshProjects.title,
                isEnabled: !store.isLoading && !store.isCreatingProject, shortcut: .refreshProjects,
                perform: { Task { await store.loadProjects() } }))
        add(
            .init(
                id: "settings", title: String(localized: "Settings…"), keywords: "settings 设置",
                perform: { openSettings() }))
        values.append(
            .init(
                id: "shortcuts", title: String(localized: "Keyboard Shortcuts"), subtitle: "",
                symbol: "keyboard", scope: .commands, keywords: "keyboard shortcuts 快捷键",
                perform: { showsShortcuts = true }))
        let projects = store.allProjects.sorted {
            if ($0.id == store.selectedProjectId) != ($1.id == store.selectedProjectId) {
                return $0.id == store.selectedProjectId
            }
            return ($0.title, $0.id) < ($1.title, $1.id)
        }
        for project in projects {
            values.append(
                .init(
                    id: "project:" + project.id, title: project.title,
                    subtitle: project.owner.login, symbol: "rectangle.3.group", scope: .projects,
                    perform: { execute { navigation.openProject(project.id) } }))
            guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || scope == .items else { continue }
            let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let items =
                query.hasPrefix("@") || query.hasPrefix("#")
                ? project.items.matching(query, currentUserLogin: store.currentUserLogin) : project.items
            for item in items {
                let reference = ItemInspectorReference(projectID: project.id, itemID: item.id)
                let metadata = [
                    item.repositoryName, item.number.map { "#\($0)" }, project.title, item.status,
                    store.isProjectCached(project.id) ? String(localized: "Cached") : nil,
                ]
                .compactMap { $0 }.joined(separator: " · ")
                let pending = store.pendingCreationState(for: item.id) != nil
                values.append(
                    .init(
                        id: "item:" + project.id + ":" + item.id, title: item.displayTitle,
                        subtitle: metadata, symbol: "doc.text", scope: .items,
                        keywords: (query.hasPrefix("@") || query.hasPrefix("#") ? query : "") + " "
                            + item.assignees.map(\.login).joined(separator: " "),
                        unavailable: pending ? String(localized: "This item is still syncing.") : nil,
                        reference: reference,
                        perform: { execute { navigation.openItem(reference) } }))
            }
        }
        return values
    }
}
