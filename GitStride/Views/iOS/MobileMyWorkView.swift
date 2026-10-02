import SwiftUI

struct MobileMyWorkView: View {
    @Bindable var model: GitStrideModel
    @State private var filter: MyWorkFilter = .assigned
    @State private var search = ""
    @State private var selection = Set<ItemInspectorReference>()
    @State private var selecting = false

    private var items: [MyWorkItem] {
        model.myWorkItems(for: filter).filter {
            ![$0.item].matching(search, currentUserLogin: model.projectStore.currentUserLogin)
                .isEmpty
        }
    }

    var body: some View {
        List {
            Picker("Filter", selection: $filter) {
                ForEach(MyWorkFilter.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
            }
            MobilePendingOperations(store: model.projectStore, projectID: nil)
            ForEach(items) { work in
                if selecting {
                    Button {
                        let reference = ItemInspectorReference(
                            projectID: work.project.id, itemID: work.item.id)
                        if !selection.insert(reference).inserted { selection.remove(reference) }
                    } label: {
                        HStack {
                            Image(
                                systemName: selection.contains(
                                    ItemInspectorReference(
                                        projectID: work.project.id, itemID: work.item.id))
                                    ? "checkmark.circle.fill" : "circle")
                            MobileItemRow(item: work.item)
                        }
                    }
                } else {
                    NavigationLink {
                        MobileItemDetailView(
                            store: model.projectStore,
                            reference: ItemInspectorReference(
                                projectID: work.project.id, itemID: work.item.id))
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            MobileItemRow(item: work.item)
                            Text(work.project.title).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if items.isEmpty && !model.projectStore.isLoadingFollowedProjects {
                ContentUnavailableView(
                    "No Items", systemImage: "tray",
                    description: Text(
                        model.myWorkStore.followedProjects.isEmpty
                            ? String(localized: "Follow projects to see your work here.")
                            : String(localized: "No items match the current filters.")))
            }
            if model.projectStore.isLoadingFollowedProjects { ProgressView() }
            if let error = model.myWorkErrorMessage { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("My Work")
        .toolbar {
            Button(selecting ? String(localized: "Done") : String(localized: "Select")) {
                selecting.toggle()
                selection.removeAll()
            }
        }
        .safeAreaInset(edge: .bottom) {
            if selecting {
                MobileBatchActions(store: model.projectStore, items: items, selection: $selection)
            }
        }
        .searchable(text: $search)
        .refreshable { await model.refreshMyWork() }
        .onChange(of: items.map(\.id)) { _, _ in
            let visible = Set(
                items.map { ItemInspectorReference(projectID: $0.project.id, itemID: $0.item.id) })
            selection.formIntersection(visible)
        }
    }
}
