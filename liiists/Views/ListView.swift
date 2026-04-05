import SwiftUI

struct ListView: View {
    @EnvironmentObject private var store: ListStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var list: ItemList
    @State private var newItemText = ""
    @State private var showRename = false
    @State private var renameText = ""
    @State private var showDeleteConfirm = false
    @FocusState private var isAddFieldFocused: Bool

    init(list: ItemList) {
        _list = State(initialValue: list)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title
            HStack {
                Text(list.title)
                    .font(Theme.headingFont(size: Theme.headingSize, weight: .medium))
                    .foregroundStyle(Theme.ndTextDisplay.resolve(for: colorScheme))
                    .tracking(-0.01 * Theme.headingSize)
                Spacer()
            }
            .padding(.horizontal, Theme.spaceMD)
            .padding(.top, Theme.spaceLG)
            .padding(.bottom, Theme.spaceMD)

            // Add item field — underline style
            HStack(spacing: Theme.spaceSM) {
                if list.type == .checklist {
                    Circle()
                        .strokeBorder(Theme.ndBorderVisible.resolve(for: colorScheme).opacity(0.5), lineWidth: Theme.checkboxStroke)
                        .frame(width: Theme.checkboxSize, height: Theme.checkboxSize)
                }
                TextField("Add item\u{2026}", text: $newItemText, axis: .vertical)
                    .font(Theme.bodyFont())
                    .foregroundStyle(Theme.ndTextPrimary.resolve(for: colorScheme))
                    .focused($isAddFieldFocused)
                    .lineLimit(1...5)
                    .submitLabel(.done)
                    .onSubmit(addItem)
                    .onChange(of: newItemText) { _, newValue in
                        // Multi-line paste: split into separate items
                        if newValue.contains("\n") {
                            let lines = newValue.components(separatedBy: "\n")
                                .map { $0.trimmingCharacters(in: .whitespaces) }
                                .filter { !$0.isEmpty }
                            for line in lines {
                                list.items.insert(ListItem(text: line), at: 0)
                            }
                            if !lines.isEmpty {
                                Theme.lightHaptic()
                            }
                            newItemText = ""
                        }
                    }
            }
            .padding(.horizontal, Theme.spaceMD)
            .padding(.bottom, Theme.spaceSM)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .frame(height: 1)
                    .foregroundStyle(
                        isAddFieldFocused
                            ? Theme.ndTextPrimary.resolve(for: colorScheme)
                            : Theme.ndBorder.resolve(for: colorScheme)
                    )
                    .padding(.horizontal, Theme.spaceMD)
            }

            // Items
            List {
                ForEach($list.items) { $item in
                    ItemRow(item: $item, listType: list.type) {
                        Theme.lightHaptic()
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowSeparatorTint(Theme.ndBorder.resolve(for: colorScheme))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            if let idx = list.items.firstIndex(where: { $0.id == item.id }) {
                                list.items.remove(at: idx)
                                Theme.lightHaptic()
                            }
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(Theme.ndBlack.resolve(for: colorScheme))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(Theme.ndTextPrimary.resolve(for: colorScheme))
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        renameText = list.title
                        showRename = true
                    } label: {
                        Label("Rename List", systemImage: "pencil")
                    }

                    Button {
                        shareListAsText()
                    } label: {
                        Label("Copy as Text", systemImage: "doc.on.doc")
                    }

                    Divider()

                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete List", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(Theme.ndTextPrimary.resolve(for: colorScheme))
                }
            }
        }
        .alert("Rename List", isPresented: $showRename) {
            TextField("List name", text: $renameText)
            Button("Save") {
                let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                store.rename(&list, to: trimmed)
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete List?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                store.delete(list)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete \"\(list.title)\" and all its items.")
        }
        .onChange(of: list) { _, newValue in
            store.update(newValue)
        }
    }

    private func addItem() {
        let text = newItemText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        list.items.insert(ListItem(text: text), at: 0)
        Theme.lightHaptic()
        newItemText = ""
        isAddFieldFocused = true
    }

    private func shareListAsText() {
        var lines = [list.title]
        for item in list.items {
            if list.type == .checklist {
                let check = item.isChecked ? "[x]" : "[ ]"
                lines.append("\(check) \(item.text)")
            } else {
                lines.append("- \(item.text)")
            }
        }
        UIPasteboard.general.string = lines.joined(separator: "\n")
        Theme.lightHaptic()
    }
}

// MARK: - Item Row

struct ItemRow: View {
    @Binding var item: ListItem
    let listType: ItemList.ListType
    @Environment(\.colorScheme) private var colorScheme
    var onToggle: (() -> Void)?

    var body: some View {
        HStack(spacing: Theme.spaceSM) {
            if listType == .checklist {
                Button {
                    withAnimation(Theme.nothingEasing) {
                        item.isChecked.toggle()
                    }
                    onToggle?()
                } label: {
                    checkboxIcon
                }
                .buttonStyle(.plain)
            }

            Text(item.text)
                .font(Theme.bodyFont())
                .foregroundStyle(
                    listType == .checklist && item.isChecked
                        ? Theme.ndTextDisabled.resolve(for: colorScheme)
                        : Theme.ndTextPrimary.resolve(for: colorScheme)
                )
                .strikethrough(
                    listType == .checklist && item.isChecked,
                    color: Theme.ndTextDisabled.resolve(for: colorScheme)
                )

            Spacer()
        }
        .frame(minHeight: Theme.rowMinHeight)
        .padding(.horizontal, Theme.spaceMD)
    }

    @ViewBuilder
    private var checkboxIcon: some View {
        if item.isChecked {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: Theme.checkboxSize))
                .foregroundStyle(Theme.ndSuccess)
        } else {
            Circle()
                .strokeBorder(Theme.ndBorderVisible.resolve(for: colorScheme), lineWidth: Theme.checkboxStroke)
                .frame(width: Theme.checkboxSize, height: Theme.checkboxSize)
        }
    }
}
