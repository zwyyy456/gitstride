import AppKit
import SwiftUI

struct AddProjectItemView: View {
    static let sheetWidth: CGFloat = 620
    private static let sheetHeight: CGFloat = 520
    static let horizontalPadding: CGFloat = 48
    static let windowDefaultSize = CGSize(width: sheetWidth, height: sheetHeight)
    static let windowMinimumSize = CGSize(width: 520, height: 500)

    enum Presentation {
        case sheet
        case window
    }

    @Bindable var store: ProjectStore
    let presentation: Presentation
    let initialQuickEntry: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var mode: Mode = .create
    @State private var maximumSheetHeight: CGFloat?
    @State private var isSubmitting = false
    @State private var validationMessage: String?
    @State private var draft = NewProjectItemDraft()
    @State private var search = ExistingItemSearchState()

    init(store: ProjectStore, presentation: Presentation = .sheet, initialQuickEntry: String? = nil) {
        self.store = store
        self.presentation = presentation
        self.initialQuickEntry = initialQuickEntry
        _draft = State(initialValue: NewProjectItemDraft(
            quickEntry: initialQuickEntry ?? "", usesQuickEntry: initialQuickEntry != nil
        ))
    }

    private enum Mode {
        case create
        case existing
    }

    private var isWorking: Bool { isSubmitting }

    var body: some View {
        VStack(spacing: 0) {
            header

            Group {
                switch mode {
                case .create:
                    NewProjectItemEditor(store: store, draft: $draft,
                                         validationMessage: $validationMessage,
                                         statusOptions: statusOptions, priorityOptions: priorityOptions,
                                         reviewQuickEntry: applyQuickEntry)
                case .existing:
                    ExistingProjectItemPicker(store: store, state: $search,
                                              validationMessage: $validationMessage)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .disabled(isWorking)

            Divider()
            actionBar
        }
        .frame(
            width: presentation == .sheet ? Self.sheetWidth : nil,
            height: presentation == .sheet ? preferredSheetHeight : nil
        )
        .frame(
            minWidth: presentation == .window ? Self.windowMinimumSize.width : nil,
            idealWidth: presentation == .window ? Self.windowDefaultSize.width : nil,
            minHeight: presentation == .window ? Self.windowMinimumSize.height : nil,
            idealHeight: presentation == .window ? Self.windowDefaultSize.height : nil
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .background {
            Button("Submit Item", action: performPrimaryAction)
                .keyboardShortcut(.return, modifiers: .command)
                .hidden()
                .accessibilityHidden(true)
        }
        .task {
            if let screen = NSApp.keyWindow?.screen {
                maximumSheetHeight = screen.visibleFrame.height - 80
            }
            validationMessage = nil
            if draft.repository.isEmpty {
                draft.repository = store.defaultIssueRepository
            }
            updateStatusSelection()
            if draft.usesQuickEntry, !QuickCreateParser.parse(draft.quickEntry).title.isEmpty {
                applyQuickEntry()
            }
        }
        .onChange(of: store.selectedProjectId) { _, _ in
            guard presentation == .window else { return }
            draft.repository = store.defaultIssueRepository
            draft.status = defaultStatus
            draft.priority = ""
        }
        .onChange(of: statusOptions) { _, _ in
            updateStatusSelection()
        }
        .onChange(of: store.defaultIssueRepository) { oldValue, newValue in
            guard draft.repository.isEmpty || draft.repository == oldValue else { return }
            draft.repository = newValue
        }
        .onChange(of: mode) { _, _ in
            validationMessage = nil
        }
        .onChange(of: draft.repository) { _, _ in
            draft.repositoryValidationMessage = nil
        }
    }

    private var sheetTitle: String {
        if let project = store.project(id: store.selectedProjectId ?? "") {
            return String(localized: "Add Item to “\(project.title)”")
        }
        return String(localized: "Add Item to Project")
    }

    private var header: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                if presentation == .sheet {
                    Text(sheetTitle)
                        .font(.headline)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .help(sheetTitle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Project")
                        .foregroundStyle(.secondary)
                    ProjectSelectorView(store: store)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Picker("Item source", selection: $mode) {
                Text("Create New").tag(Mode.create)
                Text("Add Existing").tag(Mode.existing)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.top, 20)
        .padding(.bottom, 20)
        .disabled(isWorking)
    }

    private var preferredSheetHeight: CGFloat {
        min(Self.sheetHeight, maximumSheetHeight ?? Self.sheetHeight)
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            if mode == .create {
                Button(draft.usesQuickEntry ? String(localized: "Show Full Form") : String(localized: "Quick Entry…")) {
                    draft.usesQuickEntry.toggle()
                }
                .disabled(isWorking)
            }

            if isWorking, search.isSearching == false {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Working")
            }

            Spacer()

            Button("Cancel", action: close)
                .keyboardShortcut(.cancelAction)

            switch mode {
            case .create:
                if draft.usesQuickEntry {
                    Button("Review Details", action: applyQuickEntry)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(isWorking || draft.quickEntry.trimmed.isEmpty)
                } else {
                    Button(createActionTitle, action: createItem)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(createActionIsDisabled)
                }
            case .existing:
                Button("Add Item", action: addSelectedItem)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(addActionIsDisabled)
            }
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.vertical, 14)
    }

    private var addActionIsDisabled: Bool {
        guard let selectedResult = search.selectedResult else { return true }
        return isWorking || search.isSearching || isAlreadyAdded(selectedResult)
    }

    private func addSelectedItem() {
        guard addActionIsDisabled == false, let selectedResult = search.selectedResult else { return }
        add(selectedResult)
    }

    private func performPrimaryAction() {
        switch mode {
        case .create:
            if draft.usesQuickEntry {
                applyQuickEntry()
            } else if createActionIsDisabled == false {
                createItem()
            }
        case .existing:
            addSelectedItem()
        }
    }

    private var createActionTitle: String {
        if isWorking { return String(localized: "Creating…") }
        return draft.itemType == .issue ? String(localized: "Create Issue") : String(localized: "Create Draft")
    }

    private var createActionIsDisabled: Bool {
        return isWorking || draft.title.trimmed.isEmpty
            || (draft.itemType == .issue && (draft.repository.trimmed.isEmpty || needsStatusSelection))
    }

    private var statusOptions: [String] {
        guard let project = store.selectedProject, project.statusField != nil else { return [] }
        var options = project.statusOptions.map(\.name)
        if options.contains(where: { $0.caseInsensitiveCompare("Backlog") == .orderedSame }) == false {
            options.append("Backlog")
        }
        return options
    }

    private var defaultStatus: String {
        statusOptions.first { $0.caseInsensitiveCompare("Todo") == .orderedSame } ?? ""
    }

    private var needsStatusSelection: Bool {
        statusOptions.isEmpty == false && statusOptions.contains(draft.status) == false
    }

    private func updateStatusSelection() {
        if statusOptions.contains(draft.status) == false {
            draft.status = defaultStatus
        }
    }

    private var priorityOptions: [String] {
        guard let field = store.selectedProject?.fields.first(where: {
            $0.kind == .singleSelect && $0.name.caseInsensitiveCompare("Priority") == .orderedSame
        }) else { return [] }
        return field.options.map(\.name)
    }

    private func createItem() {
        guard createActionIsDisabled == false else { return }
        NSApp.keyWindow?.makeFirstResponder(nil)
        validationMessage = nil
        draft.repositoryValidationMessage = nil
        do {
            if draft.itemType == .issue {
                let creation = try store.prepareIssueCreation(
                    repository: draft.repository.trimmed, title: draft.title.trimmed, body: draft.bodyText,
                    labels: draft.labelNames,
                    assignees: draft.assigneeLogins(currentUser: store.currentUserLogin),
                    status: draft.status.trimmed.nilIfEmpty, priority: draft.priority.trimmed.nilIfEmpty
                )
                try store.beginIssueCreation(creation)
            } else {
                try store.beginDraftCreation(title: draft.title.trimmed, body: draft.bodyText)
            }
            close()
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func add(_ item: GitHubItemCandidate) {
        guard isWorking == false else { return }
        isSubmitting = true
        validationMessage = nil
        Task {
            do {
                try await store.addExistingItem(item)
                close()
            } catch is CancellationError {
            } catch {
                validationMessage = error.localizedDescription
            }
            isSubmitting = false
        }
    }

    private func isAlreadyAdded(_ item: GitHubItemCandidate) -> Bool {
        store.selectedProject?.items.contains { $0.contentId == item.id } == true
    }

    private func applyQuickEntry() {
        guard !isWorking else { return }
        validationMessage = draft.reviewQuickEntry(
            repositories: store.repositorySuggestions,
            statuses: statusOptions, priorities: priorityOptions
        )
    }

    private func close() {
        switch presentation {
        case .sheet:
            dismiss()
        case .window:
            dismissWindow(id: "quick-add", value: initialQuickEntry ?? "")
        }
    }


}

struct PendingItemFailureBanner: View {
    @Bindable var store: ProjectStore
    @State private var showsOperations = false

    private var failureCount: Int {
        (store.pendingCreationList.map(\.state) + store.pendingEditList.map(\.state)).filter { state in
            if case .syncing = state { return false }
            return true
        }.count
    }

    var body: some View {
        if failureCount > 0 {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("GitHub sync needs attention")
                    .font(.caption)
                Spacer(minLength: 8)
                Button("Review") { showsOperations = true }
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.12))
            .popover(isPresented: $showsOperations, arrowEdge: .bottom) {
                PendingItemOperationsView(store: store)
                    .frame(width: 360)
            }
        }
    }
}

private struct PendingItemOperationsView: View {
    @Bindable var store: ProjectStore
    @State private var itemToDiscard: UUID?
    @State private var editToDiscard: String?

    var body: some View {
        if !store.pendingCreationList.isEmpty || !store.pendingEditList.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(store.pendingEditList) { edit in
                        HStack(spacing: 8) {
                            if case .syncing = edit.state {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(edit.title).lineLimit(1)
                                Text(statusText(for: edit.state))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            if case .failed = edit.state {
                                Button("Retry") { store.retryPendingEdit(edit.id) }
                                    .controlSize(.small)
                                Button("Discard") { editToDiscard = edit.id }
                                    .controlSize(.small)
                            }
                        }
                    }
                    ForEach(store.pendingCreationList) { operation in
                        HStack(spacing: 8) {
                            if case .syncing = operation.state {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(operation.title).lineLimit(1)
                                Text(statusText(for: operation.state))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            if case .failed = operation.state {
                                Button("Retry") { store.retryPendingCreation(operation.id) }
                                    .controlSize(.small)
                                Button("Discard") { itemToDiscard = operation.id }
                                    .controlSize(.small)
                            } else if case .unconfirmed = operation.state {
                                if case .issue(let creation) = operation.kind,
                                   let url = URL(string: "https://github.com/\(creation.repository)/issues") {
                                    Link("Check Repository", destination: url)
                                        .controlSize(.small)
                                }
                                Button("Dismiss") { itemToDiscard = operation.id }
                                    .controlSize(.small)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 160)
            .background(.orange.opacity(0.08))
            .confirmationDialog("Discard this pending item?", isPresented: Binding(
                get: { itemToDiscard != nil },
                set: { if !$0 { itemToDiscard = nil } }
            )) {
                Button("Discard", role: .destructive) {
                    if let itemToDiscard { store.dismissPendingCreation(itemToDiscard) }
                    itemToDiscard = nil
                }
                Button("Cancel", role: .cancel) { itemToDiscard = nil }
            } message: {
                Text("The unsynced item will be removed from this app.")
            }
            .confirmationDialog("Discard this pending edit?", isPresented: Binding(
                get: { editToDiscard != nil },
                set: { if !$0 { editToDiscard = nil } }
            )) {
                Button("Discard", role: .destructive) {
                    if let editToDiscard { store.dismissPendingEdit(editToDiscard) }
                    editToDiscard = nil
                }
                Button("Cancel", role: .cancel) { editToDiscard = nil }
            } message: {
                Text("The unsynced changes will be removed from this app.")
            }
        }
    }

    private func statusText(for state: PendingSyncState) -> String {
        switch state {
        case .syncing: String(localized: "Syncing with GitHub…")
        case .failed(let message): String(localized: "Sync failed: \(message)")
        case .unconfirmed(let message): String(localized: "GitHub may have created this item. \(message)")
        }
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

struct QuickAddWindow: View {
    @Bindable var model: GitStrideModel
    let quickEntry: String

    var body: some View {
        AddProjectItemView(store: model.projectStore, presentation: .window,
                           initialQuickEntry: quickEntry.isEmpty ? nil : quickEntry)
            .task {
                if model.projectStore.projects.isEmpty {
                    await model.projectStore.loadProjects()
                }
            }
    }
}
