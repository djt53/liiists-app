import SwiftUI

@main
struct liiistsApp: App {
    @StateObject private var store = ListStore()
    @StateObject private var account: AccountStore
    @StateObject private var publish: PublishStore
    @StateObject private var intelligence = IntelligenceStore()
    @StateObject private var paywall = Paywall.shared
    @State private var navigationTarget: String?
    @State private var focusAddField = false
    @State private var showNewListFromDeepLink = false

    init() {
        Analytics.setup()
        Analytics.identify(userID: nil, isSignedIn: false, isPro: false)
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
                .environmentObject(paywall)
                .preferredColorScheme(.dark)
                .tint(Theme.ndAccent)
                .task {
                    await account.refreshCredentialState()
                    Analytics.identify(userID: account.appleUserID, isSignedIn: account.isSignedIn, isPro: paywall.isPro)
                    store.republishHook = { [weak publish] list in
                        publish?.republishIfNeeded(list)
                    }
                    // Pull moderator's ejection list — guideline 1.2.
                    await publish.fetchEjectedAuthors()
                }
                .onChange(of: account.state) { _, _ in
                    Analytics.identify(userID: account.appleUserID, isSignedIn: account.isSignedIn, isPro: paywall.isPro)
                }
                .onChange(of: paywall.isPro) { _, _ in
                    Analytics.identify(userID: account.appleUserID, isSignedIn: account.isSignedIn, isPro: paywall.isPro)
                }
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
    }

    private func handleDeepLink(_ url: URL) {
        // Universal link from `liiists link` QR (T-35). Routing-only for now;
        // T-34 will plumb in security-scoped bookmark consumption of ?path=….
        if url.scheme == "https",
           url.host() == "davidtingle.com",
           url.path == "/liiists/link" {
            return
        }

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
