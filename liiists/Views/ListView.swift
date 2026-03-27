import SwiftUI

struct ListView: View {
    @EnvironmentObject private var store: ListStore
    @State private var list: ItemList
    @State private var newItemText = ""
    @FocusState private var isAddFieldFocused: Bool

    init(list: ItemList) {
        _list = State(initialValue: list)
    }

    var body: some View {
        List {
            // Items
            ForEach($list.items) { $item in
                ItemRow(item: $item, listType: list.type)
            }
            .onDelete(perform: deleteItems)
            .onMove(perform: moveItems)

            // Add item field
            HStack(spacing: 12) {
                if list.type == .checklist {
                    Image(systemName: "circle")
                        .foregroundStyle(.tertiary)
                }
                TextField("Add item…", text: $newItemText)
                    .focused($isAddFieldFocused)
                    .onSubmit(addItem)
            }
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .navigationTitle(list.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                EditButton()
            }
        }
        .onChange(of: list) { _, newValue in
            store.update(newValue)
        }
    }

    private func addItem() {
        let text = newItemText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        list.items.append(ListItem(text: text))
        newItemText = ""
        isAddFieldFocused = true
    }

    private func deleteItems(at offsets: IndexSet) {
        list.items.remove(atOffsets: offsets)
    }

    private func moveItems(from source: IndexSet, to destination: Int) {
        list.items.move(fromOffsets: source, toOffset: destination)
    }
}

// MARK: - Item Row

struct ItemRow: View {
    @Binding var item: ListItem
    let listType: ItemList.ListType

    var body: some View {
        HStack(spacing: 12) {
            if listType == .checklist {
                Button {
                    item.isChecked.toggle()
                } label: {
                    Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(item.isChecked ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }

            Text(item.text)
                .strikethrough(listType == .checklist && item.isChecked)
                .foregroundStyle(listType == .checklist && item.isChecked ? .secondary : .primary)
        }
    }
}
