import SwiftUI

struct MobileItemEditor: View {
  let store: ProjectStore
  let reference: ItemInspectorReference
  let detail: ProjectItemDetail
  @Environment(\.dismiss) private var dismiss
  @State private var title: String
  @State private var bodyText: String
  @State private var errorMessage: String?

  init(store: ProjectStore, reference: ItemInspectorReference, detail: ProjectItemDetail) {
    self.store = store
    self.reference = reference
    self.detail = detail
    let pending = store.pendingContentEdits[detail.id]
    _title = State(initialValue: pending?.title ?? detail.title)
    _bodyText = State(initialValue: pending?.body ?? detail.body)
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
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            do {
              try store.beginContentEdit(
                reference, contentID: detail.id,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines), body: bodyText)
              dismiss()
            } catch { errorMessage = error.localizedDescription }
          }
          .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
  }
}

struct MobilePendingOperations: View {
  @Bindable var store: ProjectStore
  let projectID: String?

  var body: some View {
    ForEach(store.pendingCreationList.filter { projectID == nil || $0.projectID == projectID }) {
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
      store.pendingEditList.filter { projectID == nil || $0.reference.projectID == projectID }
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
