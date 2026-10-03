import SwiftUI

struct MobileBatchActions: View {
    let store: ProjectStore
    let items: [MyWorkItem]
    @Binding var selection: Set<ItemInspectorReference>
    @State private var isWorking = false
    @State private var confirmingArchive = false
    @State private var errorMessage: String?

    private var selected: [MyWorkItem] {
        items.filter {
            selection.contains(ItemInspectorReference(projectID: $0.project.id, itemID: $0.item.id))
        }
    }
    private var selectedReferences: [ItemInspectorReference] {
        selected.map { ItemInspectorReference(projectID: $0.project.id, itemID: $0.item.id) }
    }
    private var statuses: [String] { store.commonStatuses(for: selectedReferences) }
    private var canEdit: Bool { store.canEditItems(selectedReferences) }

    var body: some View {
        VStack {
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
            HStack {
                Text("\(selection.count) selected").font(.caption)
                Spacer()
                if isWorking { ProgressView() }
                Menu("Status") {
                    ForEach(statuses, id: \.self) { name in
                        Button(name) { apply(status: name) }
                    }
                }
                .disabled(!canEdit || isWorking)
                Button("Archive", role: .destructive) { confirmingArchive = true }
                    .disabled(!canEdit || isWorking)
            }
        }
        .padding().background(.bar)
        .confirmationDialog("Archive selected items?", isPresented: $confirmingArchive) {
            Button("Archive", role: .destructive) { apply(status: nil) }
        }
    }

    private func apply(status: String?) {
        let targets = selectedReferences
        isWorking = true
        errorMessage = nil
        Task {
            defer { isWorking = false }
            do {
                try await store.performBatch(status.map(ProjectStore.BatchAction.moveToStatus) ?? .archive, on: targets) { reference in
                    selection.remove(reference)
                }
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
