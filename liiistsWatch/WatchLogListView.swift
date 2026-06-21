import SwiftUI

struct WatchLogListView: View {
    let entry: WatchCatalogEntry

    @EnvironmentObject var catalog: WatchCatalogStore
    @State private var showDictation = false

    private var current: WatchCatalogEntry {
        catalog.entry(filename: entry.filename) ?? entry
    }

    var body: some View {
        List {
            Section {
                Button {
                    Theme.lightHaptic()
                    showDictation = true
                } label: {
                    HStack(spacing: Theme.spaceSM) {
                        Image(systemName: "mic.fill")
                            .foregroundStyle(Theme.ndAccent)
                        Text("ADD ENTRY")
                            .font(Theme.labelFont(size: 11))
                            .tracking(1.2)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.black)
            }

            Section {
                if current.items.isEmpty {
                    Text("No entries yet.")
                        .font(Theme.bodyFont(size: 12))
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(current.items) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            if let ts = item.timestamp {
                                Text(ts.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                                    .font(Theme.labelFont(size: 9))
                                    .tracking(0.8)
                                    .foregroundStyle(.secondary)
                            }
                            Text(item.text)
                                .font(Theme.bodyFont(size: 13))
                                .lineLimit(3)
                        }
                    }
                }
            } header: {
                Text("RECENT")
                    .font(Theme.labelFont(size: 9))
                    .tracking(1)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.carousel)
        .navigationTitle(current.title)
        .sheet(isPresented: $showDictation) {
            DictateView(preselectedFilename: current.filename)
        }
    }
}
