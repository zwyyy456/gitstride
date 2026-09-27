import SwiftUI

struct MobileProjectView: View {
  @Bindable var model: GitStrideModel
  let projectID: String
  @State private var search = ""
  @State private var filter = ProjectWorkFilter()
  @State private var showingFilters = false
  @State private var showingAdd = false
  @State private var managingProject = false
  @State private var selection = Set<ItemInspectorReference>()
  @State private var selecting = false
  private var store: ProjectStore { model.projectStore }
  private var project: Project? { store.project(id: projectID) }
  private var items: [ProjectItem] {
    filter.apply(to: project?.items ?? [], currentUserLogin: store.currentUserLogin)
      .matching(search, currentUserLogin: store.currentUserLogin)
  }

  var body: some View {
    List {
      if store.isProjectCached(projectID) {
        Label("Showing cached data", systemImage: "clock").foregroundStyle(.secondary)
      }
      MobilePendingOperations(store: store, projectID: projectID)
      ForEach(items.filter { store.pendingCreationState(for: $0.id) == nil }) { item in
        if selecting {
          Button {
            let reference = ItemInspectorReference(projectID: projectID, itemID: item.id)
            if !selection.insert(reference).inserted { selection.remove(reference) }
          } label: {
            HStack {
              Image(
                systemName: selection.contains(
                  ItemInspectorReference(projectID: projectID, itemID: item.id))
                  ? "checkmark.circle.fill" : "circle")
              MobileItemRow(item: item)
            }
          }
        } else {
          NavigationLink {
            MobileItemDetailView(
              store: store,
              reference: ItemInspectorReference(projectID: projectID, itemID: item.id))
          } label: {
            MobileItemRow(item: item)
          }
        }
      }
      if store.isLoading { ProgressView() }
      if let error = store.operationErrorMessage { Text(error).foregroundStyle(.red) }
      if items.isEmpty && !store.isLoading {
        ContentUnavailableView("No Items", systemImage: "tray")
      }
    }
    .navigationTitle(project?.title ?? String(localized: "Project"))
    .navigationBarTitleDisplayMode(.inline)
    .searchable(text: $search)
    .refreshable { await store.loadProjectDetails(id: projectID) }
    .toolbar {
      ToolbarItemGroup(placement: .primaryAction) {
        Button {
          showingAdd = true
        } label: {
          Label("Add to Project", systemImage: "plus")
        }
        .disabled(!store.canEditProject(id: projectID))
        Menu {
          if let project {
            Button(model.myWorkStore.isFollowing(projectID) ? "Unfollow" : "Follow") {
              Task { await model.toggleFollowing(project) }
            }
            Link("Open in GitHub", destination: URL(string: project.url)!)
          }
          Button("Manage Project") { managingProject = true }.disabled(
            !store.canManageProject(id: projectID))
        } label: {
          Label("Project", systemImage: "ellipsis.circle")
        }
        Button(selecting ? "Done" : "Select") {
          selecting.toggle()
          selection.removeAll()
        }

        Button {
          showingFilters = true
        } label: {
          Label(
            "Filter",
            systemImage: filter.isActive
              ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
      }
    }
    .safeAreaInset(edge: .bottom) {
      if selecting, let project {
        MobileBatchActions(
          store: store,
          items: items.map { MyWorkItem(project: project, item: $0) }, selection: $selection)
      }
    }
    .sheet(isPresented: $managingProject) {
      if let project { MobileProjectManagement(model: model, project: project) }
    }
    .sheet(isPresented: $showingAdd) { MobileAddItemView(store: store) }
    .sheet(isPresented: $showingFilters) {
      if let project { MobileFilterView(project: project, filter: $filter) }
    }
    .task(id: projectID) {
      if let project { await model.openProject(project) }
    }
  }
}

struct MobileFilterView: View {
  let project: Project
  @Binding var filter: ProjectWorkFilter
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Toggle("Assigned to Me", isOn: $filter.assignedToMe)
        Picker("Completion", selection: $filter.completion) {
          ForEach(ProjectWorkCompletion.allCases) { Text($0.title).tag($0) }
        }
        Section("Status") {
          ForEach(project.statusOptions) { status in
            Toggle(
              status.name,
              isOn: Binding(
                get: { filter.statusIDs.contains(status.id) },
                set: {
                  if $0 {
                    filter.statusIDs.insert(status.id)
                  } else {
                    filter.statusIDs.remove(status.id)
                  }
                }
              ))
          }
        }
        Section {
          Picker("Label", selection: $filter.labelID) {
            Text("All").tag(String?.none)
            ForEach(labels, id: \.id) { Text($0.name).tag(Optional($0.id)) }
          }
          Picker("Issue Type", selection: $filter.issueTypeID) {
            Text("All").tag(String?.none)
            ForEach(issueTypes) { Text($0.name).tag(Optional($0.id)) }
          }
          Picker("Milestone", selection: $filter.milestoneID) {
            Text("All").tag(String?.none)
            ForEach(milestones) { Text($0.displayName).tag(Optional($0.id)) }
          }
          Picker("Parent Issue", selection: $filter.parentIssueID) {
            Text("All").tag(String?.none)
            ForEach(parents) { Text($0.displayName).tag(Optional($0.id)) }
          }
        }
        Button("Clear Filters") { filter = ProjectWorkFilter() }
      }
      .navigationTitle("Filter")
      .toolbar { Button("Done") { dismiss() } }
    }
  }

  private var labels: [IssueLabel] {
    var seen = Set<String>()
    return project.items.flatMap(\.labels).filter { seen.insert($0.id).inserted }.sorted {
      $0.name < $1.name
    }
  }
  private var issueTypes: [ProjectIssueType] {
    var seen = Set<String>()
    return project.items.compactMap(\.issueType).filter { seen.insert($0.id).inserted }
  }
  private var milestones: [ProjectPlanningReference] {
    var seen = Set<String>()
    return project.items.compactMap(\.milestone).filter { seen.insert($0.id).inserted }
  }
  private var parents: [ProjectPlanningReference] {
    var seen = Set<String>()
    return project.items.compactMap(\.parentIssue).filter { seen.insert($0.id).inserted }
  }
}
