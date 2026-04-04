import SwiftUI

struct ListView: View {
    @EnvironmentObject private var store: ListStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var list: ItemList
    @State private var newItemText = ""
    @State private var showRename = false
    @State private var renameText = ""
    @FocusState private var isAddFieldFocused: Bool

    init(list: ItemList) {
        _list = State(initialValue: list)
    }

    var body: some View {
        ScrollView {
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
                TextField("Add item\u{2026}", text: $newItemText)
                    .font(Theme.bodyFont())
                    .foregroundStyle(Theme.ndTextPrimary.resolve(for: colorScheme))
                    .focused($isAddFieldFocused)
                    .submitLabel(.done)
                    .onSubmit(addItem)
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
            LazyVStack(spacing: 0) {
                ForEach($list.items) { $item in
                    ItemRow(item: $item, listType: list.type) {
                        Theme.lightHaptic()
                    }

                    Divider()
                        .overlay(Theme.ndBorder.resolve(for: colorScheme))
                        .padding(.leading, list.type == .checklist ? Theme.spaceMD + Theme.checkboxSize + Theme.spaceSM : Theme.spaceMD)
                        .padding(.trailing, Theme.spaceMD)
                }
            }
            .padding(.top, Theme.spaceSM)
        }
        .background(Theme.ndBlack.resolve(for: colorScheme))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        renameText = list.title
                        showRename = true
                    } label: {
                        Label("Rename List", systemImage: "pencil")
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
