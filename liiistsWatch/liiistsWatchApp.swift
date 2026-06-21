import SwiftUI

@main
struct LiiistsWatchApp: App {
    @StateObject private var phone = WatchPhoneClient.shared
    @StateObject private var catalog = WatchCatalogStore.shared
    @StateObject private var router = WatchRouter()

    init() {
        WatchPhoneClient.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
                .environmentObject(phone)
                .environmentObject(catalog)
                .environmentObject(router)
                .tint(Theme.ndAccent)
                .onOpenURL { url in
                    router.handle(url: url, catalog: catalog)
                }
        }
    }
}

/// Routes complication deep-links into the watch app's navigation state.
/// Complications use `widgetURL(_:)` to fire URLs like `liiists://dictate`
/// or `liiists://list/<filename>`; this router translates those into
/// per-screen state nudges that WatchHomeView observes.
@MainActor
final class WatchRouter: ObservableObject {
    /// When set, WatchHomeView shows DictateView as a sheet.
    @Published var pendingDictation: Bool = false
    /// When set, WatchHomeView pushes the corresponding list onto its stack.
    @Published var pendingList: WatchCatalogEntry?

    func handle(url: URL, catalog: WatchCatalogStore) {
        guard url.scheme == "liiists" else { return }
        switch url.host {
        case "dictate":
            pendingDictation = true
        case "list":
            let filename = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !filename.isEmpty else { return }
            let decoded = filename.removingPercentEncoding ?? filename
            pendingList = catalog.entry(filename: decoded)
        case "home":
            break
        default:
            break
        }
    }
}
