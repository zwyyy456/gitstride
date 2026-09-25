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
    @FocusedValue(\.itemCommandScope) private var itemCommandScope
    @State private var session: PaletteSession?
    @State private var window: NSWindow?
    @State private var previousResponder: NSResponder?
    @State private var pendingAction: (() -> Void)?
    @State private var errorMessage: String?
    @State private var editRequest: ItemInspectorReference?
    @State private var editor: PaletteEditor?
    @State private var propertyEditor: ItemPropertyRequest?

    func body(content: Content) -> some View {
        content
            .background(MenuBarWindowFinder(window: $window))
            .background(WorkspaceKeyHandler { event in
                guard itemCommandScope == true, session == nil, editor == nil, propertyEditor == nil, editRequest == nil else { return false }
                let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
                guard let action = keyboardActions.first(where: { action in
                    guard let shortcut = action.shortcut else { return false }
                    let expected: NSEvent.ModifierFlags = shortcut == .copyLink ? [.command, .shift] : []
                    return modifiers == expected && event.charactersIgnoringModifiers?.lowercased() == String(shortcut.key.character)
                }) else { return false }
                guard action.isEnabled else {
                    if action.shortcut == .priority {
                        errorMessage = action.disabledReason
                        return true
                    }
                    return false
                }
                action.perform()
                return true
            })
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
                    showStatus: { show(shortcuts: false, statusTarget: context?.itemReference) },
                    itemActions: itemActions
                )
            )
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
            .sheet(item: $propertyEditor) { request in
                ItemPropertyCommandView(store: store, request: request, close: { propertyEditor = nil }).id(request.id)
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

    private var keyboardActions: [WorkspaceCommandContext.Action] {
        var actions = itemActions
        if var create = context?.addItem {
            create.shortcut = .createItem
            actions.append(create)
        }
        return actions
    }

    private var itemActions: [WorkspaceCommandContext.Action] {
        guard let reference = context?.itemReference, store.item(for: reference) != nil else { return [] }
        return [WorkspaceShortcut.status, .assignees, .labels, .priority, .edit, .copyLink].map { shortcut in
            let reason = store.itemCommandUnavailableReason(shortcut, reference: reference)
            return .init(id: "item-" + shortcut.rawValue, title: shortcut.title,
                isEnabled: reason == nil, keywords: itemCommandKeywords(shortcut), disabledReason: reason,
                shortcut: shortcut, perform: {
                    guard store.itemCommandUnavailableReason(shortcut, reference: reference) == nil else { return }
                    switch shortcut {
                    case .status: show(shortcuts: false, statusTarget: reference)
                    case .edit: editRequest = reference
                    case .copyLink:
                        guard let url = store.item(for: reference)?.url else { return }
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url, forType: .string)
                    default: propertyEditor = ItemPropertyRequest(reference: reference, shortcut: shortcut)
                    }
                })
        }
    }

    private func openWorkspace() {
        if opensWorkspaceForNavigation { openWindow(id: "kanban-board") }
    }

    private func show(shortcuts: Bool, statusTarget: ItemInspectorReference? = nil) {
        guard session == nil, editRequest == nil, let window, window.attachedSheet == nil else { return }
        window.makeKeyAndOrderFront(nil)
        previousResponder = window.firstResponder
        var paletteContext = context
        paletteContext?.itemActions = itemActions.filter { $0.shortcut != .status && $0.shortcut != .edit }
        session = PaletteSession(context: paletteContext, roadmap: roadmap, shortcuts: shortcuts, statusTarget: statusTarget)
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

private enum PaletteGroup: Int, CaseIterable, Identifiable {
    case currentContext, itemActions, views, myWork, projects, items, application

    var id: Self { self }

    var title: String {
        switch self {
        case .currentContext: String(localized: "Current Project")
        case .itemActions: String(localized: "Item Actions")
        case .views: String(localized: "Switch View")
        case .myWork: String(localized: "Go to My Work")
        case .projects: String(localized: "Switch Project")
        case .items: String(localized: "Loaded Items")
        case .application: String(localized: "Application")
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
    var isCurrent = false
    var projectID: String? = nil
    var reference: ItemInspectorReference? = nil
    let perform: () -> Void

    var group: PaletteGroup {
        if scope == .projects { return .projects }
        if scope == .items { return .items }
        if id.hasPrefix("command:layout:") || id.hasPrefix("command:roadmap-")
            || id.hasPrefix("command:zoom:") { return .views }
        if id.hasPrefix("command:mywork:") { return .myWork }
        if id.hasPrefix("command:item-") || id.hasPrefix("command:move-selection-") {
            return .itemActions
        }
        switch id {
        case "change-status", "command:refresh-item", "command:edit-item", "command:toggle-item-inspector",
             "command:open-item-in-github", "command:open-focused-item", "command:edit-focused-item",
             "command:open-focused-item-in-github", "command:archive-selection":
            return .itemActions
        case "shortcuts", "command:settings", "command:new-project", "command:quick-add", "command:refresh-projects":
            return .application
        default:
            return .currentContext
        }
    }
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
    @State private var propertyTarget: ItemPropertyRequest?

    private var results: [PaletteResult] {
        let candidates = statusTarget.map(statusResults) ?? rootResults
        return candidates.enumerated().compactMap { index, result -> (Int, Int, PaletteResult)? in
            guard statusTarget != nil || scope == .all || result.scope == scope,
                let rank = CommandSearch.rank(
                    query, title: result.title, keywords: result.keywords + " " + result.subtitle)
            else { return nil }
            return (rank, index, result)
        }.sorted {
            return ($0.2.group.rawValue, $0.0, $0.1) < ($1.2.group.rawValue, $1.0, $1.1)
        }.map(\.2)
    }

    private var selectedResult: PaletteResult? { results.first { $0.id == selection } }

    var body: some View {
        Group {
            if let propertyTarget {
                ItemPropertyCommandView(store: store, request: propertyTarget,
                    back: { self.propertyTarget = nil }, close: close).id(propertyTarget.id)
            } else {
                VStack(spacing: 0) {
                    if showsShortcuts {
                        HStack {
                            Button("Back", systemImage: "chevron.left", action: back).labelStyle(.iconOnly)
                            Text("Keyboard Shortcuts").font(.headline)
                            Spacer()
                            Button("Close", systemImage: "xmark", action: close).labelStyle(.iconOnly)
                        }.padding(16)
                        shortcutHelp
                    } else {
                        HStack(spacing: 12) {
                            if statusTarget != nil {
                                Button("Back", systemImage: "chevron.left", action: back).labelStyle(.iconOnly)
                            }
                            CommandSearchField(text: $query,
                                prompt: statusTarget == nil ? String(localized: "Search commands, projects, and loaded items") : String(localized: "Search options"),
                                move: move, submit: submit, cancel: back)
                                .frame(height: 28)
                            if statusTarget == nil {
                                Menu {
                                    Picker("Search scope", selection: $scope) {
                                        ForEach(PaletteScope.allCases) { Text($0.title).tag($0) }
                                    }
                                } label: {
                                    Text(scope.title)
                                }
                                .menuStyle(.borderlessButton)
                                .fixedSize()
                                .accessibilityLabel("Search scope")
                                .accessibilityValue(scope.title)
                                .help("Search scope")
                            }
                        }.padding(16)
                        if let target = statusTarget {
                            Text(targetTitle(target)).font(.callout).foregroundStyle(.secondary)
                                .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16).padding(.bottom, 12)
                        }
                        Divider()
                        resultList
                        Divider()
                        HStack {
                            Text(statusTarget == nil
                                ? "↑↓ Navigate · Return Execute · Esc Close"
                                : "↑↓ Navigate · Return Execute · Esc Back")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            if let reference = selectedResult?.reference {
                                Button("Change Status…") { showStatuses(reference) }
                                    .disabled(store.statusChangeUnavailableReason(reference) != nil)
                            }
                            Button("Keyboard Shortcuts", systemImage: "keyboard") { showsShortcuts = true }
                                .labelStyle(.iconOnly).buttonStyle(.borderless)
                                .help("Keyboard Shortcuts")
                            Button("Close", action: close)
                                .buttonStyle(.borderless)
                        }.padding(12)
                    }
                }
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
        let visibleResults = results
        let visibleGroups = PaletteGroup.allCases.filter { group in
            visibleResults.contains { $0.group == group }
        }
        let showsGroupTitles = statusTarget == nil && (query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || visibleGroups.count > 1)
        return ScrollViewReader { proxy in
            List(selection: $selection) {
                ForEach(visibleGroups) { group in
                    let groupResults = visibleResults.filter { $0.group == group }
                    if showsGroupTitles {
                        Text(group == .currentContext && context?.projectID == nil
                            ? String(localized: "Current View") : group.title)
                            .font(.caption).foregroundStyle(.secondary)
                            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 2, trailing: 12))
                            .listRowSeparator(.hidden)
                            .selectionDisabled()
                            .accessibilityAddTraits(.isHeader)
                    }
                    ForEach(groupResults) { result in
                        HStack(spacing: 10) {
                            Group {
                                if let projectID = result.projectID {
                                    ProjectIcon(projectID: projectID)
                                } else {
                                    Image(systemName: result.symbol)
                                }
                            }
                            .frame(width: 20).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(result.title).lineLimit(1)
                                if let detail = result.unavailable ?? (result.subtitle.isEmpty ? nil : result.subtitle) {
                                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                            Spacer(minLength: 8)
                            if result.isCurrent {
                                Text("Current")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if let shortcut = result.shortcut {
                                Text(shortcut.label).font(.caption.monospaced()).foregroundStyle(.tertiary)
                                    .help("Shortcut outside the command palette")
                            }
                        }
                        .frame(minHeight: 32)
                        .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
                        .listRowSeparator(.hidden)
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
                Text("Arrow keys navigate items. Return opens details. X toggles selection. Shift–Up/Down extends selection; Command–A selects visible items. Escape clears selection. In selection mode, Space toggles selection.")
                Text("Item shortcuts work outside text fields and editors.").foregroundStyle(.secondary)
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

    private func layoutCommandTitle(_ layout: ProjectLayout) -> String {
        switch layout {
        case .board: String(localized: "Switch to Board View")
        case .table: String(localized: "Switch to Table View")
        case .roadmap: String(localized: "Switch to Roadmap View")
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

    private func commandSymbol(_ id: String) -> String {
        if id.hasPrefix("refresh") { return "arrow.clockwise" }
        if id == "layout:board" { return "rectangle.3.group" }
        if id == "layout:table" { return "tablecells" }
        if id == "layout:roadmap" { return "chart.bar.xaxis" }
        if id.hasPrefix("mywork:") { return "briefcase" }
        if id.hasPrefix("move-selection") { return "arrow.right.circle" }
        if id.hasPrefix("zoom:") { return "plus.magnifyingglass" }
        switch id {
        case "find": return "magnifyingglass"
        case "add-item", "quick-add", "new-project": return "plus"
        case "edit-item", "edit-focused-item": return "pencil"
        case "toggle-selection": return "checkmark.circle"
        case "toggle-following": return "briefcase"
        case "archive-selection": return "archivebox"
        case "item-assignees": return "person"
        case "item-labels": return "tag"
        case "item-priority": return "flag"
        case "item-copyLink": return "link"
        case "settings", "roadmap-options": return "slider.horizontal.3"
        case "roadmap-today": return "calendar"
        case "toggle-item-inspector": return "sidebar.right"
        case "open-focused-item": return "doc.text"
        default: return id.contains("github") ? "arrow.up.right.square" : "arrow.right"
        }
    }

    private var rootResults: [PaletteResult] {
        var values: [PaletteResult] = []
        func add(_ action: WorkspaceCommandContext.Action, contextual: Bool = false, isCurrent: Bool = false) {
            values.append(
                PaletteResult(
                    id: "command:" + action.id, title: action.title,
                    subtitle: "", symbol: commandSymbol(action.id), scope: .commands,
                    keywords: action.keywords, shortcut: action.shortcut,
                    unavailable: contextual && !contextIsCurrent
                        ? String(localized: "The context changed. Reopen the command palette.")
                        : (action.isEnabled
                            ? nil
                            : (action.disabledReason ?? String(localized: "Unavailable in the current context."))),
                    destructive: action.isDestructive, isCurrent: isCurrent,
                    perform: {
                        if let shortcut = action.shortcut, [.assignees, .labels, .priority].contains(shortcut),
                           let reference = context?.itemReference {
                            propertyTarget = ItemPropertyRequest(reference: reference, shortcut: shortcut)
                            return
                        }
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
                            id: "layout:" + value.rawValue, title: layoutCommandTitle(value),
                            keywords: layoutKeywords(value), perform: { layout.wrappedValue = value }),
                        contextual: true, isCurrent: layout.wrappedValue == value
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
                        keywords: "status move 状态 移动", shortcut: .status, unavailable: reason,
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
                                isEnabled: store.itemCommandUnavailableReason(.edit, reference: reference) == nil,
                                keywords: "edit 编辑", shortcut: .edit, perform: { editItem(reference) }), contextual: true)
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
        let showsProjectOwners = Set(projects.map { $0.owner.id }).count > 1
        for project in projects {
            values.append(
                .init(
                    id: "project:" + project.id, title: project.title,
                    subtitle: showsProjectOwners ? project.owner.login : "", symbol: "square.fill", scope: .projects,
                    keywords: project.owner.login, isCurrent: project.id == store.selectedProjectId,
                    projectID: project.id,
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

private struct ItemPropertyRequest: Identifiable {
    let reference: ItemInspectorReference
    let shortcut: WorkspaceShortcut
    var id: String { reference.projectID + ":" + reference.itemID + ":" + shortcut.rawValue }
}

private struct ItemPropertyCommandView: View {
    @Bindable var store: ProjectStore
    let request: ItemPropertyRequest
    var back: (() -> Void)? = nil
    let close: () -> Void
    @State private var query = ""
    @State private var selection: String?
    @State private var labels: [RepositoryLabel] = []
    @State private var users: [Assignee] = []
    @State private var isLoading = false
    @State private var isSearching = false
    @State private var isSaving = false
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var reloadAttempt = 0

    private enum Choice: Identifiable {
        case label(RepositoryLabel), user(Assignee), option(ProjectFieldOption), defaultPriority(ProjectPriority), clear
        var id: String {
            switch self {
            case .label(let value): "label:" + value.id
            case .user(let value): "user:" + value.id
            case .option(let value): "option:" + value.id
            case .defaultPriority(let value): "priority:" + value.rawValue
            case .clear: "clear"
            }
        }
        var title: String {
            switch self {
            case .label(let value): value.name
            case .user(let value): value.name ?? value.login
            case .option(let value): value.name
            case .defaultPriority(let value): value.title
            case .clear: String(localized: "Not Set")
            }
        }
        var subtitle: String {
            if case .user(let value) = self { return "@" + value.login }
            return ""
        }
    }

    private var item: ProjectItem? { store.item(for: request.reference) }
    private var field: ProjectField? {
        try? ProjectField.priorityField(in: store.project(id: request.reference.projectID)?.fields ?? [])
    }
    private var choices: [Choice] {
        let values: [Choice]
        switch request.shortcut {
        case .labels:
            let assigned = (item?.labels ?? []).map { RepositoryLabel(id: $0.id, name: $0.name) }
            values = (assigned + labels.filter { value in !assigned.contains { $0.id == value.id } }).map(Choice.label)
        case .assignees:
            let assigned = item?.assignees ?? []
            values = (assigned + users.filter { value in !assigned.contains { $0.id == value.id } }).map(Choice.user)
        case .priority:
            if let field {
                values = [.clear] + field.options.map(Choice.option)
            } else {
                values = [.clear] + ProjectPriority.allCases.map(Choice.defaultPriority)
            }
        default: values = []
        }
        return values.filter { CommandSearch.rank(query, title: $0.title, keywords: $0.subtitle) != nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if let back {
                    Button("Back", systemImage: "chevron.left", action: back).labelStyle(.iconOnly).disabled(isSaving)
                }
                Text(request.shortcut == .labels ? String(localized: "Labels")
                     : request.shortcut == .assignees ? String(localized: "Assignees") : String(localized: "Priority"))
                    .font(.headline)
                Spacer()
                Button("Close", systemImage: "xmark", action: close).labelStyle(.iconOnly).disabled(isSaving)
            }.padding(16)
            Text(item?.displayTitle ?? String(localized: "This item is no longer available."))
                .font(.callout).foregroundStyle(.secondary).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.bottom, 12)
            CommandSearchField(text: $query,
                prompt: request.shortcut == .assignees ? String(localized: "Search GitHub users") : String(localized: "Search options"),
                move: { selection = ItemKeyboardNavigation.next(from: selection, in: choices.map(\.id), offset: $0) },
                submit: submit, cancel: cancel)
                .frame(height: 28).padding(.horizontal, 16).padding(.bottom, 12).disabled(isSaving)
            if request.shortcut == .labels {
                Text("Check to add a label; uncheck to remove it. Changes save immediately.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.bottom, 12)
            }
            if request.shortcut == .priority && field == nil {
                Text("Choosing a priority will create a Priority field for this project.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.bottom, 12)
            }
            Divider()
            ScrollViewReader { proxy in
                List(selection: $selection) {
                    ForEach(choices) { choice in
                        HStack {
                            Image(systemName: isSelected(choice) ? "checkmark" : "circle")
                                .foregroundStyle(isSelected(choice) ? Color.accentColor : .secondary)
                                .frame(width: 18)
                            Text(choice.title)
                            if !choice.subtitle.isEmpty { Text(choice.subtitle).foregroundStyle(.secondary) }
                            Spacer()
                        }
                        .padding(.vertical, 4).contentShape(Rectangle()).tag(choice.id).id(choice.id)
                        .onTapGesture { selection = choice.id; apply(choice) }
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityValue(isSelected(choice) ? String(localized: "Selected") : String(localized: "Not selected"))
                        .accessibilityAction { apply(choice) }
                    }
                }
                .listStyle(.inset).frame(height: 260).disabled(isSaving)
                .onChange(of: selection) { _, id in if let id { proxy.scrollTo(id) } }
                .onKeyPress(.return) { submit(); return .handled }
                .overlay {
                    if choices.isEmpty && !isLoading && !isSearching && loadError == nil {
                        Text(request.shortcut == .assignees && query.isEmpty
                             ? String(localized: "Enter a GitHub login or name.") : String(localized: "No Results"))
                            .foregroundStyle(.secondary).allowsHitTesting(false)
                    }
                }
            }
            if isLoading || isSearching || isSaving {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(isSaving ? String(localized: "Saving field") : String(localized: "Loading options…"))
                }.padding(8)
            }
            if let error = saveError ?? loadError {
                HStack {
                    Text(error).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    if loadError != nil { Button("Retry") { reloadAttempt += 1 }.disabled(isSaving) }
                }.padding(12)
            }
            Divider()
            HStack {
                Text(request.shortcut == .priority
                     ? String(localized: "↑↓ Navigate · Return Apply · Esc Back")
                     : String(localized: "↑↓ Navigate · Return Toggle · Esc Back"))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Done", action: close).disabled(isSaving)
            }.padding(12)
        }
        .frame(minWidth: 480, idealWidth: 560, maxWidth: 640)
        .interactiveDismissDisabled(isSaving)
        .onExitCommand(perform: cancel)
        .onChange(of: choices.map(\.id), initial: true) { old, new in
            selection = ItemKeyboardNavigation.reconciled(selection, old: old, new: new) ?? new.first
        }
        .task(id: reloadAttempt) {
            guard request.shortcut == .labels else { return }
            isLoading = true
            loadError = nil
            defer { isLoading = false }
            do { labels = try await store.repositoryLabels(for: request.reference) }
            catch is CancellationError { return }
            catch { loadError = error.localizedDescription }
        }
        .task(id: "\(query):\(reloadAttempt)") {
            guard request.shortcut == .assignees else { return }
            users = []
            loadError = nil
            let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { isSearching = false; return }
            isSearching = true
            do {
                try await Task.sleep(for: .milliseconds(250))
                let results = try await store.searchUsers(query: query)
                try Task.checkCancellation()
                users = results
                isSearching = false
            } catch is CancellationError { return }
            catch { if !Task.isCancelled { loadError = error.localizedDescription; isSearching = false } }
        }
    }

    private func isSelected(_ choice: Choice) -> Bool {
        switch choice {
        case .label(let value): item?.labels.contains { $0.id == value.id } == true
        case .user(let value): item?.assignees.contains { $0.id == value.id } == true
        case .option(let value):
            if let field, case .singleSelect(let id, _) = item?.fieldValues[field.id] { id == value.id } else { false }
        case .defaultPriority: false
        case .clear: field.map { item?.fieldValues[$0.id] == nil } ?? true
        }
    }
    private func cancel() { if !isSaving { (back ?? close)() } }
    private func submit() { if let choice = choices.first(where: { $0.id == selection }) { apply(choice) } }
    private func apply(_ choice: Choice) {
        guard !isSaving else { return }
        if let reason = store.itemCommandUnavailableReason(request.shortcut, reference: request.reference) {
            saveError = reason
            return
        }
        guard let item else { return }
        let remove = isSelected(choice)
        isSaving = true
        saveError = nil
        Task { @MainActor in
            defer { isSaving = false }
            do {
                switch choice {
                case .label(let label):
                    if remove { try await store.removeLabel(from: item, in: request.reference.projectID, name: label.name) }
                    else { try await store.addLabel(to: item, in: request.reference.projectID, name: label.name) }
                case .user(let user):
                    if remove { try await store.removeAssignee(from: item, in: request.reference.projectID, user: user) }
                    else { try await store.addAssignee(to: item, in: request.reference.projectID, user: user) }
                case .option(let option):
                    guard let field else { throw ProjectStoreError.itemUnavailable }
                    try await store.updateField(on: item, in: request.reference.projectID, field: field,
                                                value: .singleSelect(optionId: option.id, name: option.name))
                    close()
                case .defaultPriority(let priority):
                    try await store.setDefaultPriority(priority, on: item, in: request.reference.projectID)
                    close()
                case .clear:
                    if let field {
                        try await store.updateField(on: item, in: request.reference.projectID, field: field, value: nil)
                    }
                    close()
                }
            } catch is CancellationError { return }
            catch { saveError = error.localizedDescription }
        }
    }
}

private func itemCommandKeywords(_ shortcut: WorkspaceShortcut) -> String {
    switch shortcut {
    case .status: "status 状态"
    case .assignees: "assignee assign 负责人 指派"
    case .labels: "label 标签"
    case .priority: "priority 优先级"
    case .copyLink: "copy link url 复制 链接"
    case .edit: "edit 编辑"
    default: ""
    }
}

private extension ProjectStore {
    func itemCommandUnavailableReason(_ shortcut: WorkspaceShortcut, reference: ItemInspectorReference) -> String? {
        guard let item = item(for: reference) else { return String(localized: "This item is no longer available.") }
        if shortcut == .copyLink { return item.url == nil ? String(localized: "This item has no link.") : nil }
        if shortcut == .status { return statusChangeUnavailableReason(reference) }
        if shortcut == .edit {
            guard item.contentId != nil, pendingCreationState(for: item.id) == nil else {
                return String(localized: "This item is read-only.")
            }
            // The editor request loads details before checking content permissions. Browsing a
            // board must not require opening details once just to enable the edit command.
            if case .loaded = itemDetailState(for: item), !canEditItemContent(reference) {
                return String(localized: "This item is read-only.")
            }
            return nil
        }
        guard canEditProject(id: reference.projectID), pendingCreationState(for: item.id) == nil else {
            return String(localized: "This item is read-only.")
        }
        if shortcut == .priority {
            do {
                _ = try ProjectField.priorityField(in: project(id: reference.projectID)?.fields ?? [])
                return nil
            } catch { return error.localizedDescription }
        }
        if shortcut == .labels, item.contentType != .issue {
            return String(localized: "Labels are available for issues.")
        }
        if shortcut == .assignees, item.contentType != .issue && item.contentType != .pullRequest {
            return String(localized: "Assignees are available for issues and pull requests.")
        }
        return nil
    }
}
