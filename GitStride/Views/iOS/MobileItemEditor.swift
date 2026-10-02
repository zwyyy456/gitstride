import SwiftUI

struct MobileItemEditor: View {
    let save: (String, String) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var bodyText: String
    @State private var errorMessage: String?
    @State private var initialTitle: String
    @State private var initialBody: String
    @State private var confirmingDiscard = false

    private var hasChanges: Bool { title != initialTitle || bodyText != initialBody }

    init(store: ProjectStore, detail: ProjectItemDetail, save: @escaping (String, String) throws -> Void) {
        self.save = save
        let pending = store.pendingContentEdits[detail.id]
        _title = State(initialValue: pending?.title ?? detail.title)
        _bodyText = State(initialValue: pending?.body ?? detail.body)
        _initialTitle = State(initialValue: pending?.title ?? detail.title)
        _initialBody = State(initialValue: pending?.body ?? detail.body)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") { TextField("Title", text: $title, axis: .vertical) }
                Section("Description") {
                    TextEditor(text: $bodyText).frame(minHeight: 240)
                        .accessibilityLabel("Description")
                    Text("Markdown supported").font(.caption).foregroundStyle(.secondary)
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .navigationTitle("Edit")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasChanges { confirmingDiscard = true }
                        else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            try save(title.trimmingCharacters(in: .whitespacesAndNewlines), bodyText)
                            dismiss()
                        } catch { errorMessage = error.localizedDescription }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .interactiveDismissDisabled(hasChanges)
        .confirmationDialog("Discard Changes?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) { dismiss() }
            Button("Continue Editing", role: .cancel) {}
        }
    }
}

struct MobilePendingOperations: View {
    @Bindable var store: ProjectStore
    let projectIDs: Set<String>

    var body: some View {
        ForEach(store.pendingCreationList.filter { projectIDs.contains($0.projectID) })
        {
            operation in
            VStack(alignment: .leading, spacing: 8) {
                Text(operation.title).font(.headline)
                switch operation.state {
                case .syncing: ProgressView("Syncing with GitHub…")
                case .failed(let message):
                    Text(message).foregroundStyle(.red)
                    Button("Retry") { store.retryPendingCreation(operation.id) }
                case .unconfirmed(let message):
                    Text(message).foregroundStyle(.orange)
                    if case .issue(let creation) = operation.kind,
                        let url = URL(string: "https://github.com/\(creation.repository)/issues")
                    {
                        Link("Check Repository", destination: url)
                    }
                    Button("Dismiss") { store.dismissPendingCreation(operation.id) }
                }
            }
        }
        ForEach(
            store.pendingEditList.filter { $0.reference.map { projectIDs.contains($0.projectID) } == true }
        ) { edit in
            VStack(alignment: .leading, spacing: 8) {
                Text(edit.title).font(.headline)
                switch edit.state {
                case .syncing: ProgressView("Syncing with GitHub…")
                case .failed(let message):
                    Text(message).foregroundStyle(.red)
                    Button("Retry") { store.retryPendingEdit(edit.id) }
                case .unconfirmed(let message): Text(message).foregroundStyle(.orange)
                }
            }
        }
    }
}
