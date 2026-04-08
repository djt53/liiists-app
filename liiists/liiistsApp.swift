import SwiftUI

@main
struct liiistsApp: App {
    @StateObject private var store = ListStore()
    @StateObject private var account = AccountStore()
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
                .environmentObject(account)
                .preferredColorScheme(.dark)
                .tint(Theme.ndAccent)
                .task {
                    await account.refreshCredentialState()
                }
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
