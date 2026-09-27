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
  private var statuses: [String] {
    guard let first = selected.first else { return [] }
    return first.project.statusOptions.map(\.name).filter { name in
      selected.allSatisfy { $0.project.statusOptions.contains { $0.name == name } }
    }
  }
  private var canEdit: Bool {
    !selected.isEmpty
      && selected.allSatisfy {
        store.statusChangeUnavailableReason(
          ItemInspectorReference(projectID: $0.project.id, itemID: $0.item.id)) == nil
      }
  }

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
    let targets = selected
    isWorking = true
    errorMessage = nil
    Task {
      defer { isWorking = false }
      do {
        for work in targets {
          if let status, let field = work.project.statusField,
            let option = field.options.first(where: { $0.name == status })
          {
            try await store.moveItemToStatus(
              projectID: work.project.id, itemID: work.item.id,
              fieldID: field.id, optionID: option.id)
          } else if status == nil {
            try await store.archiveItem(work.item, in: work.project.id)
          }
          selection.remove(ItemInspectorReference(projectID: work.project.id, itemID: work.item.id))
        }
      } catch { errorMessage = error.localizedDescription }
    }
  }
}
