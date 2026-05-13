import SwiftUI

/// Typed destinations the HomeView NavigationStack pushes alongside list
/// filenames. Plain strings are still used for the per-list navigation;
/// this enum is for non-list screens like Discover.
enum HomeDestination: Hashable {
    case discover
}

enum HomeSortOption: String, CaseIterable, Identifiable {
    case manual
    case alphabetical
    case recentlyUpdated
    case itemCount

    var id: String { rawValue }

    var label: String {
        switch self {
        case .manual: return "Manual"
        case .alphabetical: return "Alphabetical"
        case .recentlyUpdated: return "Recently Updated"
        case .itemCount: return "Item Count"
        }
    }

    var icon: String {
        switch self {
        case .manual: return "line.3.horizontal"
        case .alphabetical: return "textformat"
        case .recentlyUpdated: return "clock"
        case .itemCount: return "number"
        }
    }
}

struct HomeView: View {
    @EnvironmentObject private var store: ListStore
    @EnvironmentObject private var account: AccountStore
    @EnvironmentObject private var paywall: Paywall
    @Environment(\.colorScheme) private var colorScheme
    @Binding var navigationTarget: String?
    @Binding var focusAddField: Bool
    @Binding var showNewListFromDeepLink: Bool
    @State private var showNewList = false
    @State private var showPaywall = false

    /// Streaks are hidden in v1.0. When `false`, any pre-existing
    /// `.streak` list opens in `ListView` (will appear empty since
    /// streak lists store dates, not items — markdown data on disk is
    /// preserved). Flip back to `true` to restore the dedicated
    /// `StreakListView` rendering. See log.md session 10.
    private let streaksEnabled = false
    @State private var showSettings = false
    @State private var newListTitle = ""
    @State private var newListType: ItemList.ListType = .list
    @State private var newListCadence: StreakCadence = .daily
    @State private var searchText = ""
    @State private var showSearch = false
    @State private var animatingCharIndex: Int? = nil
    @State private var showPublishOnboarding = false
    @State private var showAccountSheet = false
    @FocusState private var isSearchFocused: Bool
    @AppStorage("home_sort_option") private var sortOptionRaw: String = HomeSortOption.alphabetical.rawValue
    @AppStorage("home_manual_order") private var manualOrderRaw: String = ""
    /// Decision 008: flips true once the user either completes the publish
    /// onboarding sheet OR explicitly dismisses it. The bottom CTA is hidden
    /// permanently after that.
    @AppStorage("social_engaged") private var socialEngaged: Bool = false

    /// Bottom CTA visibility — three lists is the engagement gate.
    private var showsPublishCTA: Bool {
        !socialEngaged && store.lists.count >= 3
    }

    private var sortOption: HomeSortOption {
        HomeSortOption(rawValue: sortOptionRaw) ?? .alphabetical
    }

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

    private var sortedLists: [ItemList] {
        let base = filteredLists
        switch sortOption {
        case .alphabetical:
            return base.sorted { $0.title.lowercased() < $1.title.lowercased() }
        case .recentlyUpdated:
            return base.sorted { ($0.modifiedDate ?? .distantPast) > ($1.modifiedDate ?? .distantPast) }
        case .itemCount:
            return base.sorted { $0.itemCount > $1.itemCount }
        case .manual:
            let order = manualOrderRaw.split(separator: ",").map(String.init)
            let indexMap = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
            return base.sorted { (a, b) in
                let ia = indexMap[a.filename] ?? Int.max
                let ib = indexMap[b.filename] ?? Int.max
                if ia == ib { return a.title.lowercased() < b.title.lowercased() }
                return ia < ib
            }
        }
    }

    private func moveLists(from source: IndexSet, to destination: Int) {
        var current = sortedLists
        current.move(fromOffsets: source, toOffset: destination)
        manualOrderRaw = current.map { $0.filename }.joined(separator: ",")
        Theme.lightHaptic()
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
            .sheet(isPresented: $showPublishOnboarding) {
                PublishOnboardingSheet(onFinish: {
                    socialEngaged = true
                })
                .environmentObject(account)
            }
            .sheet(isPresented: $showAccountSheet) {
                AccountSheet()
                    .environmentObject(account)
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
                    cadence: $newListCadence,
                    onCreate: {
                        let trimmed = newListTitle.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        let newList = store.create(
                            title: trimmed,
                            type: newListType,
                            cadence: newListType == .streak ? newListCadence : nil
                        )
                        Theme.mediumHaptic()
                        newListTitle = ""
                        newListType = .list
                        newListCadence = .daily
                        showNewList = false
                        // Navigate to the new list. Streak lists don't need
                        // the add field — they show the first circle ready to tap.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            deepLinkFocusAdd = newList.type != .streak
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
                        .frame(width: 32, height: 44)
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
                        .frame(width: 32, height: 44)
                }
                overflowMenu
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
                ForEach(sortedLists) { list in
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
                .onMove(perform: sortOption == .manual ? moveLists : nil)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable {
                await Task { @MainActor in
                    store.loadAll()
                }.value
            }
            .safeAreaInset(edge: .bottom) {
                if showsPublishCTA {
                    publishCTA
                }
            }
        }
        .background(Theme.ndBlack.resolve(for: colorScheme))
        .onAppear { runTitleAnimation() }
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: String.self) { filename in
            if let list = store.lists.first(where: { $0.filename == filename }) {
                if streaksEnabled && list.type == .streak {
                    StreakListView(list: list)
                        .onAppear { deepLinkFocusAdd = false }
                } else {
                    ListView(list: list, focusAddField: deepLinkFocusAdd)
                        .onAppear { deepLinkFocusAdd = false }
                }
            }
        }
        .navigationDestination(for: HomeDestination.self) { dest in
            switch dest {
            case .discover:
                DiscoverView()
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

    /// HomeView overflow menu — consolidates sort, Discover, and account
    /// actions so the header HStack stays four buttons wide. Sort lives at
    /// the top because it's the most-used; Discover and Account live below
    /// a divider and only appear once the user is signed in.
    private var overflowMenu: some View {
        Menu {
            Picker("Sort by", selection: $sortOptionRaw) {
                ForEach(HomeSortOption.allCases) { option in
                    Label(option.label, systemImage: option.icon)
                        .tag(option.rawValue)
                }
            }

            if account.isSignedIn {
                Divider()
                Button {
                    path.append(HomeDestination.discover)
                } label: {
                    Label("Discover lists", systemImage: "sparkles")
                }
                Button {
                    showAccountSheet = true
                } label: {
                    Label("Account", systemImage: "person.crop.circle")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(Theme.ndTextPrimary.resolve(for: colorScheme))
                .frame(width: 32, height: 44)
        }
    }

    /// Subtle text-link CTA pinned to the bottom of HomeView. Visible only
    /// once the user has 3+ lists and hasn't engaged with publish onboarding.
    /// Decision 008.
    private var publishCTA: some View {
        Button {
            showPublishOnboarding = true
        } label: {
            HStack(spacing: Theme.spaceXS) {
                Text("Want to publish a list?")
                    .font(Theme.bodyFont(size: Theme.bodySM))
                    .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.spaceMD)
            .background(Theme.ndBlack.resolve(for: colorScheme))
        }
        .buttonStyle(.plain)
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

    private var typeIcon: String {
        switch list.type {
        case .streak: return "flame"
        case .checklist: return "checklist"
        case .list: return "list.bullet"
        }
    }

    private var badge: String? {
        if !searchQuery.isEmpty && matchingItemCount > 0 {
            return "\(matchingItemCount) match\(matchingItemCount == 1 ? "" : "es")"
        }
        switch list.type {
        case .streak:
            return list.streakCadence?.displayLabel.lowercased()
        case .checklist:
            return list.itemCount > 0 ? "\(list.checkedCount)/\(list.itemCount)" : nil
        case .list:
            return list.itemCount > 0 ? "\(list.itemCount)" : nil
        }
    }

    var body: some View {
        HStack(spacing: Theme.spaceSM) {
            // Type icon
            Image(systemName: typeIcon)
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(
                    list.type == .streak
                        ? Theme.ndAccent
                        : Theme.ndTextSecondary.resolve(for: colorScheme)
                )
                .frame(width: 24)

            Text(list.title)
                .font(Theme.bodyFont())
                .foregroundStyle(Theme.ndTextPrimary.resolve(for: colorScheme))

            if let badge {
                Text(badge)
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
    @Binding var cadence: StreakCadence
    var onCreate: () -> Void
    var onCancel: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isFocused: Bool

    /// Streaks are hidden in v1.0. Flip back to `true` to reactivate the
    /// new-list segment button and the cadence picker. Underlying
    /// `ListType.streak`, `StreakCadence`, `StreakListView`, `StreakStats`,
    /// and `StreakWidget` infrastructure stays in place; the streak case
    /// just isn't user-creatable. See log.md session 10.
    private let streaksEnabled = false

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
                    if streaksEnabled {
                        segmentButton(label: "STREAK", icon: "flame", type: .streak)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: Theme.cornerRadius)
                        .strokeBorder(Theme.ndBorderVisible.resolve(for: colorScheme), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
            }
            .padding(.horizontal, Theme.spaceMD)

            // Cadence picker — only when STREAK is selected
            if listType == .streak {
                Spacer().frame(height: Theme.spaceLG)

                VStack(alignment: .leading, spacing: Theme.spaceSM) {
                    Text("CADENCE")
                        .nothingLabel(color: Theme.ndTextSecondary.resolve(for: colorScheme))

                    HStack(spacing: 0) {
                        cadenceButton(label: "DAILY", value: .daily)
                        cadenceButton(label: "WEEKDAYS", value: .weekdays)
                        cadenceButton(label: "3/WEEK", value: .threePerWeek)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: Theme.cornerRadius)
                            .strokeBorder(Theme.ndBorderVisible.resolve(for: colorScheme), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                }
                .padding(.horizontal, Theme.spaceMD)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Spacer()
        }
        .background(Theme.ndSurface.resolve(for: colorScheme))
        .onAppear { isFocused = true }
    }

    private func cadenceButton(label: String, value: StreakCadence) -> some View {
        let isActive = cadence == value
        return Button {
            withAnimation(.easeOut(duration: Theme.microDuration)) {
                cadence = value
            }
        } label: {
            Text(label)
                .font(Theme.labelFont(size: Theme.labelSize))
                .tracking(Theme.labelSize * 0.06)
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

