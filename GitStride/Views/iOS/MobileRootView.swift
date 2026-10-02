import SwiftUI

struct MobileRootView: View {
    @Bindable var model: GitStrideModel
    @State private var selectedProjectID: String?
    @State private var selection: Tab = .myWork
    private enum Tab { case myWork, projects, following, settings }

    var body: some View {
        Group {
            if model.projectStore.currentAccount == nil {
                NavigationStack { MobileAccountView(model: model) }
            } else {
                TabView(selection: $selection) {
                    NavigationStack { MobileMyWorkView(model: model) }
                        .tabItem { Label("My Work", systemImage: "tray") }.tag(Tab.myWork)
                    MobileProjectsView(model: model, selectedProjectID: $selectedProjectID)
                        .tabItem { Label("Projects", systemImage: "rectangle.stack") }.tag(Tab.projects)
                    NavigationStack {
                        MobileFollowedWorkView(model: model, browseProjects: { selection = .projects })
                    }
                    .tabItem { Label(String(localized: "Following Tab", defaultValue: "Following"), systemImage: "star") }.tag(Tab.following)
                    NavigationStack { MobileSettingsView(model: model) }
                        .tabItem { Label("Settings", systemImage: "gear") }.tag(Tab.settings)
                }
            }
        }
        .projectUsage(store: model.projectStore, projectIDs: Set(selectedProjectID.map { [$0] } ?? []),
                      refresh: selection == .projects)
        .id(model.connectionID)
        .onChange(of: model.connectionID) { _, _ in selectedProjectID = nil }
    }
}
