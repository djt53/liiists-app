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
                ItemRow(item: $item, listType: list.type) {
                    Theme.lightHaptic()
                }
            }
            .onDelete(perform: deleteItems)
            .onMove(perform: moveItems)

            // Inline add field
            Section {
                HStack(spacing: 12) {
                    if list.type == .checklist {
                        Image(systemName: "circle")
                            .font(.system(size: Theme.checkboxSize * 0.6))
                            .foregroundStyle(.quaternary)
                    }
                    TextField("Add item…", text: $newItemText)
                        .focused($isAddFieldFocused)
                        .submitLabel(.done)
                        .onSubmit(addItem)
                }
            }
        }
        .listStyle(.insetGrouped)
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
        Theme.lightHaptic()
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
    var onToggle: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            if listType == .checklist {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        item.isChecked.toggle()
                    }
                    onToggle?()
                } label: {
                    checkboxIcon
                }
                .buttonStyle(.plain)
            }

            Text(item.text)
                .font(.body)
                .foregroundStyle(listType == .checklist && item.isChecked ? .secondary : .primary)
                .strikethrough(listType == .checklist && item.isChecked, color: .secondary)
        }
        .frame(minHeight: Theme.rowMinHeight)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                // Handled by .onDelete
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var checkboxIcon: some View {
        if item.isChecked {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: Theme.checkboxSize))
                .foregroundStyle(Theme.accent)
        } else {
            Circle()
                .strokeBorder(.tertiary, lineWidth: Theme.checkboxStroke)
                .frame(width: Theme.checkboxSize, height: Theme.checkboxSize)
        }
    }
}
