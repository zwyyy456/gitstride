import SwiftUI

struct ItemDescriptionView: View {
    @Bindable var store: ProjectStore
    let reference: ItemInspectorReference
    @State private var showsDiscardConfirmation = false
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
        if let edit = pendingEdit {
            VStack(spacing: 0) {
                if case .failed(let message) = edit.state {
                    HStack {
                        Text(message).font(.callout).textSelection(.enabled)
                        Spacer()
                        Button("Retry") { store.retryPendingEdit(edit.id) }
                        Button("Discard Changes") { showsDiscardConfirmation = true }
                    }
                    .padding(12)
                    .background(.orange.opacity(0.12))
                }
                ItemMarkdownBodyView(markdown: edit.body)
            }
            .confirmationDialog("Discard this pending edit?", isPresented: $showsDiscardConfirmation) {
                Button("Discard Changes", role: .destructive) { store.dismissPendingEdit(edit.id) }
                Button("Cancel", role: .cancel) {}
            }
        } else {
            switch store.itemDetailState(for: item) {
            case .idle, .loading:
                ProgressView("Loading description…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .loaded(let detail):
                ItemMarkdownBodyView(markdown: detail.body)

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
