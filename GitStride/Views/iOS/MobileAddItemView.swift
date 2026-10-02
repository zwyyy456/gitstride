import SwiftUI

struct MobileAddItemView: View {
    @Bindable var store: ProjectStore
    let projectID: String
    private var project: Project? { store.project(id: projectID) }
    @Environment(\.dismiss) private var dismiss
    @State private var draft: NewProjectItemDraft
    @State private var initialDraft: NewProjectItemDraft
    @State private var confirmingDiscard = false
    @State private var existing = false
    @State private var query = ""
    @State private var results: [GitHubItemCandidate] = []
    @State private var isWorking = false
    @State private var errorMessage: String?

    init(store: ProjectStore, projectID: String) {
        self.store = store
        self.projectID = projectID
        let project = store.project(id: projectID)
        var draft = NewProjectItemDraft()
        draft.repository = project.map { store.defaultIssueRepository(in: $0) } ?? ""
        draft.reconcileStatus(in: project)
        _draft = State(initialValue: draft)
        _initialDraft = State(initialValue: draft)
    }

    private var hasChanges: Bool { draft != initialDraft }
    private var statuses: [String] { NewProjectItemDraft.statusOptions(in: project) }
    private var priorities: [String] { NewProjectItemDraft.priorityOptions(in: project) }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Add to Project", selection: $existing) {
                    Text("Create New").tag(false)
                    Text("Add Existing").tag(true)
                }
                .pickerStyle(.segmented)
                if existing { existingItems } else { creationForm }
                if isWorking { ProgressView() }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .disabled(isWorking)
            .navigationTitle("Add to Project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasChanges { confirmingDiscard = true }
                        else { dismiss() }
                    }
                    .disabled(isWorking)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !existing {
                        Button("Create", action: create)
                            .disabled(isWorking || !draft.canSubmit(in: project))
                    }
                }
            }
            .projectUsage(store: store, projectIDs: [projectID], refresh: false)
            .onChange(of: statuses) { _, _ in
                draft.reconcileStatus(in: project)
                initialDraft.reconcileStatus(in: project)
            }
        }
        .interactiveDismissDisabled(hasChanges || isWorking)
        .confirmationDialog("Discard Changes?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) { dismiss() }
            Button("Continue Editing", role: .cancel) {}
        }
    }

    private var creationForm: some View {
        Group {
            Section {
                Picker("Type", selection: $draft.itemType) {
                    ForEach(NewProjectItemDraft.ItemType.allCases) { Text($0.title).tag($0) }
                }
                if draft.itemType == .issue {
                    NavigationLink {
                        MobileRepositoryPicker(store: store, owner: project?.owner, selection: $draft.repository)
                    } label: {
                        LabeledContent(
                            "Repository",
                            value: draft.repository.isEmpty
                                ? String(localized: "Choose Repository") : draft.repository)
                    }
                }
                TextField("Title", text: $draft.title, axis: .vertical)
                TextEditor(text: $draft.bodyText).frame(minHeight: 160).accessibilityLabel(
                    "Description")
            }
            if draft.itemType == .issue {
                Section("Fields") {
                    if !statuses.isEmpty {
                        Picker("Status", selection: $draft.status) {
                            if draft.status.isEmpty { Text("Choose Status").tag("").disabled(true) }
                            ForEach(statuses, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    if !priorities.isEmpty {
                        Picker("Priority", selection: $draft.priority) {
                            Text("Not Set").tag("")
                            ForEach(priorities, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    TextField("Labels (comma-separated)", text: $draft.labels)
                        .textInputAutocapitalization(
                            .never)
                    TextField("Assignees (comma-separated)", text: $draft.assignees)
                        .textInputAutocapitalization(.never)
                    Button("Assign to Me") { draft.assignToMe() }
                        .disabled(draft.hasCurrentUserAssignee(currentUser: store.currentUserLogin))
                    optionalDate("Start date", value: $draft.startDate)
                    optionalDate("Target date", value: $draft.targetDate)
                }
            }
            Section("Quick Entry") {
                TextField("> Title repo:owner/repo @me #bug", text: $draft.quickEntry)
                    .textInputAutocapitalization(.never)
                Button("Apply Quick Entry") {
                    errorMessage = draft.reviewQuickEntry(
                        repositories: store.repositorySuggestions,
                        statuses: statuses, priorities: priorities)
                }
                .disabled(draft.quickEntry.isEmpty)
            }
        }
    }

    private var existingItems: some View {
        Section {
            TextField("Search or paste a GitHub URL", text: $query)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .onSubmit(search)
            Button("Search", action: search).disabled(
                query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            ForEach(results) { candidate in
                Button {
                    isWorking = true
                    errorMessage = nil
                    Task {
                        defer { isWorking = false }
                        do {
                            try await store.addExistingItem(candidate, projectID: projectID)
                            dismiss()
                        } catch { errorMessage = error.localizedDescription }
                    }
                } label: {
                    VStack(alignment: .leading) {
                        Text(candidate.title)
                        Text("\(candidate.repository) #\(candidate.number)").font(.caption)
                            .foregroundStyle(
                                .secondary)
                    }
                }
            }
        }
    }

    private func optionalDate(_ title: LocalizedStringKey, value: Binding<Date?>) -> some View {
        Group {
            Toggle(
                title,
                isOn: Binding(
                    get: { value.wrappedValue != nil },
                    set: { value.wrappedValue = $0 ? Date() : nil }))
            if value.wrappedValue != nil {
                DatePicker(
                    title,
                    selection: Binding(
                        get: { value.wrappedValue ?? Date() }, set: { value.wrappedValue = $0 }),
                    displayedComponents: .date)
            }
        }
    }

    private func create() {
        guard draft.canSubmit(in: project) else { return }
        do {
            if draft.itemType == .draft {
                try store.beginDraftCreation(title: draft.title, body: draft.bodyText, projectID: projectID)
            } else {
                let creation = try store.prepareIssueCreation(
                    repository: draft.repository, title: draft.title,
                    body: draft.bodyText, labels: draft.labelNames,
                    assignees: draft.assigneeLogins(currentUser: store.currentUserLogin),
                    status: draft.status.isEmpty ? nil : draft.status,
                    priority: draft.priority.isEmpty ? nil : draft.priority,
                    startDate: draft.startDate, targetDate: draft.targetDate, projectID: projectID)
                try store.beginIssueCreation(creation)
            }
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }

    private func search() {
        isWorking = true
        errorMessage = nil
        Task {
            defer { isWorking = false }
            do { results = try await store.searchItems(query: query) } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct MobileRepositoryPicker: View {
    let store: ProjectStore
    let owner: ProjectOwner?
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        List {
            if let owner {
                switch store.repositoryListState(ownerID: owner.id) {
                case .idle, .loading: ProgressView()
                case .failed(let message):
                    Text(message).foregroundStyle(.red)
                    Button("Retry") { Task { await store.loadRepositories(owner: owner) } }
                case .loaded(let repositories):
                    ForEach(
                        repositories.filter {
                            query.isEmpty
                                || $0.nameWithOwner.localizedCaseInsensitiveContains(query)
                        }
                    ) { repository in
                        Button(repository.nameWithOwner) {
                            selection = repository.nameWithOwner
                            dismiss()
                        }
                    }
                }
            }
            Section("Repository") {
                TextField("owner/repository", text: $query).textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Use Repository") {
                    selection = query.trimmingCharacters(in: .whitespacesAndNewlines)
                    dismiss()
                }
                .disabled(!query.contains("/"))
            }
        }
        .searchable(text: $query)
        .navigationTitle("Repository")
        .task { if let owner { await store.loadRepositories(owner: owner) } }
    }
}
