import SwiftUI

struct MobileItemDetailView: View {
    @Bindable var store: ProjectStore
    let reference: ItemInspectorReference
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
                switch store.itemDetailState(for: item) {
                case .idle, .loading: ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Couldn’t Load Item", systemImage: "exclamationmark.triangle")
                    } description: { Text(message) } actions: {
                        Button("Retry") { Task { await store.loadItemDetail(for: item, forceRefresh: true) } }
                    }
                case .loaded(let detail):
                    if detail.body.isEmpty {
                        ContentUnavailableView("No Description", systemImage: "text.alignleft")
                    } else {
                        GitHubHTMLBodyView(html: detail.bodyHTML)
                    }
                }
            } else {
                ContentUnavailableView("Item Unavailable", systemImage: "questionmark.folder")
            }
        }
        .navigationTitle(item?.number.map { "#\($0)" } ?? String(localized: "Details"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: reference) { if let item { await store.loadItemDetail(for: item) } }
    }
}
