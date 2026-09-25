import SwiftUI

struct ItemDetailView: View {
    @Bindable var store: ProjectStore
    let reference: ItemInspectorReference
    let allowsOpeningNewWindow: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @State private var isInspectorPresented = true
    @State private var inspectorWidth: CGFloat = 300
    @State private var pendingInspectorWidthUpdate: Task<Void, Never>?
    @State private var isArchiving = false
    @State private var operationErrorMessage: String?
    @State private var editingDetail: ProjectItemDetail?

    private static let inspectorMinimumWidth: CGFloat = 260
    private static let inspectorMaximumWidth: CGFloat = 360

    private var item: ProjectItem? { store.item(for: reference) }
    private var isRefreshing: Bool { store.isRefreshingItem(reference) }
    private var canEdit: Bool {
        store.canEditItemContent(reference) && !isRefreshing && !isArchiving && editingDetail == nil
            && item?.contentId.flatMap { store.pendingContentEdits[$0] } == nil
    }
    private var canArchive: Bool {
        item != nil && store.canEditProject(id: reference.projectID)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let operationErrorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(operationErrorMessage)
                        .font(.callout)
                        .textSelection(.enabled)
                    Spacer()
                    Button("Dismiss", systemImage: "xmark") {
                        self.operationErrorMessage = nil
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.orange.opacity(0.12))
            }

            Group {
                if item != nil, store.project(id: reference.projectID) != nil {
                    ItemDescriptionView(store: store, reference: reference)
                } else {
                    ContentUnavailableView("Item Unavailable", systemImage: "archivebox")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(
            minWidth: allowsOpeningNewWindow ? nil : 560,
            minHeight: 520
        )
        .navigationTitle(item?.displayTitle ?? String(localized: "Item"))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Edit", systemImage: "pencil", action: editItem)
                    .labelStyle(.iconOnly)
                    .disabled(!canEdit)
                    .help("Edit title and description")

                Menu {
                    Button("Refresh Item", systemImage: "arrow.clockwise", action: refreshItem)
                        .disabled(isRefreshing || isArchiving)
                    if itemURL != nil {
                        Button(action: openInGitHub) {
                            Label(openInGitHubTitle, systemImage: "arrow.up.right.square")
                        }
                    }
                    if allowsOpeningNewWindow {
                        Button("Open in New Window", systemImage: "macwindow", action: openInNewWindow)
                    }
                    if canArchive {
                        Divider()
                        Button(role: .destructive, action: archiveItem) {
                            Label("Archive from Project", systemImage: "archivebox")
                        }
                        .disabled(isRefreshing || isArchiving)
                    }
                } label: {
                    Label("More Actions", systemImage: "ellipsis.circle")
                }
                .help("More Actions")

                if isRefreshing || isArchiving {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel(isArchiving ? String(localized: "Archiving item") : String(localized: "Refreshing item"))
                }
            }

            if #available(macOS 26.0, *) {
                ToolbarSpacer(.flexible, placement: .primaryAction)
            }

            ToolbarItem(placement: .primaryAction) {
                Button(
                    isInspectorPresented ? String(localized: "Hide Inspector") : String(localized: "Show Inspector"),
                    systemImage: "sidebar.right", action: toggleInspector
                )
                .labelStyle(.iconOnly)
                .help(isInspectorPresented ? String(localized: "Hide Inspector") : String(localized: "Show Inspector"))
            }
        }
        .sheet(item: $editingDetail) { detail in
            let editor = ItemContentEditorView(store: store, reference: reference, detail: detail)
            if #available(macOS 15.0, *) {
                editor.presentationSizing(.fitted)
            } else {
                editor
            }
        }
        .inspector(isPresented: $isInspectorPresented) {
            ItemPropertiesView(
                store: store,
                reference: reference
            )
            .id(reference)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                scheduleInspectorWidthUpdate(width)
            }
            .inspectorColumnWidth(
                min: Self.inspectorMinimumWidth,
                ideal: inspectorWidth,
                max: Self.inspectorMaximumWidth
            )
        }
        .focusedValue(\.itemCommandScope, true)
        .focusedSceneValue(\.workspaceCommandContext, commandContext)
        .task(id: item.map { "\($0.contentId ?? ""):\($0.updatedAt ?? "")" }) {
            guard let item,
                  item.contentId.flatMap({ store.pendingContentEdits[$0] }) == nil else { return }
            await store.loadItemDetail(for: item)
        }
        .onDisappear {
            pendingInspectorWidthUpdate?.cancel()
        }
    }

    private var itemURL: URL? {
        item?.url.flatMap(URL.init(string:))
    }

    private var openInGitHubTitle: String {
        switch item?.contentType {
        case .issue: String(localized: "Open Issue")
        case .pullRequest: String(localized: "Open Pull Request")
        case .draftIssue: String(localized: "Open Draft Item")
        case .redacted, .none: String(localized: "Open in GitHub")
        }
    }

    private var commandContext: WorkspaceCommandContext {
        WorkspaceCommandContext(
            itemReference: reference,
            refresh: .init(
                id: "refresh-item",
                title: String(localized: "Refresh Item"),
                isEnabled: isRefreshing == false && isArchiving == false,
                perform: refreshItem
            ),
            editItem: .init(
                id: "edit-item",
                title: String(localized: "Edit Item…"),
                isEnabled: canEdit,
                perform: editItem
            ),
            toggleInspector: .init(
                id: "toggle-item-inspector",
                title: isInspectorPresented ? String(localized: "Hide Inspector") : String(localized: "Show Inspector"),
                perform: toggleInspector
            ),
            openInGitHub: itemURL.map { _ in
                .init(
                    id: "open-item-in-github",
                    title: openInGitHubTitle,
                    perform: openInGitHub
                )
            }
        )
    }

    private func openInGitHub() {
        guard let itemURL else { return }
        NSWorkspace.shared.open(itemURL)
    }

    private func openInNewWindow() {
        openWindow(id: "item-detail", value: reference)
    }

    private func editItem() {
        guard canEdit, let item,
              case .loaded(let detail) = store.itemDetailState(for: item) else { return }
        editingDetail = detail
    }

    private func refreshItem() {
        operationErrorMessage = nil
        Task {
            do {
                try await store.refreshItem(reference)
            } catch is CancellationError {
                return
            } catch {
                operationErrorMessage = String(localized: "Item refresh failed: \(error.localizedDescription)")
            }
        }
    }

    private func toggleInspector() {
        pendingInspectorWidthUpdate?.cancel()
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isInspectorPresented.toggle()
        }
    }

    private func scheduleInspectorWidthUpdate(_ width: CGFloat) {
        guard isInspectorPresented,
              Self.inspectorMinimumWidth...Self.inspectorMaximumWidth ~= width else { return }

        pendingInspectorWidthUpdate?.cancel()
        pendingInspectorWidthUpdate = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard Task.isCancelled == false, isInspectorPresented else { return }
            inspectorWidth = width
        }
    }

    private func archiveItem() {
        guard let item, isArchiving == false else { return }
        isArchiving = true
        operationErrorMessage = nil
        Task {
            do {
                try await store.archiveItem(item, in: reference.projectID)
                dismiss()
            } catch is CancellationError {
            } catch {
                operationErrorMessage = error.localizedDescription
            }
            isArchiving = false
        }
    }
}
