import SwiftUI

struct WorkspaceCommandContext {
    struct Action: Identifiable {
        let id: String
        let title: String
        var isEnabled = true
        var keywords = ""
        var disabledReason: String? = nil
        var shortcut: WorkspaceShortcut? = nil
        var isDestructive = false
        let perform: () -> Void
    }

    var projectID: String? = nil
    var find: Action? = nil
    var itemReference: ItemInspectorReference? = nil
    var projectLayout: Binding<ProjectLayout>? = nil
    let refresh: Action
    var addItem: Action? = nil
    var editItem: Action? = nil
    var toggleSelection: Action? = nil
    var toggleFollowing: Action? = nil
    var toggleInspector: Action? = nil
    var openInGitHub: Action? = nil
    var moveSelection: [Action] = []
    var archiveSelection: Action? = nil
    var stopFollowing: [Action] = []
    var itemActions: [Action] = []
}

private struct WorkspaceCommandContextKey: FocusedValueKey {
    typealias Value = WorkspaceCommandContext
}

extension FocusedValues {
    var workspaceCommandContext: WorkspaceCommandContext? {
        get { self[WorkspaceCommandContextKey.self] }
        set { self[WorkspaceCommandContextKey.self] = newValue }
    }
}


enum WorkspaceShortcut: String, CaseIterable, Identifiable {
    case palette, find, refresh, refreshProjects, newProject, addItem, inspector
    case status, assignees, labels, priority, edit, copyLink, createItem
    var id: Self { self }
    var key: KeyEquivalent {
        switch self {
        case .status: "s"
        case .assignees: "a"
        case .labels: "l"
        case .priority: "p"
        case .edit: "e"
        case .copyLink, .createItem: "c"
        case .palette: "k"
        case .find: "f"
        case .refresh, .refreshProjects: "r"
        case .newProject, .addItem: "n"
        case .inspector: "i"
        }
    }
    var modifiers: EventModifiers {
        switch self {
        case .status, .assignees, .labels, .priority, .edit, .createItem: []
        case .refreshProjects, .addItem, .copyLink: [.command, .shift]
        case .inspector: [.command, .option]
        default: .command
        }
    }
    var label: String {
        switch self {
        case .createItem: "C"
        case .status: "S"
        case .assignees: "A"
        case .labels: "L"
        case .priority: "P"
        case .edit: "E"
        case .copyLink: "⇧⌘C"
        case .palette: "⌘K"
        case .find: "⌘F"
        case .refresh: "⌘R"
        case .refreshProjects: "⇧⌘R"
        case .newProject: "⌘N"
        case .addItem: "⇧⌘N"
        case .inspector: "⌥⌘I"
        }
    }
    var title: String {
        switch self {
        case .createItem: String(localized: "Add Item…")
        case .status: String(localized: "Change Status…")
        case .assignees: String(localized: "Edit Assignees…")
        case .labels: String(localized: "Edit Labels…")
        case .priority: String(localized: "Change Priority…")
        case .edit: String(localized: "Edit Item…")
        case .copyLink: String(localized: "Copy Item Link")
        case .palette: String(localized: "Show Command Palette…")
        case .find: String(localized: "Find in Current View")
        case .refresh: String(localized: "Refresh")
        case .refreshProjects: String(localized: "Refresh Projects")
        case .newProject: String(localized: "New Project")
        case .addItem: String(localized: "Add to Project…")
        case .inspector: String(localized: "Toggle Inspector")
        }
    }
}

extension View {
    func workspaceShortcut(_ shortcut: WorkspaceShortcut) -> some View {
        keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
    }
}

struct CommandPaletteRequest {
    let show: () -> Void
    let showShortcuts: () -> Void
    let showStatus: () -> Void
    var itemActions: [WorkspaceCommandContext.Action] = []
}
private struct CommandPaletteRequestKey: FocusedValueKey {
    typealias Value = CommandPaletteRequest
}
extension FocusedValues {
    var commandPaletteRequest: CommandPaletteRequest? {
        get { self[CommandPaletteRequestKey.self] }
        set { self[CommandPaletteRequestKey.self] = newValue }
    }
}

extension WorkspaceCommandContext {
    var actions: [Action] {
        var refresh = refresh
        refresh.shortcut = .refresh
        refresh.keywords = "r refresh reload 刷新"
        var inspector = toggleInspector
        inspector?.shortcut = .inspector
        var create = addItem
        create?.shortcut = .createItem
        var edit = editItem
        edit?.shortcut = .edit
        var archive = archiveSelection
        archive?.isDestructive = true
        return [refresh, find, create, edit, toggleSelection, toggleFollowing, inspector, openInGitHub, archive]
            .compactMap { $0 }.map { action in
                var action = action
                let aliases: [String: String] = [
                    "add-item": "add create 新增 添加",
                    "edit-item": "edit 编辑",
                    "toggle-selection": "select 选择",
                    "toggle-following": "follow 关注 我的工作",
                    "toggle-item-inspector": "inspector 检查器",
                    "open-project-in-github": "github 打开项目",
                    "open-item-in-github": "github 打开条目",
                    "archive-selection": "archive 归档"
                ]
                action.keywords += " " + (aliases[action.id] ?? "")
                return action
            } + stopFollowing + itemActions
    }
}
