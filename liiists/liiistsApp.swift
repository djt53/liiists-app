import SwiftUI

@main
struct liiistsApp: App {
    @StateObject private var store = ListStore()

    init() {
        Analytics.setup()
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(Theme.ndAccent)
        }
    }
}
