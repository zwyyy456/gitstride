import SwiftUI

struct MobileItemDetailView: View {
    @Bindable var store: ProjectStore
    let reference: ItemInspectorReference
    @State private var showingEditor = false
    @State private var showingProperties = false
    @State private var confirmArchive = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    private var item: ProjectItem? { store.item(for: reference) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let item {
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.displayTitle).font(.title2.bold()).textSelection(.enabled)
                    if let url = item.url.flatMap(URL.init(string:)) {
                        ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                    }
                }
                .padding()
                if let errorMessage { Text(errorMessage).foregroundStyle(.red).padding() }
                if let pending = item.contentId.flatMap({ store.pendingContentEdits[$0] }) {
                    switch pending.state {
                    case .syncing: ProgressView("Syncing with GitHub…").padding()
                    case .failed(let message):
                        Text(message).foregroundStyle(.red).padding()
                        Button("Retry") { store.retryPendingEdit(pending.id) }
                    case .unconfirmed(let message): Text(message).foregroundStyle(.orange)
                    }
                }
                if showingProperties {
                    ItemPropertiesView(store: store, reference: reference)
                } else {
                    switch store.itemDetailState(for: item) {
                    case .idle, .loading:
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .failed(let message):
                        ContentUnavailableView {
                            Label("Couldn’t Load Item", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(message)
                        } actions: {
                            Button("Retry") {
                                Task { await store.loadItemDetail(for: item, forceRefresh: true) }
                            }
                        }
                    case .loaded(let detail):
                        if detail.body.isEmpty {
                            ContentUnavailableView("No Description", systemImage: "text.alignleft")
                        } else if let pending = store.pendingContentEdits[detail.id] {
                            ScrollView {
                                Text(pending.body).textSelection(.enabled).frame(
                                    maxWidth: .infinity, alignment: .leading
                                ).padding()
                            }
                        } else {
                            GitHubHTMLBodyView(html: detail.bodyHTML)
                        }
                    }
                }
            } else {
                ContentUnavailableView("Item Unavailable", systemImage: "questionmark.folder")
            }
        }
        .navigationTitle(item?.number.map { "#\($0)" } ?? String(localized: "Details"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showingProperties.toggle()
                } label: {
                    Label("Properties", systemImage: "slider.horizontal.3")
                }
                Menu {
                    Button("Edit") { showingEditor = true }.disabled(
                        !store.canEditItemContent(reference))
                    Button("Refresh") {
                        Task {
                            do { try await store.refreshItem(reference) } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    }
                    if let url = item?.url.flatMap(URL.init(string:)) {
                        Link("Open in GitHub", destination: url)
                    }
                    Button("Archive", role: .destructive) { confirmArchive = true }
                        .disabled(!store.canEditProject(id: reference.projectID))
                } label: {
                    Label("More Actions", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            if let item, case .loaded(let detail) = store.itemDetailState(for: item) {
                MobileItemEditor(store: store, reference: reference, detail: detail)
            }
        }
        .confirmationDialog("Archive this item?", isPresented: $confirmArchive) {
            Button("Archive", role: .destructive) {
                guard let item else { return }
                Task {
                    do {
                        try await store.archiveItem(item, in: reference.projectID)
                        dismiss()
                    } catch { errorMessage = error.localizedDescription }
                }
            }
        }
        .task(id: reference) { if let item { await store.loadItemDetail(for: item) } }
    }
}
