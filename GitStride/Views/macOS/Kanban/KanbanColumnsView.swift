import SwiftUI

struct KanbanColumnsView: View {
    let store: ProjectStore
    let project: Project
    let items: [ProjectItem]
    let statuses: [StatusOption]
    let preferenceID: String
    let emptyMessage: String
    @Binding var isSelecting: Bool
    @Binding var selectedItemIDs: Set<String>
    @Binding var currentItemID: String?
    let showInspector: (ItemInspectorReference) -> Void
    let reportError: (Error) -> Void
    @State private var showsKeyboardFocus = false
    @FocusState private var boardFocused: Bool
    @FocusedValue(\.itemCommandScope) private var itemCommandScope

    private static let minimumColumnWidth: CGFloat = 260
    private static let idealOverflowColumnWidth: CGFloat = 280
    private static let maximumColumnWidth: CGFloat = 420
    private static let columnSpacing: CGFloat = 8

    private struct Column: Identifiable {
        let status: StatusOption?
        var id: String? { status?.id }
    }

    var body: some View {
        let showsRepository = Set(project.items.compactMap(\.repositoryName)).count > 1
        let cardFields = project.fields.filter { $0.isEditable && $0.id != project.statusField?.id }
        let knownStatusIDs = Set(project.statusOptions.map(\.id))
        let includesNoStatus = project.items.contains { hasNoStatus($0, knownIDs: knownStatusIDs) }
        let columns = statuses.map { Column(status: $0) } + (includesNoStatus ? [Column(status: nil)] : [])
        let itemColumns = columns.map { column in
            items.filter { item in
                (column.status.map { item.statusOptionId == $0.id } ?? hasNoStatus(item, knownIDs: knownStatusIDs))
                    && store.pendingCreationState(for: item.id) == nil
            }.map(\.id)
        }
        GeometryReader { geometry in
            let columnCount = max(columns.count, 1)
            let totalSpacing = CGFloat(columnCount - 1) * Self.columnSpacing
            let fittingWidth = (geometry.size.width - 32 - totalSpacing) / CGFloat(columnCount)
            let columnWidth = fittingWidth >= Self.minimumColumnWidth
                ? min(Self.maximumColumnWidth, fittingWidth) : Self.idealOverflowColumnWidth

            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: Self.columnSpacing) {
                        ForEach(columns) { column in
                            let status = column.status
                            let columnItems = items.filter { item in
                                status.map { item.statusOptionId == $0.id } ?? hasNoStatus(item, knownIDs: knownStatusIDs)
                            }
                            KanbanColumn(
                                projectID: project.id, preferenceID: preferenceID,
                                showsRepository: showsRepository, availableFields: cardFields,
                                status: status, items: columnItems, emptyMessage: emptyMessage,
                                allStatuses: project.statusOptions, store: store,
                                isSelecting: isSelecting, selectedItemIDs: $selectedItemIDs,
                                currentItemID: $currentItemID, showsKeyboardFocus: $showsKeyboardFocus,
                                moveAcross: { offset in
                                    currentItemID = ItemKeyboardNavigation.horizontal(from: currentItemID, columns: itemColumns, offset: offset)
                                },
                                showInspector: showInspector, reportError: reportError
                            )
                            .frame(width: columnWidth, height: geometry.size.height - 32)
                            .id(column.id ?? "no-status")
                        }
                    }
                    .padding(16)
                }
                .onChange(of: currentItemID) { _, id in
                    if let index = itemColumns.firstIndex(where: { $0.contains(id ?? "") }) {
                        proxy.scrollTo(columns[index].id ?? "no-status")
                    }
                }
            }
            .id([preferenceID, includesNoStatus ? "includes-no-status" : "statuses-only"] + statuses.map(\.id))
        }
        .background {
            Color.clear.contentShape(Rectangle()).onTapGesture { boardFocused = true }
        }
        .focusable().focusEffectDisabled().focused($boardFocused)
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
            guard boardFocused, !KeyboardInput.isEditingText, press.modifiers.isEmpty else { return .ignored }
            showsKeyboardFocus = true
            if press.key == .leftArrow || press.key == .rightArrow {
                currentItemID = ItemKeyboardNavigation.horizontal(from: currentItemID, columns: itemColumns,
                    offset: press.key == .leftArrow ? -1 : 1)
            } else {
                let column = itemColumns.first { $0.contains(currentItemID ?? "") } ?? itemColumns.first(where: { !$0.isEmpty }) ?? []
                currentItemID = ItemKeyboardNavigation.next(from: currentItemID, in: column,
                    offset: press.key == .upArrow ? -1 : 1)
            }
            return .handled
        }
        .background(WorkspaceKeyHandler(onPointerDown: { showsKeyboardFocus = false }) { event in
            if itemCommandScope == true { showsKeyboardFocus = true }
            return false
        })
        .onAppear {
            if let event = NSApp.currentEvent, [.leftMouseDown, .leftMouseUp].contains(event.type) {
                showsKeyboardFocus = false
            }
        }
        .itemSelectionKeyboard(ids: itemColumns.flatMap { $0 }, current: $currentItemID,
            selected: $selectedItemIDs, isSelecting: $isSelecting)
        .onChange(of: itemColumns.flatMap { $0 }) { old, new in
            currentItemID = ItemKeyboardNavigation.reconciled(currentItemID, old: old, new: new)
        }
    }

    private func hasNoStatus(_ item: ProjectItem, knownIDs: Set<String>) -> Bool {
        item.statusOptionId.map { !knownIDs.contains($0) } ?? true
    }
}
