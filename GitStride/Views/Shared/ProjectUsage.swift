import SwiftUI

/// Each presentation keeps its project alive; only foreground content requests automatic refresh.
private struct ProjectUsage: ViewModifier {
    let store: ProjectStore
    let projectIDs: Set<String>
    let refresh: Bool
    @State private var usageID = UUID()
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onAppear(perform: update)
            .onChange(of: projectIDs) { _, _ in update() }
            .onChange(of: refresh) { _, _ in update() }
            .onChange(of: scenePhase) { _, _ in update() }
            .onDisappear { store.removeProjectUsage(usageID) }
    }

    private func update() {
        store.setProjectUsage(usageID, projectIDs: projectIDs, refresh: refresh && scenePhase == .active)
    }
}

extension View {
    func projectUsage(store: ProjectStore, projectIDs: Set<String>, refresh: Bool = true) -> some View {
        modifier(ProjectUsage(store: store, projectIDs: projectIDs, refresh: refresh))
    }
}
