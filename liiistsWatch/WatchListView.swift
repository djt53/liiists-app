import SwiftUI

/// Routes to the right list view based on entry type.
struct WatchListRouter: View {
    let entry: WatchCatalogEntry

    var body: some View {
        switch entry.type {
        case "log":
            WatchLogListView(entry: entry)
        case "checklist":
            WatchListView(entry: entry, isChecklist: true)
        default:
            WatchListView(entry: entry, isChecklist: false)
        }
    }
}

struct WatchListView: View {
    let entry: WatchCatalogEntry
    let isChecklist: Bool

    @EnvironmentObject var catalog: WatchCatalogStore
    @EnvironmentObject var phone: WatchPhoneClient

    /// Optimistic local override — flips immediately on tap, reverts only
    /// if the iPhone reports a failure. The catalog refresh from the
    /// iPhone side replaces this once it lands.
    @State private var localChecked: [UUID: Bool] = [:]

    /// Snapshot of the catalog entry. Reloaded from `catalog` whenever it
    /// publishes — keeps the view in sync after iPhone-side updates.
    private var current: WatchCatalogEntry {
        catalog.entry(filename: entry.filename) ?? entry
    }

    var body: some View {
        List {
            if current.items.isEmpty {
                Text("Empty list. Add an item from your iPhone or dictate one.")
                    .font(Theme.bodyFont(size: 12))
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(current.items) { item in
                    row(for: item)
                }
            }
        }
        .listStyle(.carousel)
        .navigationTitle(current.title)
    }

    @ViewBuilder
    private func row(for item: WatchCatalogItem) -> some View {
        let isOn = localChecked[item.id] ?? item.isChecked
        if isChecklist {
            Button {
                toggle(item: item)
            } label: {
                HStack(spacing: Theme.spaceSM) {
                    Image(systemName: isOn ? "checkmark.square.fill" : "square")
                        .foregroundStyle(isOn ? Theme.ndAccent : .secondary)
                        .font(.system(size: 16))
                    Text(item.text)
                        .font(Theme.bodyFont(size: 14))
                        .strikethrough(isOn, color: .secondary)
                        .foregroundStyle(isOn ? .secondary : .primary)
                        .lineLimit(2)
                }
            }
            .buttonStyle(.plain)
        } else {
            HStack(alignment: .top, spacing: Theme.spaceSM) {
                Text("·")
                    .foregroundStyle(.secondary)
                Text(item.text)
                    .font(Theme.bodyFont(size: 14))
                    .lineLimit(3)
            }
        }
    }

    private func toggle(item: WatchCatalogItem) {
        let next = !(localChecked[item.id] ?? item.isChecked)
        localChecked[item.id] = next
        Theme.lightHaptic()
        phone.send(.toggleItem(filename: current.filename, itemID: item.id)) { error in
            if error != nil {
                // Revert optimistic state on failure.
                localChecked[item.id] = !next
                Theme.warningHaptic()
            }
        }
    }
}
