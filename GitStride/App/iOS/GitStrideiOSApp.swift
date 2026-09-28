import SwiftUI

@main
struct GitStrideiOSApp: App {
    @State private var model = GitStrideModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MobileRootView(model: model)
                .task { await model.start() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        model.automationSetup.setProjectEventsActive(false)
                    } else if phase == .active {
                        model.automationSetup.setProjectEventsActive(true)
                        Task { await model.refreshVisibleProjects() }
                    }
                }
        }
    }
}
