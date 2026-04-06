import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: ListStore
    @EnvironmentObject private var paywall: Paywall
    @Environment(\.colorScheme) private var colorScheme
    @Binding var navigationTarget: String?
    @Binding var focusAddField: Bool
    @Binding var showNewListFromDeepLink: Bool
    @State private var showNewList = false
    @State private var showPaywall = false
    @State private var showSettings = false
    @State private var newListTitle = ""
    @State private var newListType: ItemList.ListType = .list
    @State private var searchText = ""
    @State private var showSearch = false
    @State private var animatingCharIndex: Int? = nil
    @FocusState private var isSearchFocused: Bool

    /// Whether the user is allowed to create another list right now.
    private var canCreateAnotherList: Bool {
        paywall.canCreateList(currentCount: store.lists.count)
    }

    /// Centralized "+" tap handler — gates on Pro status.
    private func attemptCreateList() {
        if canCreateAnotherList {
            showNewList = true
        } else {
            showPaywall = true
        }
    }

    private var filteredLists: [ItemList] {
        guard !searchText.isEmpty else { return store.lists }
        let query = searchText.lowercased()
        return store.lists.filter { list in
            list.title.lowercased().contains(query) ||
            list.items.contains { $0.text.lowercased().contains(query) }
        }
    }

    @State private var path = NavigationPath()
    @State private var deepLinkFocusAdd = false

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if !store.isLoaded {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.ndBlack.resolve(for: colorScheme))
                } else if store.lists.isEmpty {
                    EmptyStateView(onCreateList: { attemptCreateList() })
                } else {
                    listsView
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallSheet(paywall: paywall, reason: "list_cap_reached")
            }
            .sheet(isPresented: $showSettings) {
                SettingsSheet(paywall: paywall)
            }
            .sheet(isPresented: $showNewList) {
                NewListSheet(
                    title: $newListTitle,
                    listType: $newListType,
                    onCreate: {
                        let trimmed = newListTitle.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        let newList = store.create(title: trimmed, type: newListType)
                        Theme.mediumHaptic()
                        newListTitle = ""
                        newListType = .list
                        showNewList = false
                        // Navigate to the new list
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            deepLinkFocusAdd = true
                            path.append(newList.filename)
                        }
                    },
                    onCancel: {
                        showNewList = false
                    }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private var listsView: some View {
        VStack(spacing: 0) {
            // Display title + plus button
            HStack(alignment: .center) {
                HStack(spacing: -0.02 * Theme.displayLG) {
                    let title = Array("liiists")
                    ForEach(Array(title.enumerated()), id: \.offset) { index, char in
                        Text(String(char))
                            .font(Theme.displayFont(size: Theme.displayLG))
                            .foregroundStyle(
                                animatingCharIndex == index
                                    ? Theme.ndAccent
                                    : Theme.ndTextDisplay.resolve(for: colorScheme)
                            )
                    }
                }
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showSearch.toggle()
                        if showSearch {
                            isSearchFocused = true
                        } else {
                            searchText = ""
                        }
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(Theme.ndTextPrimary.resolve(for: colorScheme))
                        .frame(width: 44, height: 44)
                }
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(Theme.ndTextPrimary.resolve(for: colorScheme))
                        .frame(width: 44, height: 44)
                }
                Button {
                    attemptCreateList()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(Theme.ndTextPrimary.resolve(for: colorScheme))
                        .frame(width: 44, height: 44)
                }
            }
            .padding(.horizontal, Theme.spaceMD)
            .padding(.top, Theme.space3XL)
            .padding(.bottom, showSearch ? Theme.spaceSM : Theme.spaceLG)

            // Search bar (expandable)
            if showSearch {
                HStack(spacing: Theme.spaceSM) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .light))
                        .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                    TextField("Search lists\u{2026}", text: $searchText)
                        .font(Theme.bodyFont())
                        .foregroundStyle(Theme.ndTextPrimary.resolve(for: colorScheme))
                        .focused($isSearchFocused)
                    Button {
                        searchText = ""
                        showSearch = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                    }
                }
                .padding(.horizontal, Theme.spaceMD)
                .padding(.vertical, Theme.spaceSM)
                .background(Theme.ndSurfaceRaised.resolve(for: colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                .padding(.horizontal, Theme.spaceMD)
                .padding(.bottom, Theme.spaceLG)
            }

            // List rows
            List {
                ForEach(filteredLists) { list in
                    NavigationLink(value: list.filename) {
                        ListRow(list: list, searchQuery: searchText)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: Theme.spaceMD, bottom: 0, trailing: Theme.spaceMD))
                    .listRowSeparatorTint(Theme.ndBorder.resolve(for: colorScheme))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            store.delete(list)
                            Theme.mediumHaptic()
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable {
                await Task { @MainActor in
                    store.loadAll()
                }.value
            }
        }
        .background(Theme.ndBlack.resolve(for: colorScheme))
        .onAppear { runTitleAnimation() }
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: String.self) { filename in
            if let list = store.lists.first(where: { $0.filename == filename }) {
                ListView(list: list, focusAddField: deepLinkFocusAdd)
                    .onAppear { deepLinkFocusAdd = false }
            }
        }
        .onChange(of: navigationTarget) { _, filename in
            guard let filename, store.lists.contains(where: { $0.filename == filename }) else { return }
            deepLinkFocusAdd = focusAddField
            path.append(filename)
            navigationTarget = nil
            focusAddField = false
        }
        .onChange(of: showNewListFromDeepLink) { _, newValue in
            if newValue {
                attemptCreateList()
                showNewListFromDeepLink = false
            }
        }
    }

    private func runTitleAnimation() {
        let charCount = 6 // "liiists" = 7 chars, indices 0-6
        let startDelay = 0.4
        let perChar = 0.1

        for i in 0...charCount {
            DispatchQueue.main.asyncAfter(deadline: .now() + startDelay + Double(i) * perChar) {
                withAnimation(.easeInOut(duration: 0.12)) {
                    animatingCharIndex = i
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + startDelay + Double(charCount + 1) * perChar) {
            withAnimation(.easeOut(duration: 0.2)) {
                animatingCharIndex = nil
            }
        }
    }
}

// MARK: - List Row

struct ListRow: View {
    let list: ItemList
    var searchQuery: String = ""
    @Environment(\.colorScheme) private var colorScheme

    private var matchingItemCount: Int {
        guard !searchQuery.isEmpty else { return 0 }
        let query = searchQuery.lowercased()
        return list.items.filter { $0.text.lowercased().contains(query) }.count
    }

    var body: some View {
        HStack(spacing: Theme.spaceSM) {
            // Type icon
            Image(systemName: list.type == .checklist ? "checklist" : "list.bullet")
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                .frame(width: 24)

            Text(list.title)
                .font(Theme.bodyFont())
                .foregroundStyle(Theme.ndTextPrimary.resolve(for: colorScheme))

            if !searchQuery.isEmpty && matchingItemCount > 0 {
                Text("\(matchingItemCount) match\(matchingItemCount == 1 ? "" : "es")")
                    .nothingLabel(color: Theme.ndTextSecondary.resolve(for: colorScheme))
            } else if list.type == .checklist && list.itemCount > 0 {
                Text("\(list.checkedCount)/\(list.itemCount)")
                    .nothingLabel(color: Theme.ndTextSecondary.resolve(for: colorScheme))
            } else if list.itemCount > 0 {
                Text("\(list.itemCount)")
                    .nothingLabel(color: Theme.ndTextSecondary.resolve(for: colorScheme))
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
    var onCancel: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isFocused: Bool

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack {
                Button {
                    title = ""
                    listType = .list
                    onCancel()
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
                            isValid
                                ? Theme.ndBlack.resolve(for: colorScheme)
                                : Theme.ndTextDisabled.resolve(for: colorScheme)
                        )
                        .padding(.horizontal, Theme.spaceLG)
                        .padding(.vertical, Theme.spaceSM)
                        .background(
                            isValid
                                ? Theme.ndTextPrimary.resolve(for: colorScheme)
                                : Theme.ndSurfaceRaised.resolve(for: colorScheme)
                        )
                        .clipShape(Capsule())
                }
                .disabled(!isValid)
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
