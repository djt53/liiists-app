import SwiftUI

@main
struct liiistsApp: App {
    @StateObject private var store = ListStore()
    @StateObject private var account: AccountStore
    @StateObject private var publish: PublishStore
    @StateObject private var intelligence = IntelligenceStore()
    @State private var navigationTarget: String?
    @State private var focusAddField = false
    @State private var showNewListFromDeepLink = false

    init() {
        Analytics.setup()
        let account = AccountStore()
        _account = StateObject(wrappedValue: account)
        _publish = StateObject(wrappedValue: PublishStore(account: account))
    }

    var body: some Scene {
        WindowGroup {
            HomeView(navigationTarget: $navigationTarget, focusAddField: $focusAddField, showNewListFromDeepLink: $showNewListFromDeepLink)
                .environmentObject(store)
                .environmentObject(account)
                .environmentObject(publish)
                .environmentObject(intelligence)
                .preferredColorScheme(.dark)
                .tint(Theme.ndAccent)
                .task {
                    await account.refreshCredentialState()
                    store.republishHook = { [weak publish] list in
                        publish?.republishIfNeeded(list)
                    }
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
