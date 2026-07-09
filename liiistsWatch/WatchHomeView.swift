import SwiftUI

struct WatchHomeView: View {
    @EnvironmentObject var catalog: WatchCatalogStore
    @EnvironmentObject var router: WatchRouter
    @State private var showDictation = false
    @State private var path: [WatchCatalogEntry] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    Button {
                        Theme.lightHaptic()
                        showDictation = true
                    } label: {
                        HStack(spacing: Theme.spaceSM) {
                            Image(systemName: "mic.fill")
                                .foregroundStyle(Theme.ndAccent)
                            Text("DICTATE")
                                .font(Theme.labelFont(size: 13))
                                .tracking(1.5)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.black)
                }

                Section {
                    if catalog.entries.isEmpty {
                        Text("Open liiists on your iPhone to start.")
                            .font(Theme.bodyFont(size: 12))
                            .foregroundStyle(.secondary)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(catalog.entries) { entry in
                            NavigationLink(value: entry) {
                                Row(entry: entry)
                            }
                        }
                    }
                } header: {
                    Text("LISTS")
                        .font(Theme.labelFont(size: 10))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.carousel)
            .navigationTitle("liiists")
            .navigationDestination(for: WatchCatalogEntry.self) { entry in
                WatchListRouter(entry: entry)
            }
            .sheet(isPresented: $showDictation) {
                DictateView()
            }
            .onAppear { catalog.reload() }
            .onChange(of: router.pendingDictation) { _, isPending in
                if isPending {
                    showDictation = true
                    router.pendingDictation = false
                }
            }
            .onChange(of: router.pendingList) { _, entry in
                if let entry {
                    path = [entry]
                    router.pendingList = nil
                }
            }
        }
    }
}

private struct Row: View {
    let entry: WatchCatalogEntry

    var body: some View {
        HStack(spacing: Theme.spaceSM) {
            Image(systemName: typeIcon)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(Theme.bodyFont(size: 14, weight: .medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(Theme.labelFont(size: 10))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private var typeIcon: String {
        switch entry.type {
        case "checklist": return "checklist"
        case "log": return "clock"
        case "streak": return "flame"
        default: return "list.bullet"
        }
    }

    private var subtitle: String {
        switch entry.type {
        case "checklist":
            return "\(entry.checkedCount) / \(entry.itemCount)"
        case "log":
            if let latest = entry.items.first?.text, !latest.isEmpty {
                return latest
            }
            return "\(entry.itemCount) entries"
        case "streak":
            let n = entry.streak?.currentStreak ?? 0
            let unit = entry.streak?.periodIsWeek == true ? "week" : "day"
            if n == 0 { return "No streak yet" }
            return "\(n) \(unit)\(n == 1 ? "" : "s")"
        default:
            return "\(entry.itemCount) items"
        }
    }
}
