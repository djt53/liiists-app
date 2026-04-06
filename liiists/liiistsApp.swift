import SwiftUI

@main
struct liiistsApp: App {
    @StateObject private var store = ListStore()
    @State private var navigationTarget: String?
    @State private var focusAddField = false

    init() {
        Analytics.setup()
    }

    var body: some Scene {
        WindowGroup {
            HomeView(navigationTarget: $navigationTarget, focusAddField: $focusAddField)
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(Theme.ndAccent)
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "liiists" else { return }
        let host = url.host()
        let filename = url.pathComponents.dropFirst().joined(separator: "/")

        switch host {
        case "list":
            navigationTarget = filename
        case "add":
            navigationTarget = filename
            focusAddField = true
        default:
            break
        }
    }
}
