import SwiftUI

struct ItemDescriptionView: View {
    @Bindable var store: ProjectStore
    let reference: ItemInspectorReference
    @State private var presentedEdit: PresentedEdit?

    private struct PresentedEdit {
        let contentID: String
        let title: String
        let body: String
    }

    private var item: ProjectItem? { store.item(for: reference) }
    private var pendingEdit: PendingContentEdit? {
        item?.contentId.flatMap { store.pendingContentEdits[$0] }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading

            if let item {
                descriptionContent(for: item)
            } else {
                unavailable
            }
        }
        .onChange(of: pendingEdit?.id, initial: true) { _, _ in
            guard let pendingEdit else { return }
            presentedEdit = PresentedEdit(
                contentID: pendingEdit.id, title: pendingEdit.title, body: pendingEdit.body
            )
        }
        .onChange(of: reference) { _, _ in
            if pendingEdit == nil { presentedEdit = nil }
        }
        .onChange(of: store.isRefreshingItem(reference)) { _, isRefreshing in
            if isRefreshing && pendingEdit == nil { presentedEdit = nil }
        }
    }

    private var heading: some View {
        HStack(alignment: .top, spacing: 12) {
            if let item {
                Image(systemName: stateSymbol(for: item).name)
                    .font(.title2)
                    .foregroundStyle(stateSymbol(for: item).color)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.displayTitle)
                        .font(.title2.bold())
                        .lineLimit(2)
                        .textSelection(.enabled)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            let repository = item.repositoryName ?? String(localized: "Draft item")
                            let identifier = item.number.map { "\(repository) #\($0)" } ?? repository

                            if let urlString = item.url, let url = URL(string: urlString) {
                                Link(identifier, destination: url)
                            } else {
                                Text(identifier)
                            }

                            Text("· \(stateTitle(for: item))")
                                .foregroundStyle(.secondary)
                        }

                        if let detailMetadata = detailMetadata(for: item) {
                            Text(detailMetadata)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.callout)
                    .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: 760, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    @ViewBuilder
    private func descriptionContent(for item: ProjectItem) -> some View {
        if let body = locallyPresentedBody(for: item) {
            ScrollView {
                Text(body.isEmpty ? String(localized: "No Description") : body)
                    .textSelection(.enabled)
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(24)
            }
        } else {
            switch store.itemDetailState(for: item) {
            case .idle, .loading:
                ProgressView("Loading description…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .loaded(let detail):
                if detail.bodyHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView(
                        "No Description",
                        systemImage: "text.alignleft",
                        description: Text("This item does not have a description.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    GitHubHTMLBodyView(html: detail.bodyHTML)
                }

            case .failed(let message):
                VStack(spacing: 12) {
                    ContentUnavailableView(
                        "Description Unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text(message)
                    )

                    Button("Retry") {
                        Task { await store.loadItemDetail(for: item, forceRefresh: true) }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
    }

    private func locallyPresentedBody(for item: ProjectItem) -> String? {
        if let contentID = item.contentId, let edit = store.pendingContentEdits[contentID] {
            return edit.body
        }
        // A confirmed write only removes the sync label; it must not rebuild the visible body.
        guard let presentedEdit, presentedEdit.contentID == item.contentId,
              item.title == presentedEdit.title,
              case .loaded(let detail) = store.itemDetailState(for: item),
              detail.body == presentedEdit.body else { return nil }
        return presentedEdit.body
    }

    private func syncStatusText(for state: PendingSyncState) -> String {
        switch state {
        case .syncing: String(localized: "Syncing with GitHub…")
        case .failed: String(localized: "Sync failed")
        case .unconfirmed: String(localized: "Sync status unknown")
        }
    }

    private func detailMetadata(for item: ProjectItem) -> String? {
        let detail: ProjectItemDetail?
        if case .loaded(let loaded) = store.itemDetailState(for: item) {
            detail = loaded
        } else {
            detail = nil
        }
        let edit = item.contentId.flatMap { store.pendingContentEdits[$0] }
        var values: [String] = []
        if let author = edit?.author ?? detail?.author {
            values.append("@\(author.login)")
        }
        if let edit {
            values.append(syncStatusText(for: edit.state))
        } else if let updated = detail?.updatedAt.flatMap(formattedDate) {
            values.append(String(localized: "Updated \(updated)"))
        }
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }

    private func stateTitle(for item: ProjectItem) -> String {
        switch item.contentType {
        case .issue:
            return item.issueState == .closed ? String(localized: "Closed") : String(localized: "item.state.open", defaultValue: "Open", comment: "An issue or pull request that is still open, not the action to open a window.")
        case .pullRequest:
            if item.engineeringSignals?.isDraft == true { return String(localized: "Draft pull request") }
            switch item.prState {
            case .merged: return String(localized: "Merged")
            case .closed: return String(localized: "Closed")
            case .open, .none: return String(localized: "item.state.open", defaultValue: "Open", comment: "An issue or pull request that is still open, not the action to open a window.")
            }
        case .draftIssue:
            return String(localized: "Draft item")
        case .redacted:
            return String(localized: "Unavailable")
        }
    }

    private func stateSymbol(for item: ProjectItem) -> (name: String, color: Color) {
        switch item.contentType {
        case .issue:
            return item.issueState == .closed
                ? ("checkmark.circle.fill", .purple)
                : ("circle", .green)
        case .pullRequest:
            switch item.prState {
            case .merged: return ("arrow.triangle.merge", .purple)
            case .closed: return ("xmark.circle", .red)
            case .open, .none: return ("arrow.triangle.pull", .green)
            }
        case .draftIssue:
            return ("doc.text", .secondary)
        case .redacted:
            return ("questionmark.square.dashed", .secondary)
        }
    }

    private var unavailable: some View {
        ContentUnavailableView("Item Unavailable", systemImage: "archivebox")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func formattedDate(_ value: String) -> String? {
        guard let date = try? Date(value, strategy: .iso8601) else { return nil }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
