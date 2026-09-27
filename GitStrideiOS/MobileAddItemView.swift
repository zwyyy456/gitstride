import SwiftUI

struct MobileAddItemView: View {
    @Bindable var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft = NewProjectItemDraft()
    @State private var existing = false
    @State private var query = ""
    @State private var results: [GitHubItemCandidate] = []
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var statuses: [String] {
        guard let project = store.selectedProject, project.statusField != nil else { return [] }
        let names = project.statusOptions.map(\.name)
        return names.contains(where: { $0.caseInsensitiveCompare("Backlog") == .orderedSame })
            ? names : names + ["Backlog"]
    }
    private var priorities: [String] {
        store.selectedProject?.fields.first {
            $0.kind == .singleSelect && $0.name.caseInsensitiveCompare("Priority") == .orderedSame
        }?.options.map(\.name) ?? []
    }

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
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if !existing {
                        Button("Create", action: create)
                            .disabled(
                                draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    || (draft.itemType == .issue && draft.repository.isEmpty)
                                    || isWorking)
                    }
                }
            }
            .onAppear { draft.repository = store.defaultIssueRepository }
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
                        MobileRepositoryPicker(store: store, selection: $draft.repository)
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
                    Picker("Status", selection: $draft.status) {
                        Text("Not Set").tag("")
                        ForEach(statuses, id: \.self) { Text($0).tag($0) }
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
                            try await store.addExistingItem(candidate)
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
        do {
            let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if draft.itemType == .draft {
                try store.beginDraftCreation(title: title, body: draft.bodyText)
            } else {
                let creation = try store.prepareIssueCreation(
                    repository: draft.repository, title: title,
                    body: draft.bodyText, labels: draft.labelNames,
                    assignees: draft.assigneeLogins(currentUser: store.currentUserLogin),
                    status: draft.status.isEmpty ? nil : draft.status,
                    priority: draft.priority.isEmpty ? nil : draft.priority,
                    startDate: draft.startDate, targetDate: draft.targetDate)
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
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        List {
            if let owner = store.selectedOwner {
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
        .task { if let owner = store.selectedOwner { await store.loadRepositories(owner: owner) } }
    }
}
