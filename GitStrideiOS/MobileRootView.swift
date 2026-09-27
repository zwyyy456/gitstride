import SwiftUI

struct MobileRootView: View {
  @Bindable var model: GitStrideModel

  var body: some View {
    Group {
      if model.projectStore.currentAccount == nil {
        NavigationStack { MobileAccountView(model: model) }
      } else {
        TabView {
          NavigationStack { MobileMyWorkView(model: model) }
            .tabItem { Label("My Work", systemImage: "tray") }
          MobileProjectsView(model: model)
            .tabItem { Label("Projects", systemImage: "rectangle.stack") }
          NavigationStack { MobileAccountView(model: model) }
            .tabItem { Label("Settings", systemImage: "gear") }
        }
      }
    }
    .id(model.connectionID)
  }
}

struct MobileProjectsView: View {
  @Bindable var model: GitStrideModel
  @State private var search = ""
  @State private var creatingProject = false
  private var store: ProjectStore { model.projectStore }

  var body: some View {
    NavigationSplitView {
      List {
        Section {
          Picker(
            "Owner",
            selection: Binding(
              get: { store.selectedOwnerId },
              set: { id in
                if let owner = store.owners.first(where: { $0.id == id }) {
                  Task { await store.selectOwner(owner) }
                }
              }
            )
          ) {
            ForEach(store.owners) { Text($0.login).tag(Optional($0.id)) }
          }
        }
        Section("Projects") {
          ForEach(
            store.projects.filter {
              search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)
            }
          ) { project in
            NavigationLink {
              MobileProjectView(model: model, projectID: project.id)
            } label: {
              HStack {
                Text(project.title)
                Spacer()
                if model.myWorkStore.isFollowing(project.id) {
                  Image(systemName: "star.fill").foregroundStyle(.secondary)
                    .accessibilityLabel("Following")
                }
              }
            }
            .swipeActions {
              Button {
                Task { await model.toggleFollowing(project) }
              } label: {
                Label(
                  model.myWorkStore.isFollowing(project.id) ? "Unfollow" : "Follow",
                  systemImage: "star")
              }
              .tint(.orange)
            }
          }
        }
        if store.isLoading { ProgressView("Loading projects…") }
        if let error = store.error { Text(error.localizedDescription).foregroundStyle(.red) }
      }
      .navigationTitle("Projects")
      .toolbar {
        Button {
          creatingProject = true
        } label: {
          Label("New Project", systemImage: "plus")
        }
        .disabled(store.selectedOwner == nil)
      }
      .sheet(isPresented: $creatingProject) { MobileProjectManagement(model: model) }
      .searchable(text: $search)
      .refreshable { await store.loadProjects() }
    } detail: {
      ContentUnavailableView("Select a Project", systemImage: "rectangle.stack")
    }
  }
}

struct MobileMyWorkView: View {
  @Bindable var model: GitStrideModel
  @State private var filter: MyWorkFilter = .assigned
  @State private var search = ""
  @State private var selection = Set<ItemInspectorReference>()
  @State private var selecting = false

  private var items: [MyWorkItem] {
    model.myWorkItems(for: filter).filter {
      ![$0.item].matching(search, currentUserLogin: model.projectStore.currentUserLogin).isEmpty
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
            let reference = ItemInspectorReference(projectID: work.project.id, itemID: work.item.id)
            if !selection.insert(reference).inserted { selection.remove(reference) }
          } label: {
            HStack {
              Image(
                systemName: selection.contains(
                  ItemInspectorReference(projectID: work.project.id, itemID: work.item.id))
                  ? "checkmark.circle.fill" : "circle")
              MobileItemRow(item: work.item)
            }
          }
        } else {
          NavigationLink {
            MobileItemDetailView(
              store: model.projectStore,
              reference: ItemInspectorReference(projectID: work.project.id, itemID: work.item.id))
          } label: {
            VStack(alignment: .leading, spacing: 4) {
              MobileItemRow(item: work.item)
              Text(work.project.title).font(.caption).foregroundStyle(.secondary)
            }
          }
        }
      }
      if items.isEmpty {
        ContentUnavailableView(
          "No Items", systemImage: "tray",
          description: Text("Follow projects to see your work here."))
      }
      if model.projectStore.isLoadingFollowedProjects { ProgressView() }
      if let error = model.myWorkErrorMessage { Text(error).foregroundStyle(.red) }
    }
    .navigationTitle("My Work")
    .toolbar {
      Button(selecting ? "Done" : "Select") {
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
  }
}

struct MobileItemRow: View {
  let item: ProjectItem

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(item.displayTitle).font(.body).foregroundStyle(.primary)
      HStack {
        Text(item.repositoryName ?? String(localized: "Draft item"))
        if let number = item.number { Text("#\(number)") }
        Spacer(minLength: 4)
        if let status = item.status { Text(status) }
      }
      .font(.caption).foregroundStyle(.secondary)
    }
    .padding(.vertical, 4)
  }
}
