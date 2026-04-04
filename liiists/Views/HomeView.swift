import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: ListStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var showNewList = false
    @State private var newListTitle = ""
    @State private var newListType: ItemList.ListType = .list

    var body: some View {
        NavigationStack {
            Group {
                if !store.isLoaded {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.ndBlack.resolve(for: colorScheme))
                } else if store.lists.isEmpty {
                    EmptyStateView(onCreateList: { showNewList = true })
                } else {
                    listsView
                }
            }
            .toolbar {
                if !store.lists.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showNewList = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .light))
                                .foregroundStyle(Theme.ndTextPrimary.resolve(for: colorScheme))
                        }
                    }
                }
            }
            .sheet(isPresented: $showNewList) {
                NewListSheet(
                    title: $newListTitle,
                    listType: $newListType,
                    onCreate: {
                        let trimmed = newListTitle.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        _ = store.create(title: trimmed, type: newListType)
                        Theme.mediumHaptic()
                        newListTitle = ""
                        newListType = .list
                        showNewList = false
                    }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private var listsView: some View {
        ScrollView {
            // Display title — Doto, hero-sized
            HStack {
                Text("liiists")
                    .font(Theme.displayFont(size: Theme.displayLG))
                    .foregroundStyle(Theme.ndTextDisplay.resolve(for: colorScheme))
                    .tracking(-0.02 * Theme.displayLG)
                Spacer()
            }
            .padding(.horizontal, Theme.spaceMD)
            .padding(.top, Theme.spaceXL)
            .padding(.bottom, Theme.spaceLG)

            // List rows
            LazyVStack(spacing: 0) {
                ForEach(store.lists) { list in
                    NavigationLink(value: list.id) {
                        ListRow(list: list)
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .overlay(Theme.ndBorder.resolve(for: colorScheme))
                }
            }
            .padding(.horizontal, Theme.spaceMD)
        }
        .background(Theme.ndBlack.resolve(for: colorScheme))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: UUID.self) { listId in
            if let list = store.lists.first(where: { $0.id == listId }) {
                ListView(list: list)
            }
        }
    }
}

// MARK: - List Row

struct ListRow: View {
    let list: ItemList
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: Theme.spaceSM) {
            // Type icon — monoline, no fill
            Image(systemName: list.type == .checklist ? "checklist" : "list.bullet")
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: Theme.spaceXS) {
                Text(list.title)
                    .font(Theme.bodyFont())
                    .foregroundStyle(Theme.ndTextPrimary.resolve(for: colorScheme))

                if list.type == .checklist && list.itemCount > 0 {
                    Text("\(list.checkedCount) OF \(list.itemCount)")
                        .nothingLabel(color: Theme.ndTextSecondary.resolve(for: colorScheme))
                } else if list.itemCount > 0 {
                    Text("\(list.itemCount) ITEMS")
                        .nothingLabel(color: Theme.ndTextSecondary.resolve(for: colorScheme))
                }
            }

            Spacer()
        }
        .frame(minHeight: Theme.rowMinHeight)
        .padding(.vertical, Theme.spaceSM)
    }
}

// MARK: - New List Sheet

struct NewListSheet: View {
    @Binding var title: String
    @Binding var listType: ItemList.ListType
    var onCreate: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack {
                Button {
                    title = ""
                    listType = .list
                } label: {
                    Text("CANCEL")
                        .font(Theme.labelFont(size: 13))
                        .textCase(.uppercase)
                        .tracking(13 * 0.06)
                        .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                }

                Spacer()

                Button(action: onCreate) {
                    Text("CREATE")
                        .font(Theme.labelFont(size: 13))
                        .textCase(.uppercase)
                        .tracking(13 * 0.06)
                        .foregroundStyle(
                            title.trimmingCharacters(in: .whitespaces).isEmpty
                                ? Theme.ndTextDisabled.resolve(for: colorScheme)
                                : Theme.ndTextDisplay.resolve(for: colorScheme)
                        )
                        .padding(.horizontal, Theme.spaceLG)
                        .padding(.vertical, Theme.spaceSM)
                        .background(
                            title.trimmingCharacters(in: .whitespaces).isEmpty
                                ? Theme.ndSurfaceRaised.resolve(for: colorScheme)
                                : Theme.ndTextDisplay.resolve(for: colorScheme)
                        )
                        .foregroundStyle(
                            title.trimmingCharacters(in: .whitespaces).isEmpty
                                ? Theme.ndTextDisabled.resolve(for: colorScheme)
                                : Theme.ndBlack.resolve(for: colorScheme)
                        )
                        .clipShape(Capsule())
                }
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, Theme.spaceMD)
            .padding(.top, Theme.spaceLG)

            Spacer().frame(height: Theme.space2XL)

            // Title input — underline style
            VStack(alignment: .leading, spacing: Theme.spaceSM) {
                Text("LIST NAME")
                    .nothingLabel(color: Theme.ndTextSecondary.resolve(for: colorScheme))

                TextField("", text: $title)
                    .font(Theme.headingFont(size: Theme.headingSize))
                    .foregroundStyle(Theme.ndTextDisplay.resolve(for: colorScheme))
                    .focused($isFocused)
                    .submitLabel(.done)
                    .onSubmit(onCreate)
                    .padding(.bottom, Theme.spaceSM)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .frame(height: 1)
                            .foregroundStyle(
                                isFocused
                                    ? Theme.ndTextPrimary.resolve(for: colorScheme)
                                    : Theme.ndBorderVisible.resolve(for: colorScheme)
                            )
                    }
            }
            .padding(.horizontal, Theme.spaceMD)

            Spacer().frame(height: Theme.spaceXL)

            // Type picker — segmented control
            VStack(alignment: .leading, spacing: Theme.spaceSM) {
                Text("TYPE")
                    .nothingLabel(color: Theme.ndTextSecondary.resolve(for: colorScheme))

                HStack(spacing: 0) {
                    segmentButton(label: "LIST", icon: "list.bullet", type: .list)
                    segmentButton(label: "CHECKLIST", icon: "checklist", type: .checklist)
                }
                .background(
                    RoundedRectangle(cornerRadius: Theme.cornerRadius)
                        .strokeBorder(Theme.ndBorderVisible.resolve(for: colorScheme), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
            }
            .padding(.horizontal, Theme.spaceMD)

            Spacer()
        }
        .background(Theme.ndSurface.resolve(for: colorScheme))
        .onAppear { isFocused = true }
    }

    private func segmentButton(label: String, icon: String, type: ItemList.ListType) -> some View {
        let isActive = listType == type
        return Button {
            withAnimation(.easeOut(duration: Theme.microDuration)) {
                listType = type
            }
        } label: {
            HStack(spacing: Theme.spaceXS) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .light))
                Text(label)
                    .font(Theme.labelFont(size: Theme.labelSize))
                    .tracking(Theme.labelSize * 0.06)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .foregroundStyle(
                isActive
                    ? Theme.ndBlack.resolve(for: colorScheme)
                    : Theme.ndTextSecondary.resolve(for: colorScheme)
            )
            .background(
                isActive
                    ? Theme.ndTextDisplay.resolve(for: colorScheme)
                    : .clear
            )
        }
        .buttonStyle(.plain)
    }
}
