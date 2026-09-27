import SwiftUI

@main
struct GitStrideiOSApp: App {
    @State private var model = GitStrideModel()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                MobileAccountView(model: model)
            }
            .task { await model.start() }
        }
    }
}
