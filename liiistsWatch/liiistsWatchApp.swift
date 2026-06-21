import SwiftUI

@main
struct LiiistsWatchApp: App {
    @StateObject private var phone = WatchPhoneClient.shared

    init() {
        WatchPhoneClient.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(phone)
        }
    }
}

private struct ContentView: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("liiists")
                .font(.system(.title3, design: .monospaced))
                .fontWeight(.bold)
            Text("watch scaffold")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}
