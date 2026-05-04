import SwiftUI

struct ListView: View {
    @EnvironmentObject private var store: ListStore
    @EnvironmentObject private var account: AccountStore
    @EnvironmentObject private var publish: PublishStore
    @EnvironmentObject private var intelligence: IntelligenceStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var list: ItemList
    @State private var newItemText = ""
    @State private var showRename = false
    @State private var renameText = ""
    @State private var showDeleteConfirm = false
    @State private var showUnpublishConfirm = false
    @State private var searchText = ""
    @State private var showSearch = false
    @State private var isAdding = false
    @State private var showPublishOnboarding = false
    @State private var publishAfterOnboarding = false
    @State private var showEULA = false
    @State private var showSuggestMore = false
    @FocusState private var isAddFieldFocused: Bool
    @FocusState private var isSearchFocused: Bool
    @AppStorage("social_engaged") private var socialEngaged: Bool = false

    private var isPublished: Bool {
        publish.isPublished(filename: list.filename)
    }

    /// Whether to render the "Suggest More" overflow entry. Hidden entirely
    /// for streak lists (decision 011) and on devices without Apple
    /// Intelligence. The disabled-when-N<2 case shows the entry but greys it.
    private var showSuggestMoreEntry: Bool {
        list.type != .streak && intelligence.aiAvailable
    }

    var isNewList: Bool = false

    init(list: ItemList, focusAddField: Bool = false) {
        _list = State(initialValue: list)
        self.isNewList = focusAddField
    }

    private var filteredItems: [ListItem] {
        guard !searchText.isEmpty else { return list.items }
        let query = searchText.lowercased()
        return list.items.filter { $0.text.lowercased().contains(query) }
    }

    /// Whether to show the add-item field
    private var addFieldVisible: Bool {
        list.items.isEmpty || isAdding
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title + search/plus icons
            HStack(alignment: .top) {
                Text(list.title)
                    .font(Theme.headingFont(size: Theme.headingSize, weight: .medium))
                    .foregroundStyle(Theme.ndTextDisplay.resolve(for: colorScheme))
                    .tracking(-0.01 * Theme.headingSize)
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
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(Theme.ndTextPrimary.resolve(for: colorScheme))
                        .frame(width: 36, height: 36)
                }
                Button {
                    startAdding()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(Theme.ndTextPrimary.resolve(for: colorScheme))
                        .frame(width: 36, height: 36)
                }
                overflowMenu
            }
            .padding(.horizontal, Theme.spaceMD)
            .padding(.top, Theme.spaceLG)
            .padding(.bottom, isPublished ? Theme.spaceXS : (showSearch ? Theme.spaceSM : Theme.spaceMD))

            if isPublished {
                publicChip
                    .padding(.horizontal, Theme.spaceMD)
                    .padding(.bottom, showSearch ? Theme.spaceSM : Theme.spaceMD)
            }

            // Expandable search bar
            if showSearch {
                HStack(spacing: Theme.spaceSM) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .light))
                        .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                    TextField("Search\u{2026}", text: $searchText)
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
                .padding(.bottom, Theme.spaceSM)
            }

            // Add item field
            if addFieldVisible {
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
                        .submitLabel(.done)
                        .tint(.blue)
                        .onSubmit {
                            addItem()
                        }
                        .onChange(of: newItemText) { _, newValue in
                            if newValue.contains(where: { $0.isNewline }) {
                                addItem()
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
            }

            // Items
            List {
                ForEach(searchText.isEmpty ? $list.items : .constant(filteredItems)) { $item in
                    ItemRow(item: $item, listType: list.type) {
                        Theme.lightHaptic()
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowSeparatorTint(Theme.ndBorder.resolve(for: colorScheme))
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = item.text
                            Theme.lightHaptic()
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        Button(role: .destructive) {
                            if let idx = list.items.firstIndex(where: { $0.id == item.id }) {
                                list.items.remove(at: idx)
                                Theme.lightHaptic()
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
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
                .onMove { source, destination in
                    list.items.move(fromOffsets: source, toOffset: destination)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable {
                await Task { @MainActor in
                    let dir = SharedContainer.listsDirectory
                    let url = dir.appendingPathComponent(list.filename)
                    let coordinator = NSFileCoordinator()
                    var error: NSError?
                    coordinator.coordinate(readingItemAt: url, options: [], error: &error) { coordURL in
                        if let content = try? String(contentsOf: coordURL, encoding: .utf8) {
                            let refreshed = MarkdownParser.parse(content: content, filename: list.filename)
                            list.items = refreshed.items
                        }
                    }
                }.value
            }
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
        .alert("Publish error", isPresented: Binding(
            get: { publish.lastError != nil },
            set: { if !$0 { publish.clearError() } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(publish.lastError ?? "")
        }
        .alert("Unpublish?", isPresented: $showUnpublishConfirm) {
            Button("Unpublish", role: .destructive) {
                Task { await publish.unpublish(list) }
                Analytics.listUnpublished(title: list.title)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\"\(list.title)\" will be removed from Discover. Your local copy is unchanged.")
        }
        .enableSwipeBack()
        .sheet(isPresented: $showPublishOnboarding) {
            PublishOnboardingSheet(onFinish: {
                socialEngaged = true
                if publishAfterOnboarding && account.isSignedIn {
                    if EULA.isAccepted {
                        Task { await publish.publish(list) }
                        Analytics.listPublished(title: list.title)
                        publishAfterOnboarding = false
                    } else {
                        // Defer publish until after EULA accepted
                        showEULA = true
                    }
                } else {
                    publishAfterOnboarding = false
                }
            })
            .environmentObject(account)
        }
        .sheet(isPresented: $showEULA) {
            EULASheet(
                onAccept: {
                    if publishAfterOnboarding {
                        Task { await publish.publish(list) }
                        Analytics.listPublished(title: list.title)
                        publishAfterOnboarding = false
                    }
                },
                onDecline: {
                    publishAfterOnboarding = false
                }
            )
        }
        .sheet(isPresented: $showSuggestMore) {
            SuggestMoreSheet(list: list) { selected in
                appendSuggestions(selected)
            }
            .environmentObject(intelligence)
        }
        .onChange(of: list) { _, newValue in
            store.update(newValue)
        }
        .onChange(of: isAddFieldFocused) { _, focused in
            if !focused && !isSubmitting {
                // Tapping away counts as enter — commit any pending text first.
                if !newItemText.trimmingCharacters(in: .whitespaces).isEmpty {
                    addItem()
                } else if !list.items.isEmpty {
                    isAdding = false
                }
            }
        }
        .onAppear {
            if isNewList || list.items.isEmpty {
                startAdding()
            }
        }
    }

    // MARK: - Overflow menu

    /// Inline ellipsis menu shown alongside search and + in the list header.
    /// Replaces the previous nav-bar trailing toolbar item so all per-list
    /// actions live in one place.
    private var overflowMenu: some View {
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

            if showSuggestMoreEntry {
                Divider()

                Button {
                    showSuggestMore = true
                } label: {
                    Label("Suggest More", systemImage: "wand.and.stars")
                }
                .disabled(list.items.count < 2)
            }

            Divider()

            if isPublished {
                Button {
                    showUnpublishConfirm = true
                } label: {
                    Label("Unpublish", systemImage: "eye.slash")
                }
            } else {
                Button {
                    handlePublishTapped()
                } label: {
                    Label(publish.isPublishing(filename: list.filename) ? "Publishing…" : "Publish to Discover",
                          systemImage: "sparkles")
                }
                .disabled(publish.isPublishing(filename: list.filename))
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
                .frame(width: 36, height: 36)
        }
    }

    // MARK: - Publish

    /// Small "Public" pill shown under the title when the list is currently
    /// in CloudKit's public DB. Decision 008 — visible safety badge so edits
    /// to a published list are never surprising.
    private var publicChip: some View {
        HStack(spacing: Theme.spaceXS) {
            Circle()
                .fill(Theme.ndAccent)
                .frame(width: 6, height: 6)
            Text("PUBLIC")
                .font(Theme.labelFont(size: Theme.labelSize))
                .tracking(Theme.labelSize * 0.1)
                .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
        }
        .padding(.horizontal, Theme.spaceSM)
        .padding(.vertical, 4)
        .background(Theme.ndSurfaceRaised.resolve(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: Theme.pillRadius))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func handlePublishTapped() {
        guard account.isSignedIn else {
            publishAfterOnboarding = true
            showPublishOnboarding = true
            return
        }
        guard EULA.isAccepted else {
            publishAfterOnboarding = true
            showEULA = true
            return
        }
        Task { await publish.publish(list) }
        Analytics.listPublished(title: list.title)
    }

    // MARK: - Add Item Logic

    private func startAdding() {
        isAdding = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isAddFieldFocused = true
        }
    }

    @State private var isSubmitting = false

    private func addItem() {
        let entries = Self.parseEntries(from: newItemText)
        guard !entries.isEmpty else {
            return
        }
        isSubmitting = true
        for entry in entries.reversed() {
            list.items.insert(ListItem(text: entry), at: 0)
        }
        Theme.lightHaptic()
        newItemText = ""
        isAdding = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isAddFieldFocused = true
            isSubmitting = false
        }
    }

    static func parseEntries(from raw: String) -> [String] {
        let lines = raw.split(whereSeparator: { $0.isNewline })
        var results: [String] = []
        for line in lines {
            var trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            // Strip common bullet markers
            let bulletPrefixes: [Character] = ["-", "*", "•", "·", "–", "—"]
            if let first = trimmed.first, bulletPrefixes.contains(first) {
                trimmed = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
            } else {
                // Strip numbered prefixes like "1." "1)" "12:"
                let scanner = Scanner(string: trimmed)
                scanner.charactersToBeSkipped = nil
                if let _ = scanner.scanCharacters(from: .decimalDigits),
                   let sep = scanner.scanCharacter(),
                   sep == "." || sep == ")" || sep == ":" {
                    trimmed = String(trimmed[scanner.currentIndex...]).trimmingCharacters(in: .whitespaces)
                }
            }
            if !trimmed.isEmpty {
                results.append(trimmed)
            }
        }
        if results.isEmpty {
            let fallback = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !fallback.isEmpty { return [fallback] }
        }
        return results
    }

    /// Append suggestions to the top of the list, animated. Mirrors `addItem`'s
    /// insertion-at-index-0 pattern so the new items show up where the user
    /// expects them.
    private func appendSuggestions(_ suggestions: [String]) {
        guard !suggestions.isEmpty else { return }
        withAnimation(Theme.nothingEasing) {
            for text in suggestions.reversed() {
                list.items.insert(ListItem(text: text), at: 0)
            }
        }
        Theme.lightHaptic()
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
    @FocusState private var isEditing: Bool
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

            TextField("", text: $item.text, axis: .vertical)
                .font(Theme.bodyFont())
                .foregroundStyle(
                    listType == .checklist && item.isChecked
                        ? Theme.ndTextDisabled.resolve(for: colorScheme)
                        : Theme.ndTextPrimary.resolve(for: colorScheme)
                )
                .focused($isEditing)
                .lineLimit(nil)

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

// MARK: - Edge swipe back gesture (T-110)
// Re-enable the interactive pop gesture even when the navigation back button
// is hidden (we use a custom Nothing-style chevron). Without this, hiding the
// system back button also disables iOS's default left-edge swipe-to-go-back.

extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
