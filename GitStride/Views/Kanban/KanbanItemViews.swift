import SwiftUI

struct KanbanColumn: View {
    let projectID: String
    let preferenceID: String
    let showsRepository: Bool
    let availableFields: [ProjectField]
    let status: StatusOption?
    let items: [ProjectItem]
    let emptyMessage: String
    let allStatuses: [StatusOption]
    @Bindable var store: ProjectStore
    let isSelecting: Bool
    @Binding var selectedItemIDs: Set<String>
    @Binding var currentItemID: String?
    @Binding var showsKeyboardFocus: Bool
    let moveAcross: (Int) -> Void
    @FocusState private var keyboardItemID: String?
    let showInspector: (ItemInspectorReference) -> Void
    let reportError: (Error) -> Void

    @State private var isTargeted = false

    var statusName: String {
        status?.name ?? String(localized: "No Status")
    }

    var statusColor: Color {
        status?.swiftUIColor ?? .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)

                Text(statusName)
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                Text("\(items.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            // Cards
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 8) {
                        if items.isEmpty {
                            Text(emptyMessage)
                                .font(.callout)
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                        } else {
                            ForEach(items) { item in
                                Group {
                                    if isSelecting {
                                        KanbanCard(
                                            projectID: projectID,
                                            preferenceID: preferenceID,
                                            showsRepository: showsRepository,
                                            availableFields: availableFields,
                                            item: item,
                                            allStatuses: allStatuses,
                                            store: store,
                                            isSelecting: true,
                                            isSelected: selectedItemIDs.contains(item.id)
                                        ) {
                                            toggleSelection(item.id)
                                        } showInspector: {
                                            showInspector(
                                                ItemInspectorReference(projectID: projectID, itemID: item.id)
                                            )
                                        } reportError: { reportError($0) }
                                    } else if store.pendingCreationState(for: item.id) != nil {
                                        KanbanCard(
                                            projectID: projectID,
                                            preferenceID: preferenceID,
                                            showsRepository: showsRepository,
                                            availableFields: availableFields,
                                            item: item,
                                            allStatuses: allStatuses,
                                            store: store,
                                            isSelecting: false,
                                            isSelected: false,
                                            onSelect: {},
                                            showInspector: {},
                                            reportError: reportError
                                        )
                                    } else {
                                        KanbanCard(
                                            projectID: projectID,
                                            preferenceID: preferenceID,
                                            showsRepository: showsRepository,
                                            availableFields: availableFields,
                                            item: item,
                                            allStatuses: allStatuses,
                                            store: store,
                                            isSelecting: false,
                                            isSelected: false,
                                            onSelect: {},
                                            showInspector: {
                                                showInspector(
                                                    ItemInspectorReference(projectID: projectID, itemID: item.id)
                                                )
                                            },
                                            reportError: reportError
                                        )
                                        .draggable(item.id) {
                                            KanbanCardPreview(item: item)
                                        }
                                    }
                                }
                                .focusable(store.pendingCreationState(for: item.id) == nil)
                                .focusEffectDisabled()
                                .focused($keyboardItemID, equals: item.id)
                                .id(item.id)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(showsKeyboardFocus && keyboardItemID == item.id ? Color.accentColor : .clear, lineWidth: 2)
                                        .allowsHitTesting(false)
                                }
                                .onKeyPress(.return) {
                                    guard !KeyboardInput.isEditingText, !isSelecting else { return .ignored }
                                    showInspector(ItemInspectorReference(projectID: projectID, itemID: item.id))
                                    return .handled
                                }
                                .onKeyPress(.space) {
                                    guard !KeyboardInput.isEditingText, isSelecting else { return .ignored }
                                    toggleSelection(item.id)
                                    return .handled
                                }
                            }
                        }
                    }
                    .padding(8)
                }
                .onChange(of: currentItemID, initial: true) { _, id in
                    if let id, items.contains(where: { $0.id == id }) {
                        proxy.scrollTo(id)
                        if showsKeyboardFocus && !KeyboardInput.isEditingText { keyboardItemID = id }
                    } else { keyboardItemID = nil }
                }
            }
        }
        .onChange(of: showsKeyboardFocus) { _, visible in
            if visible, let currentItemID, items.contains(where: { $0.id == currentItemID }), !KeyboardInput.isEditingText {
                keyboardItemID = currentItemID
            }
        }
        .onChange(of: keyboardItemID) { _, id in
            if let id {
                currentItemID = id
                if NSApp.currentEvent?.type == .keyDown { showsKeyboardFocus = true }
            }
        }
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
            guard !KeyboardInput.isEditingText, keyboardItemID != nil else { return .ignored }
            if press.key == .leftArrow || press.key == .rightArrow {
                moveAcross(press.key == .leftArrow ? -1 : 1)
            } else {
                currentItemID = ItemKeyboardNavigation.next(from: currentItemID,
                    in: items.filter { store.pendingCreationState(for: $0.id) == nil }.map(\.id),
                    offset: press.key == .upArrow ? -1 : 1)
            }
            return .handled
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isTargeted ? statusColor.opacity(0.8) : Color.clear, lineWidth: 2)
        )
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
        .dropDestination(for: String.self) { droppedItems, _ in
            guard let itemId = droppedItems.first,
                  let targetStatus = status,
                  isSelecting == false,
                  store.canEditProject(id: projectID) else { return false }

            // Find the item being dropped from all project items
            if let project = store.project(id: projectID),
               let item = project.items.first(where: { $0.id == itemId }) {
                // Only move if status is different
                if item.status != targetStatus.name {
                    Task {
                        do {
                            try await store.moveItem(item, toStatus: targetStatus, in: projectID)
                        } catch {
                            reportError(error)
                        }
                    }
                }
            }
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
    }

    private func toggleSelection(_ itemID: String) {
        guard store.pendingCreationState(for: itemID) == nil else { return }
        if selectedItemIDs.contains(itemID) {
            selectedItemIDs.remove(itemID)
        } else {
            selectedItemIDs.insert(itemID)
        }
    }
}

// MARK: - Kanban Card

struct KanbanCard: View {
    let projectID: String
    let preferenceID: String
    let showsRepository: Bool
    let availableFields: [ProjectField]
    let item: ProjectItem
    let allStatuses: [StatusOption]
    @Bindable var store: ProjectStore
    let isSelecting: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    let showInspector: () -> Void
    let reportError: (Error) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        Button(action: activateCard) {
            VStack(alignment: .leading, spacing: 4) {
                KanbanCardContent(item: item, showsRepository: showsRepository,
                                  availableFields: availableFields, preferenceID: preferenceID)
                if let syncState = store.pendingSyncState(for: item) {
                    Label(syncTitle(for: syncState), systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
                .padding(.trailing, isSelecting ? 20 : 0)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(cardBackground)
                .overlay(cardBorder)
                .overlay(alignment: .topTrailing) {
                    if isSelecting {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                            .padding(8)
                    }
                }
        }
            .buttonStyle(.plain)
            .disabled(store.pendingCreationState(for: item.id) != nil)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isHovered)
            .onHover { isHovered = $0 }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(accessibilityValue)
            .accessibilityHint(isSelecting ? String(localized: "Toggles selection") : String(localized: "Shows details"))
        .contextMenu {
            if store.pendingCreationState(for: item.id) == nil {
            KanbanCardContextMenu(
                projectID: projectID,
                item: item,
                allStatuses: allStatuses,
                store: store,
                showDeleteConfirmation: $showDeleteConfirmation,
                showInspector: showInspector,
                reportError: reportError
            )
            }
        }
        .confirmationDialog(
            removalConfirmationTitle,
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                Task {
                    do {
                        try await store.deleteItem(item, from: projectID)
                    } catch {
                        reportError(error)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Archive is recommended when you may need the item again.")
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovered ? Color.accentColor.opacity(0.06) : Color.clear)
            }
            .shadow(
                color: .black.opacity(0.06),
                radius: 1,
                x: 0,
                y: 1
            )
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 10)
            .stroke(
                isSelected
                    ? Color.accentColor
                    : (isHovered
                        ? Color.accentColor.opacity(0.45)
                        : Color(nsColor: .separatorColor)),
                lineWidth: isSelected ? 2 : 1
            )
    }

    private var accessibilityValue: String {
        guard isSelecting else { return "" }
        return isSelected ? String(localized: "Selected") : String(localized: "Not selected")
    }

    private var removalConfirmationTitle: String {
        String(localized: "Remove \"\(item.displayTitle)\" from the project?")
    }

    private var accessibilityLabel: String {
        var parts = [item.displayTitle]
        if let number = item.number {
            parts.append(String(localized: "Number \(number)"))
        }
        if let status = item.status {
            parts.append(String(localized: "Status \(status)"))
        }
        if let repository = item.repositoryName { parts.append(repository) }
        if !item.isWorkComplete && item.signals.blockedByCount > 0 {
            parts.append(String(localized: "Blocked by \(item.signals.blockedByCount) issues"))
        }
        if !item.assignees.isEmpty { parts.append(String(localized: "Assigned to \(item.assignees.map(\.login).joined(separator: ", "))")) }
        return parts.joined(separator: ", ")
    }

    private func activateCard() {
        guard store.pendingCreationState(for: item.id) == nil else { return }
        if isSelecting {
            onSelect()
        } else {
            showInspector()
        }
    }

    private func syncTitle(for state: PendingSyncState) -> String {
        switch state {
        case .syncing: String(localized: "Syncing with GitHub…")
        case .failed: String(localized: "Sync failed")
        case .unconfirmed: String(localized: "Check GitHub before retrying")
        }
    }

}

// MARK: - Drag Preview

struct KanbanCardPreview: View {
    let item: ProjectItem

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.contentType == .pullRequest ? "arrow.triangle.merge" : "circle.dotted")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text(item.displayTitle)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)

            if let number = item.number {
                Text("#\(number)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        )
    }
}
