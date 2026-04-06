import SwiftUI

@main
struct liiistsApp: App {
    @StateObject private var store = ListStore()
    @StateObject private var paywall = Paywall.shared
    @State private var navigationTarget: String?
    @State private var focusAddField = false
    @State private var showNewListFromDeepLink = false

    init() {
        Analytics.setup()
    }

    var body: some Scene {
        WindowGroup {
            HomeView(navigationTarget: $navigationTarget, focusAddField: $focusAddField, showNewListFromDeepLink: $showNewListFromDeepLink)
                .environmentObject(store)
                .environmentObject(paywall)
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
        case "new":
            showNewListFromDeepLink = true
        default:
            break
        }
    }
}
