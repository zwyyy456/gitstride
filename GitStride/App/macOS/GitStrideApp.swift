import SwiftUI

// Environment key for dismissing menubar
private struct DismissMenuBarKey: EnvironmentKey {
    static let defaultValue: @MainActor @Sendable () -> Void = {}
}

extension EnvironmentValues {
    var dismissMenuBar: @MainActor @Sendable () -> Void {
        get { self[DismissMenuBarKey.self] }
        set { self[DismissMenuBarKey.self] = newValue }
    }
}

@main
struct GitStrideApp: App {
    @State private var model = GitStrideModel()
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var isShowingWelcome = false
    @State private var menuBarWindow: NSWindow?
    @State private var requestsProjectBoard = false
    @State private var requestsCommandPalette = false
    @State private var requestedMyWorkFilter: MyWorkFilter?
    @State private var requestedItemReference: ItemInspectorReference?
    @State private var requestedContentEdit: ItemContentEditRequest?

    init() {
        #if !APP_STORE && canImport(Sparkle)
        _ = UpdateController.shared
        #endif
        #if APP_STORE
        _ = SupportPurchaseModel.shared
        #endif
    }

    var body: some Scene {
        Window("GitStride", id: "kanban-board") {
            MainWorkspaceView(
                model: model,
                requestedItemReference: $requestedItemReference,
                requestedContentEdit: $requestedContentEdit,
                requestsProjectBoard: $requestsProjectBoard,
                requestsCommandPalette: $requestsCommandPalette,
                requestedMyWorkFilter: $requestedMyWorkFilter
            )
                .id(model.connectionID)
                .sheet(isPresented: $isShowingWelcome) {
                    WelcomeView()
                }
                .onAppear {
                    if !hasSeenWelcome {
                        let defaults = UserDefaults.standard
                        let hasAccountSetup = defaults.object(forKey: "githubAuthenticationMethod") != nil
                            || defaults.object(forKey: "githubSignedOut") != nil
                            || defaults.object(forKey: "selectedOwnerId") != nil
                        isShowingWelcome = !hasAccountSetup && model.projectStore.currentAccount == nil
                        hasSeenWelcome = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
        }
        .defaultSize(width: 1200, height: 800)
        .windowResizability(.contentMinSize)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            GitStrideCommands(store: model.projectStore) {
                isShowingWelcome = true
            }
        }

        MenuBarExtra {
            MenuBarPopoverView(
                store: model.projectStore,
                requestedItemReference: $requestedItemReference,
                requestsCommandPalette: $requestsCommandPalette
            )
                .id(model.connectionID)
                .environment(\.dismissMenuBar) { @MainActor @Sendable in
                    menuBarWindow?.close()
                }
                .background(MenuBarWindowFinder(window: $menuBarWindow))
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "rectangle.3.group")
                if model.attentionCount > 0 {
                    Text(model.attentionCount > 9 ? "9+" : "\(model.attentionCount)")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(2)
                        .background(.red)
                        .clipShape(Circle())
                        .offset(x: 5, y: -4)
                }
            }
                .task {
                    await model.start()
                    let actions = await NotificationService.shared.actions()
                    for await action in actions {
                        if let url = await model.handleNotificationAction(action) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
        }
        .menuBarExtraStyle(.window)

        WindowGroup("Item Details", id: "item-detail", for: ItemInspectorReference.self) { $reference in
            NavigationStack {
                if let reference {
                    ItemDetailWindowView(store: model.projectStore, reference: reference)
                } else {
                    ContentUnavailableView("Item Unavailable", systemImage: "archivebox")
                }
            }
            .commandPalette(store: model.projectStore, opensWorkspaceForNavigation: true, navigation: CommandPaletteNavigation(
                openProject: { id in
                    guard let project = model.projectStore.project(id: id) else { return }
                    Task {
                        await model.openProject(project)
                        requestsProjectBoard = true
                    }
                },
                openItem: { reference in
                    requestedItemReference = reference
                },
                openMyWork: { filter in
                    requestedMyWorkFilter = filter
                },
                editItem: { reference, detail in
                    requestedContentEdit = ItemContentEditRequest(reference: reference, detail: detail)
                }
            ))
            .id(model.connectionID)
        }
        .defaultSize(width: 980, height: 720)
        .windowResizability(.contentMinSize)

        WindowGroup("Add to Project", id: "quick-add", for: String.self) { $quickEntry in
            QuickAddWindow(model: model, quickEntry: quickEntry).id(model.connectionID)
        } defaultValue: {
            ""
        }
        .defaultSize(
            width: AddProjectItemView.windowDefaultSize.width,
            height: AddProjectItemView.windowDefaultSize.height
        )
        .windowResizability(.contentMinSize)
        .commandsRemoved()

        Window("New Project", id: "new-project") {
            CreateProjectView(store: model.projectStore) { requestsProjectBoard = true }
                .id(model.connectionID)
        }
        .defaultSize(width: 480, height: 240)
        .windowResizability(.contentSize)
        .commandsRemoved()

        WindowGroup("Link Repository", id: "link-project-repository", for: String.self) { $projectID in
            if let projectID {
                LinkProjectRepositoryView(store: model.projectStore, projectID: projectID)
                    .id(model.connectionID)
            }
        }
        .defaultSize(width: 480, height: 260)
        .windowResizability(.contentSize)
        .commandsRemoved()

        WindowGroup("Delete Project", id: "delete-project", for: String.self) { $projectID in
            if let projectID {
                DeleteProjectView(model: model, projectID: projectID)
                    .id(model.connectionID)
            }
        }
        .defaultSize(width: 480, height: 300)
        .windowResizability(.contentSize)
        .commandsRemoved()

        Window("About GitStride", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .commandsRemoved()

        Settings {
            SettingsView(model: model)
        }
        .windowResizability(.contentSize)
    }

}

private struct GitStrideCommands: Commands {
    @Bindable var store: ProjectStore
    let showWelcome: () -> Void
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.workspaceCommandContext) private var workspaceCommandContext
    @FocusedValue(\.roadmapCommands) private var roadmapCommands
    @FocusedValue(\.commandPaletteRequest) private var paletteRequest

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About GitStride") {
                openWindow(id: "about")
            }
        }

        CommandGroup(after: .help) {
            Button("Welcome to GitStride…") {
                openWindow(id: "kanban-board")
                showWelcome()
                NSApp.activate(ignoringOtherApps: true)
            }
        }

        CommandGroup(after: .sidebar) {
            if let toggleInspector = workspaceCommandContext?.toggleInspector {
                Button(toggleInspector.title, action: toggleInspector.perform)
                    .workspaceShortcut(.inspector)
                    .disabled(toggleInspector.isEnabled == false)
            }
        }

        CommandGroup(after: .newItem) {
            NewProjectButton()
                .workspaceShortcut(.newProject)
            Button("Add to Project…") {
                openWindow(id: "quick-add")
            }
            .workspaceShortcut(.addItem)

            Divider()

            RefreshProjectsButton(store: store)
                .workspaceShortcut(.refreshProjects)
        }

        CommandMenu("Workspace") {
            Button("Show Command Palette…") { paletteRequest?.show() }
                .workspaceShortcut(.palette)
                .disabled(paletteRequest == nil)
            Button("Keyboard Shortcuts") { paletteRequest?.showShortcuts() }
                .disabled(paletteRequest == nil)
            Button("Find in Current View") { workspaceCommandContext?.find?.perform() }
                .workspaceShortcut(.find)
                .disabled(workspaceCommandContext?.find == nil)
            ForEach(paletteRequest?.itemActions ?? []) { action in
                // Single-letter actions are dispatched by the window-local handler, never by text editors.
                Button(action.title + "    " + (action.shortcut?.label ?? ""), action: action.perform)
                    .disabled(!action.isEnabled)
            }
            Divider()
            if let layout = workspaceCommandContext?.projectLayout {
                Picker("Project Layout", selection: layout) {
                    ForEach(ProjectLayout.allCases, id: \.self) { value in
                        Text(value.title).tag(value)
                    }
                }
                Divider()
            }

            if let roadmap = roadmapCommands {
                Menu("Roadmap") {
                    Button("Today", action: roadmap.today)
                    Picker("Timeline Zoom", selection: roadmap.zoom) {
                        ForEach(RoadmapZoom.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Button("Roadmap Options", action: roadmap.showOptions)
                }
                Divider()
            }

            if let addItem = workspaceCommandContext?.addItem {
                Button(addItem.title, action: addItem.perform)
                    .disabled(addItem.isEnabled == false)
            }

            if let toggleSelection = workspaceCommandContext?.toggleSelection {
                Button(toggleSelection.title, action: toggleSelection.perform)
                    .disabled(toggleSelection.isEnabled == false)
            }

            if let moveSelection = workspaceCommandContext?.moveSelection,
               moveSelection.isEmpty == false {
                Menu("Move To") {
                    ForEach(moveSelection) { action in
                        Button(action.title, action: action.perform)
                            .disabled(action.isEnabled == false)
                    }
                }
            }

            if let archiveSelection = workspaceCommandContext?.archiveSelection {
                Button(archiveSelection.title, role: .destructive, action: archiveSelection.perform)
                    .disabled(archiveSelection.isEnabled == false)
            }

            if let toggleFollowing = workspaceCommandContext?.toggleFollowing {
                Button(toggleFollowing.title, action: toggleFollowing.perform)
                    .disabled(toggleFollowing.isEnabled == false)
            }

            if let stopFollowing = workspaceCommandContext?.stopFollowing,
               stopFollowing.isEmpty == false {
                Menu("Followed Projects") {
                    ForEach(stopFollowing) { action in
                        Button(action.title, role: .destructive, action: action.perform)
                            .disabled(action.isEnabled == false)
                    }
                }
            }

            Divider()

            Button(workspaceCommandContext?.refresh.title ?? String(localized: "Refresh")) {
                workspaceCommandContext?.refresh.perform()
            }
            .workspaceShortcut(.refresh)
            .disabled(workspaceCommandContext?.refresh.isEnabled != true)

            if let openInGitHub = workspaceCommandContext?.openInGitHub {
                Button(openInGitHub.title, action: openInGitHub.perform)
                    .disabled(openInGitHub.isEnabled == false)
            }
        }
    }
}

// Helper view to capture the NSWindow reference
struct MenuBarWindowFinder: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            self.window = view.window
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if self.window == nil {
                self.window = nsView.window
            }
        }
    }
}
