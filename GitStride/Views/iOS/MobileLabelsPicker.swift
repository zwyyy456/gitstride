import SwiftUI

struct MobileLabelsPicker: View {
    let store: ProjectStore
    let reference: ItemInspectorReference
    @Environment(\.dismiss) private var dismiss
    @State private var labels: [RepositoryLabel] = []
    @State private var search = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if isLoading { ProgressView() }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                    Button("Retry") { Task { await load() } }
                }
                ForEach(
                    labels.filter {
                        search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)
                    }
                ) { label in
                    Button {
                        change(label)
                    } label: {
                        HStack {
                            Text(label.name).foregroundStyle(.primary)
                            Spacer()
                            if store.item(for: reference)?.labels.contains(where: {
                                $0.id == label.id
                            }) == true {
                                Image(systemName: "checkmark").accessibilityLabel("Selected")
                            }
                        }
                        .frame(minHeight: 28)
                    }
                    .disabled(isSaving)
                }
                if isSaving { ProgressView("Saving field") }
                if !isLoading && labels.isEmpty && errorMessage == nil { Text("No labels") }
            }
            .navigationTitle("Labels")
            .searchable(text: $search)
            .toolbar { Button("Done") { dismiss() } }
            .task { await load() }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do { labels = try await store.repositoryLabels(for: reference) } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func change(_ label: RepositoryLabel) {
        guard let item = store.item(for: reference) else { return }
        isSaving = true
        errorMessage = nil
        Task {
            defer { isSaving = false }
            do {
                if item.labels.contains(where: { $0.id == label.id }) {
                    try await store.removeLabel(
                        from: item, in: reference.projectID, name: label.name)
                } else {
                    try await store.addLabel(to: item, in: reference.projectID, name: label.name)
                }
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
