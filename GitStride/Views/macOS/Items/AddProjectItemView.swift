import AppKit
import SwiftUI

struct AddProjectItemView: View {
    static let sheetWidth: CGFloat = 620
    private static let sheetHeight: CGFloat = 620
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

    @State private var projectID: String?
    @State private var ownerID: String?
    @State private var mode: Mode = .create
    @State private var maximumSheetHeight: CGFloat?
    @State private var isSubmitting = false
    @State private var validationMessage: String?
    @State private var draft = NewProjectItemDraft()
    @State private var search = ExistingItemSearchState()

    init(store: ProjectStore, projectID: String?, presentation: Presentation = .sheet, initialQuickEntry: String? = nil) {
        self.store = store
        _projectID = State(initialValue: projectID)
        _ownerID = State(initialValue: projectID.flatMap { store.project(id: $0)?.owner.id } ?? store.selectedOwnerId)
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
    private var project: Project? { projectID.flatMap { store.project(id: $0) } }
    private var canEditProject: Bool { projectID.map { store.canEditProject(id: $0) } ?? false }
    private var availableProjects: [Project] { ownerID.map { store.projects(ownerID: $0) } ?? [] }
    private var repositories: [String] { project.map { store.repositorySuggestions(in: $0) } ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            header

            Group {
                switch mode {
                case .create:
                    NewProjectItemEditor(store: store, project: project, repositories: repositories, draft: $draft,
                                         validationMessage: $validationMessage,
                                         statusOptions: statusOptions, priorityOptions: priorityOptions,
                                         reviewQuickEntry: applyQuickEntry)
                case .existing:
                    ExistingProjectItemPicker(store: store, project: project, repositories: repositories, state: $search,
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
            if presentation == .window, projectID == nil {
                if store.projects.isEmpty { await store.loadProjects() }
                ownerID = store.selectedOwnerId
                projectID = store.selectedProjectId
            }
            if draft.repository.isEmpty {
                draft.repository = project.map { store.defaultIssueRepository(in: $0) } ?? ""
            }
            draft.reconcileStatus(in: project)
            if draft.usesQuickEntry, !QuickCreateParser.parse(draft.quickEntry).title.isEmpty {
                applyQuickEntry()
            }
        }
        .projectUsage(store: store, projectIDs: Set(projectID.map { [$0] } ?? []), refresh: false)
        .task(id: ownerID) {
            guard presentation == .window, let owner = store.owners.first(where: { $0.id == ownerID }) else { return }
            do {
                try await store.loadProjectCatalog(for: owner)
                guard !Task.isCancelled else { return }
                if projectID == nil { projectID = availableProjects.first?.id }
            } catch {
                guard !Task.isCancelled else { return }
                validationMessage = error.localizedDescription
            }
        }
        .task(id: projectID) {
            if presentation == .window, let projectID {
                await store.loadProjectDetails(id: projectID)
                guard !Task.isCancelled else { return }
                if draft.repository.isEmpty {
                    draft.repository = project.map { store.defaultIssueRepository(in: $0) } ?? ""
                }
            }
        }
        .onChange(of: statusOptions) { _, _ in
            draft.reconcileStatus(in: project)
        }
        .onChange(of: mode) { _, _ in
            validationMessage = nil
        }
        .onChange(of: draft.repository) { _, _ in
            draft.repositoryValidationMessage = nil
        }
    }

    private var sheetTitle: String {
        if let project {
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
                    if store.owners.count > 1 {
                        Menu(store.owners.first { $0.id == ownerID }?.login ?? String(localized: "Owner")) {
                            ForEach(store.owners) { owner in
                                Button(owner.login) {
                                    guard ownerID != owner.id else { return }
                                    projectID = nil
                                    ownerID = owner.id
                                }
                            }
                        }
                    } else {
                        Text("Project").foregroundStyle(.secondary)
                    }
                    Picker("Project", selection: $projectID) {
                        if projectID == nil { Text("Select Project").tag(String?.none) }
                        ForEach(availableProjects) { project in
                            Text(project.title).tag(Optional(project.id))
                        }
                        if let project, !availableProjects.contains(where: { $0.id == project.id }) {
                            Text(project.title).tag(Optional(project.id))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if projectID != nil && project == nil {
                Text("Project unavailable").foregroundStyle(.secondary)
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
        return isWorking || !canEditProject || search.isSearching || isAlreadyAdded(selectedResult)
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
        isWorking || !canEditProject || !draft.canSubmit(in: project)
    }

    private var statusOptions: [String] { NewProjectItemDraft.statusOptions(in: project) }
    private var priorityOptions: [String] { NewProjectItemDraft.priorityOptions(in: project) }

    private func createItem() {
        guard createActionIsDisabled == false, let projectID else { return }
        NSApp.keyWindow?.makeFirstResponder(nil)
        validationMessage = nil
        draft.repositoryValidationMessage = nil
        do {
            if draft.itemType == .issue {
                let creation = try store.prepareIssueCreation(
                    repository: draft.repository, title: draft.title, body: draft.bodyText,
                    labels: draft.labelNames,
                    assignees: draft.assigneeLogins(currentUser: store.currentUserLogin),
                    status: draft.status.nilIfEmpty, priority: draft.priority.nilIfEmpty,
                    startDate: draft.startDate, targetDate: draft.targetDate, projectID: projectID
                )
                try store.beginIssueCreation(creation)
            } else {
                try store.beginDraftCreation(title: draft.title, body: draft.bodyText, projectID: projectID)
            }
            close()
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func add(_ item: GitHubItemCandidate) {
        guard isWorking == false, canEditProject, let projectID else { return }
        isSubmitting = true
        validationMessage = nil
        Task {
            do {
                try await store.addExistingItem(item, projectID: projectID)
                close()
            } catch is CancellationError {
            } catch {
                validationMessage = error.localizedDescription
            }
            isSubmitting = false
        }
    }

    private func isAlreadyAdded(_ item: GitHubItemCandidate) -> Bool {
        project?.items.contains { $0.contentId == item.id } == true
    }

    private func applyQuickEntry() {
        guard !isWorking else { return }
        validationMessage = draft.reviewQuickEntry(
            repositories: repositories,
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
        AddProjectItemView(store: model.projectStore, projectID: model.projectStore.selectedProjectId, presentation: .window,
                           initialQuickEntry: quickEntry.isEmpty ? nil : quickEntry)
    }
}
