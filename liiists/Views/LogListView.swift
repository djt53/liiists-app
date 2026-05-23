import SwiftUI

/// Reverse-chronological log view. Two-column layout: date on the left,
/// entry text on the right. New entries auto-stamp `now` and insert at the
/// top. Tap the date column to edit a timestamp (re-sorts on commit).
///
/// See decision 016.
struct LogListView: View {
    @EnvironmentObject private var store: ListStore
    @EnvironmentObject private var account: AccountStore
    @EnvironmentObject private var publish: PublishStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var list: ItemList
    @State private var newEntryText = ""
    @State private var showRename = false
    @State private var renameText = ""
    @State private var showDeleteConfirm = false
    @State private var showUnpublishConfirm = false
    @State private var editingItemID: UUID?
    @State private var pendingTimestamp = Date()
    @State private var showPublishOnboarding = false
    @State private var publishAfterOnboarding = false
    @State private var showEULA = false
    @State private var isAdding = false
    @State private var isSubmitting = false
    @State private var showSearch = false
    @State private var searchText = ""
    @FocusState private var isAddFieldFocused: Bool
    @FocusState private var isSearchFocused: Bool
    @AppStorage("social_engaged") private var socialEngaged: Bool = false
    @AppStorage private var showTime: Bool

    private var isPublished: Bool {
        publish.isPublished(filename: list.filename)
    }

    private var addFieldVisible: Bool {
        list.items.isEmpty || isAdding
    }

    private var filteredItems: [ListItem] {
        guard !searchText.isEmpty else { return list.items }
        let query = searchText.lowercased()
        return list.items.filter { Self.searchableText(for: $0).contains(query) }
    }

    /// Lowercased haystack covering the entry text plus the date and time as
    /// they're displayed (or commonly typed). Supports queries like "may 14",
    /// "yesterday", "2026", "14:30".
    private static func searchableText(for item: ListItem) -> String {
        var parts: [String] = [item.text]
        if let ts = item.timestamp {
            let cal = Calendar.current
            if cal.isDateInToday(ts) { parts.append("today") }
            if cal.isDateInYesterday(ts) { parts.append("yesterday") }
            for fmt in Self.searchDateFormatters {
                parts.append(fmt.string(from: ts))
            }
        }
        return parts.joined(separator: " ").lowercased()
    }

    private static let searchDateFormatters: [DateFormatter] = {
        let formats = ["MMM d", "MMMM d", "MMM d, yyyy", "yyyy-MM-dd", "yyyy", "HH:mm"]
        return formats.map { fmt in
            let f = DateFormatter()
            f.dateFormat = fmt
            f.locale = Locale(identifier: "en_US_POSIX")
            return f
        }
    }()

    init(list: ItemList) {
        _list = State(initialValue: list)
        _showTime = AppStorage(wrappedValue: false, "log_show_time_\(list.filename)")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if isPublished {
                publicChip
                    .padding(.horizontal, Theme.spaceMD)
                    .padding(.bottom, showSearch ? Theme.spaceSM : Theme.spaceMD)
            }
            if showSearch {
                searchBar
            }
            if addFieldVisible {
                addField
            }
            entriesList
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
            Text("This will permanently delete \"\(list.title)\" and all its entries.")
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
        .sheet(isPresented: Binding(
            get: { editingItemID != nil },
            set: { if !$0 { editingItemID = nil } }
        )) {
            TimestampEditSheet(
                timestamp: $pendingTimestamp,
                onCommit: {
                    if let id = editingItemID {
                        commitTimestamp(for: id)
                    }
                },
                onCancel: {
                    editingItemID = nil
                }
            )
            .presentationDetents([.fraction(0.8)])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPublishOnboarding) {
            PublishOnboardingSheet(onFinish: {
                socialEngaged = true
                if publishAfterOnboarding && account.isSignedIn {
                    if EULA.isAccepted {
                        Task { await publish.publish(list) }
                        Analytics.listPublished(title: list.title)
                        publishAfterOnboarding = false
                    } else {
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
        .enableSwipeBack()
        .onChange(of: list) { _, newValue in
            store.update(newValue)
        }
        .onChange(of: isAddFieldFocused) { _, focused in
            if !focused && !isSubmitting {
                if !newEntryText.trimmingCharacters(in: .whitespaces).isEmpty {
                    addEntry()
                } else if !list.items.isEmpty {
                    isAdding = false
                }
            }
        }
        .onAppear {
            if list.items.isEmpty {
                startAdding()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
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
    }

    private var overflowMenu: some View {
        Menu {
            Button {
                renameText = list.title
                showRename = true
            } label: {
                Label("Rename List", systemImage: "pencil")
            }

            Button {
                shareLogAsText()
            } label: {
                Label("Copy as Text", systemImage: "doc.on.doc")
            }

            Button {
                showTime.toggle()
            } label: {
                Label(showTime ? "Hide Time" : "Show Time", systemImage: "clock")
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
                    Label(publish.isPublishing(filename: list.filename) ? "Publishing\u{2026}" : "Publish to Discover",
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

    // MARK: - Search bar

    private var searchBar: some View {
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

    // MARK: - Add field

    private var addField: some View {
        HStack(spacing: Theme.spaceSM) {
            Image(systemName: "clock")
                .font(.system(size: 14, weight: .light))
                .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                .frame(width: 24)
            TextField("New entry\u{2026}", text: $newEntryText, axis: .vertical)
                .font(Theme.bodyFont())
                .foregroundStyle(Theme.ndTextPrimary.resolve(for: colorScheme))
                .focused($isAddFieldFocused)
                .submitLabel(.done)
                .tint(.blue)
                .onSubmit(addEntry)
                .onChange(of: newEntryText) { _, newValue in
                    if newValue.contains(where: { $0.isNewline }) {
                        addEntry()
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

    // MARK: - Entries

    private var entriesList: some View {
        List {
            ForEach(searchText.isEmpty ? $list.items : .constant(filteredItems)) { $item in
                LogEntryRow(item: $item, showTime: showTime) {
                    pendingTimestamp = item.timestamp ?? Date()
                    editingItemID = item.id
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
                    Button {
                        pendingTimestamp = item.timestamp ?? Date()
                        editingItemID = item.id
                    } label: {
                        Label("Edit Timestamp", systemImage: "clock.arrow.circlepath")
                    }
                    Button(role: .destructive) {
                        deleteEntry(id: item.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        deleteEntry(id: item.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

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

    // MARK: - Actions

    private func startAdding() {
        isAdding = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isAddFieldFocused = true
        }
    }

    private func addEntry() {
        let trimmed = newEntryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let now = Date()
        // Round to the minute so the on-disk representation matches what the
        // user sees in the timestamp picker.
        let rounded = roundedToMinute(now)
        let entry = ListItem(text: trimmed, timestamp: rounded)
        isSubmitting = true
        withAnimation(Theme.nothingEasing) {
            list.items.insert(entry, at: 0)
        }
        Theme.lightHaptic()
        Analytics.logEntryAdded(entryCount: list.items.count)
        newEntryText = ""
        isAdding = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isAddFieldFocused = true
            isSubmitting = false
        }
    }

    private func deleteEntry(id: UUID) {
        guard let idx = list.items.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(Theme.nothingEasing) {
            list.items.remove(at: idx)
        }
        Theme.lightHaptic()
        Analytics.logEntryDeleted()
    }

    private func commitTimestamp(for id: UUID) {
        guard let idx = list.items.firstIndex(where: { $0.id == id }) else { return }
        let rounded = roundedToMinute(pendingTimestamp)
        list.items[idx].timestamp = rounded
        list.items.sort { (a, b) in
            (a.timestamp ?? .distantPast) > (b.timestamp ?? .distantPast)
        }
        editingItemID = nil
        Theme.lightHaptic()
        Analytics.logEntryTimestampEdited()
    }

    private func roundedToMinute(_ date: Date) -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return cal.date(from: comps) ?? date
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

    private func shareLogAsText() {
        var lines = [list.title]
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        for item in list.items {
            if let ts = item.timestamp {
                lines.append("\(fmt.string(from: ts))  \(item.text)")
            } else {
                lines.append(item.text)
            }
        }
        UIPasteboard.general.string = lines.joined(separator: "\n")
        Theme.lightHaptic()
    }
}

// MARK: - Log Entry Row

struct LogEntryRow: View {
    @Binding var item: ListItem
    let showTime: Bool
    let onDateTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private static let relativeDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private var dateLabel: String {
        guard let ts = item.timestamp else { return "—" }
        let cal = Calendar.current
        if cal.isDateInToday(ts) { return "Today" }
        if cal.isDateInYesterday(ts) { return "Yesterday" }
        let now = Date()
        let f = Self.relativeDateFormatter
        if cal.component(.year, from: ts) == cal.component(.year, from: now) {
            f.dateFormat = "MMM d"
        } else {
            f.dateFormat = "MMM d, ʼyy"
        }
        return f.string(from: ts)
    }

    private var timeLabel: String {
        guard let ts = item.timestamp else { return "" }
        return Self.timeFormatter.string(from: ts)
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.spaceMD) {
            // Date column — tappable to edit timestamp.
            Button(action: onDateTap) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dateLabel)
                        .font(Theme.bodyFont(size: 14, weight: .medium))
                        .foregroundStyle(Theme.ndTextPrimary.resolve(for: colorScheme))
                    if showTime {
                        Text(timeLabel)
                            .font(Theme.bodyFont(size: 11))
                            .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                    }
                }
                .frame(width: 72, alignment: .leading)
            }
            .buttonStyle(.plain)

            TextField("", text: $item.text, axis: .vertical)
                .font(Theme.bodyFont())
                .foregroundStyle(Theme.ndTextPrimary.resolve(for: colorScheme))
                .lineLimit(nil)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: Theme.rowMinHeight)
        .padding(.horizontal, Theme.spaceMD)
        .padding(.vertical, Theme.spaceSM)
    }
}

// MARK: - Timestamp Edit Sheet

struct TimestampEditSheet: View {
    @Binding var timestamp: Date
    var onCommit: () -> Void
    var onCancel: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button {
                    onCancel()
                } label: {
                    Text("CANCEL")
                        .font(Theme.labelFont(size: 13))
                        .textCase(.uppercase)
                        .tracking(13 * 0.06)
                        .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                }

                Spacer()

                Button {
                    onCommit()
                } label: {
                    Text("SAVE")
                        .font(Theme.labelFont(size: 13))
                        .textCase(.uppercase)
                        .tracking(13 * 0.06)
                        .foregroundStyle(Theme.ndBlack.resolve(for: colorScheme))
                        .padding(.horizontal, Theme.spaceLG)
                        .padding(.vertical, Theme.spaceSM)
                        .background(Theme.ndTextPrimary.resolve(for: colorScheme))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, Theme.spaceMD)
            .padding(.top, Theme.spaceLG)

            Spacer().frame(height: Theme.space2XL)

            Text("TIMESTAMP")
                .nothingLabel(color: Theme.ndTextSecondary.resolve(for: colorScheme))
                .padding(.horizontal, Theme.spaceMD)

            DatePicker(
                "",
                selection: $timestamp,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .padding(.horizontal, Theme.spaceMD)

            Spacer()
        }
        .background(Theme.ndSurface.resolve(for: colorScheme))
    }
}
