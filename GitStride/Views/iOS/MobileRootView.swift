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
