import SwiftUI

@main
struct liiistsApp: App {
    @StateObject private var store = ListStore()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(store)
        }
    }
}
