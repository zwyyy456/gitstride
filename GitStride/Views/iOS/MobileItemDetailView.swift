import SwiftUI

struct MobileItemDetailView: View {
    @Bindable var store: ProjectStore
    private let target: ContentEditTarget
    @State private var showingEditor = false
    @State private var showingProperties = false
    @State private var propertyProjectID: String?
    @State private var confirmArchive = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    init(store: ProjectStore, reference: ItemInspectorReference) {
        self.store = store
        target = .project(reference)
    }

    init(store: ProjectStore, personalItem: PersonalWorkItem) {
        self.store = store
        target = .personal(personalItem)
    }

    private var reference: ItemInspectorReference? {
        if case .project(let reference) = target { return reference }
        return nil
    }
    private var item: ProjectItem? { reference.flatMap { store.item(for: $0) } }
    private var contentID: String? {
        switch target {
        case .project: item?.contentId
        case .personal(let item): item.id
        }
    }
    private var detailState: ItemDetailState {
        switch target {
        case .project: item.map { store.itemDetailState(for: $0) } ?? .failed(String(localized: "This item is no longer available."))
        case .personal(let item): store.personalItemDetailState(item.id)
        }
    }
    private var detail: ProjectItemDetail? {
        if case .loaded(let detail) = detailState { return detail }
        return nil
    }
    private var pending: PendingContentEdit? { contentID.flatMap { store.pendingContentEdits[$0] } }
    private var title: String {
        if let pending { return pending.title }
        if let detail { return detail.title }
        switch target {
        case .project: return item?.displayTitle ?? String(localized: "Details")
        case .personal(let item): return item.title
        }
    }
    private var url: URL? {
        switch target {
        case .project: item?.url.flatMap(URL.init(string:))
        case .personal(let item): item.url
        }
    }
    private var repository: String? {
        switch target {
        case .project: item?.repositoryName
        case .personal(let item): item.repository
        }
    }
    private var number: Int? {
        switch target {
        case .project: item?.number
        case .personal(let item): item.number
        }
    }
    private var signals: EngineeringSignals {
        if let signals = detail?.pullRequestSignals { return signals }
        return switch target {
        case .project: item?.signals ?? EngineeringSignals()
        case .personal(let item): item.signals
        }
    }
    private var canEdit: Bool {
        guard pending == nil else { return false }
        if let reference { return store.canEditItemContent(reference) }
        return detail?.viewerCanUpdate == true
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    if let repository { Text(repository).font(.subheadline).foregroundStyle(.secondary) }
                    Text(title).font(.title2.bold()).textSelection(.enabled)
                    if detail?.state != "CLOSED" && detail?.state != "MERGED" {
                        EngineeringSignalsView(signals: signals)
                    }
                    if let state = detail?.state {
                        switch state {
                        case "OPEN": Text(String(localized: "Item State Open", defaultValue: "Open")).font(.caption).foregroundStyle(.secondary)
                        case "CLOSED": Text("Closed").font(.caption).foregroundStyle(.secondary)
                        case "MERGED": Text("Merged").font(.caption).foregroundStyle(.secondary)
                        default: EmptyView()
                        }
                    }
                    if let status = item?.status {
                        LabeledContent("Status", value: status).font(.subheadline)
                    }
                    if let author = detail?.author { Text("@\(author.login)").font(.caption).foregroundStyle(.secondary) }
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                if let pending {
                    switch pending.state {
                    case .syncing: ProgressView("Syncing with GitHub…")
                    case .failed(let message):
                        Text(message).foregroundStyle(.red)
                        Button("Retry") { store.retryPendingEdit(pending.id) }
                    case .unconfirmed(let message): Text(message).foregroundStyle(.orange)
                    }
                }
                Divider()
                switch detailState {
                case .idle, .loading:
                    ProgressView("Loading…").frame(maxWidth: .infinity)
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Couldn’t Load Item", systemImage: "exclamationmark.triangle")
                    } description: { Text(message) } actions: {
                        Button("Retry") { Task { await refresh() } }
                    }
                case .loaded(let detail):
                    ItemMarkdownContentView(markdown: pending?.body ?? detail.body)
                    if let metadata = detail.issueMetadata {
                        relations(metadata)
                    }
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding()
        }
        .navigationTitle(number.map { "#\($0)" } ?? String(localized: "Details"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Properties", systemImage: "slider.horizontal.3") { showingProperties.toggle() }
                Menu {
                    if let url { ShareLink(item: url) }
                    Button("Edit") { showingEditor = true }.disabled(!canEdit)
                    Button("Refresh") { Task { await refresh() } }
                    if let url { Link("Open in GitHub", destination: url) }
                    if let reference {
                        Button("Archive", role: .destructive) { confirmArchive = true }
                            .disabled(!store.canEditProject(id: reference.projectID))
                    }
                } label: { Label("More Actions", systemImage: "ellipsis.circle") }
            }
        }
        .inspector(isPresented: $showingProperties) {
            NavigationStack {
                propertiesPanel
                    .navigationTitle("Properties")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { Button("Done") { showingProperties = false } }
            }
            .inspectorColumnWidth(min: 300, ideal: 360, max: 440)
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingEditor) {
            if let detail {
                MobileItemEditor(store: store, detail: detail) { title, body in
                    switch target {
                    case .project(let reference):
                        try store.beginContentEdit(reference, contentID: detail.id, title: title, body: body)
                    case .personal(let item):
                        try store.beginPersonalContentEdit(item, title: title, body: body)
                    }
                }
            }
        }
        .confirmationDialog("Archive this item?", isPresented: $confirmArchive) {
            Button("Archive", role: .destructive) {
                guard let reference, let item else { return }
                Task {
                    do { try await store.archiveItem(item, in: reference.projectID); dismiss() }
                    catch { errorMessage = error.localizedDescription }
                }
            }
        }
        .task(id: contentID) {
            switch target {
            case .project: if let item { await store.loadItemDetail(for: item) }
            case .personal(let item): await store.loadPersonalItemDetail(item)
            }
        }
        .refreshable { await refresh() }
    }

    private var propertyReferences: [ItemInspectorReference] {
        guard let contentID else { return reference.map { [$0] } ?? [] }
        return store.allProjects.compactMap { project in
            guard let item = project.items.first(where: { $0.contentId == contentID }) else { return nil }
            return ItemInspectorReference(projectID: project.id, itemID: item.id)
        }
    }

    private var propertiesPanel: some View {
        let references = propertyReferences
        let selected = references.first { $0.projectID == (propertyProjectID ?? reference?.projectID) } ?? references.first
        return VStack(spacing: 0) {
            if references.count > 1 {
                Picker("Project", selection: Binding(
                    get: { selected?.projectID },
                    set: { propertyProjectID = $0 }
                )) {
                    ForEach(references, id: \.projectID) { reference in
                        Text(store.project(id: reference.projectID)?.title ?? "")
                            .tag(Optional(reference.projectID))
                    }
                }
                .padding()
            }
            if let selected {
                ItemPropertiesView(store: store, reference: selected).id(selected)
            } else {
                Form {
                    if let repository { LabeledContent("Repository", value: repository) }
                    if let author = detail?.author { LabeledContent("Author", value: "@\(author.login)") }
                    if let state = detail?.state { LabeledContent("State", value: state) }
                    if let milestone = detail?.issueMetadata?.milestone { LabeledContent("Milestone", value: milestone.title) }
                    Section {
                        Text("Project properties are available when this item belongs to a loaded project.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func refresh() async {
        errorMessage = nil
        switch target {
        case .project(let reference):
            do { try await store.refreshItem(reference) } catch { errorMessage = error.localizedDescription }
        case .personal(let item): await store.loadPersonalItemDetail(item, forceRefresh: true)
        }
    }

    @ViewBuilder
    private func relations(_ metadata: IssueMetadata) -> some View {
        if let milestone = metadata.milestone {
            Divider()
            LabeledContent("Milestone", value: milestone.title)
        }
        if let parent = metadata.parent { relationGroup("Parent Issue", items: [parent]) }
        if !metadata.subIssues.isEmpty { relationGroup("Sub-issues", items: metadata.subIssues) }
        if !metadata.blockedBy.isEmpty { relationGroup("Blocked by", items: metadata.blockedBy) }
        if !metadata.blocking.isEmpty { relationGroup("Blocking", items: metadata.blocking) }
    }

    private func relationGroup(_ title: LocalizedStringKey, items: [IssueReference]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text(title).font(.headline)
            ForEach(items) { issue in
                NavigationLink {
                    MobileItemDetailView(store: store, personalItem: PersonalWorkItem(
                        id: issue.id, title: issue.title, number: issue.number, url: issue.url,
                        repository: issue.repository, isPullRequest: false, updatedAt: "", signals: EngineeringSignals()
                    ))
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(issue.title)
                        Text("\(issue.repository) #\(issue.number)").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            }
        }
    }
}
