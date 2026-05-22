import SwiftUI

/// Read-only renderer for someone else's published list. Pushed from
/// DiscoverView. T-51f + tweaks pass 1.
struct PublicListView: View {
    let summary: PublishedListSummary

    @EnvironmentObject private var publish: PublishStore
    @EnvironmentObject private var store: ListStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var newListPromptItem: String?
    @State private var newListTitle: String = ""
    @State private var copyConfirm = false
    @State private var showReportDialog = false
    @State private var reportConfirm = false
    @State private var showBlockConfirm = false
    @State private var hideConfirm = false

    private var isUpvoted: Bool {
        publish.upvotedRecordNames.contains(summary.recordName)
    }

    private var isSaved: Bool {
        publish.isSaved(summary)
    }

    /// Live summary keeps upvote count in sync with toggleUpvote optimistic
    /// updates. Falls back to the original summary if the row has scrolled
    /// out of the in-memory feed.
    private var liveSummary: PublishedListSummary {
        publish.feed.first(where: { $0.recordName == summary.recordName }) ?? summary
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            divider
            itemsList
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
        .alert("Copied to your lists", isPresented: $copyConfirm) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\"\(liveSummary.title)\" is now in your library. It won't update if the author changes the original.")
        }
        .confirmationDialog(
            "Report this list?",
            isPresented: $showReportDialog,
            titleVisibility: .visible
        ) {
            ForEach(ReportReason.allCases) { reason in
                Button(reason.label) {
                    Task {
                        await publish.report(liveSummary, reason: reason)
                        reportConfirm = true
                        // Dismiss back to Discover after a beat — the list
                        // is now hidden from the feed.
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It will be hidden from your feed. Lists reported by enough people are removed for everyone.")
        }
        .alert("Reported", isPresented: $reportConfirm) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Thanks. We review reports within 24 hours.")
        }
        .alert("Block this author?", isPresented: $showBlockConfirm) {
            Button("Block", role: .destructive) {
                publish.blockAuthor(of: liveSummary)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You won't see any lists from this author. You can unblock from Account.")
        }
        .alert("Hidden", isPresented: $hideConfirm) {
            Button("OK", role: .cancel) {
                dismiss()
            }
        } message: {
            Text("This list won't show up in your feed anymore.")
        }
        .alert("New list", isPresented: Binding(
            get: { newListPromptItem != nil },
            set: { if !$0 { newListPromptItem = nil } }
        )) {
            TextField("List name", text: $newListTitle)
            Button("Create") {
                createListFromItem()
            }
            Button("Cancel", role: .cancel) {
                newListPromptItem = nil
                newListTitle = ""
            }
        } message: {
            Text("New list with one item: \(newListPromptItem ?? "")")
        }
        .enableSwipeBack()
        .onAppear {
            Analytics.publicListViewed(title: summary.title, author: summary.authorDisplayName)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.spaceSM) {
            HStack(alignment: .top) {
                Text(liveSummary.title)
                    .font(Theme.headingFont(size: Theme.headingSize, weight: .medium))
                    .foregroundStyle(Theme.ndTextDisplay.resolve(for: colorScheme))
                    .tracking(-0.01 * Theme.headingSize)
                Spacer()
                overflowMenu
            }

            HStack(spacing: Theme.spaceXS) {
                Text(liveSummary.authorDisplayName.map { "@\($0)" } ?? "Anonymous")
                    .font(Theme.bodyFont(size: Theme.bodySM, weight: .medium))
                    .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                Text("·")
                    .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                Text("\(liveSummary.itemCount) items")
                    .font(Theme.bodyFont(size: Theme.bodySM))
                    .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
            }

            HStack(spacing: Theme.spaceSM) {
                upvotePill
                savePill
            }
            .padding(.top, Theme.spaceXS)
        }
        .padding(.horizontal, Theme.spaceMD)
        .padding(.top, Theme.spaceLG)
        .padding(.bottom, Theme.spaceMD)
    }

    private var upvotePill: some View {
        Button {
            let willUpvote = !isUpvoted
            Task { await publish.toggleUpvote(for: liveSummary) }
            Analytics.upvoteToggled(listTitle: liveSummary.title, isUpvoted: willUpvote)
        } label: {
            HStack(spacing: Theme.spaceXS) {
                Image(systemName: isUpvoted ? "arrowtriangle.up.fill" : "arrowtriangle.up")
                    .font(.system(size: 13, weight: .regular))
                Text("\(liveSummary.upvoteCount)")
                    .font(Theme.monoFont(size: Theme.bodySM, weight: .medium))
            }
            .foregroundStyle(isUpvoted ? Theme.ndAccent : Theme.ndTextPrimary.resolve(for: colorScheme))
            .padding(.horizontal, Theme.spaceMD)
            .padding(.vertical, Theme.spaceSM)
            .background(Theme.ndSurfaceRaised.resolve(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: Theme.pillRadius))
        }
        .buttonStyle(.plain)
    }

    private var savePill: some View {
        Button {
            let willSave = !isSaved
            publish.toggleSaved(liveSummary)
            Analytics.saveToggled(listTitle: liveSummary.title, isSaved: willSave)
        } label: {
            HStack(spacing: Theme.spaceXS) {
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 13, weight: .regular))
                Text(isSaved ? "Saved" : "Save")
                    .font(Theme.bodyFont(size: Theme.bodySM, weight: .medium))
            }
            .foregroundStyle(isSaved ? Theme.ndAccent : Theme.ndTextPrimary.resolve(for: colorScheme))
            .padding(.horizontal, Theme.spaceMD)
            .padding(.vertical, Theme.spaceSM)
            .background(Theme.ndSurfaceRaised.resolve(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: Theme.pillRadius))
        }
        .buttonStyle(.plain)
    }

    private var overflowMenu: some View {
        Menu {
            Button {
                copyListToLocal()
            } label: {
                Label("Copy to my lists", systemImage: "square.on.square")
            }

            Divider()

            // One-tap hide — guideline 1.2 requirement that anonymous-UGC
            // apps offer a way to immediately remove a post from the feed.
            // Distinct from Report (moderation signal) and Block (author).
            // Decision 014.
            Button {
                publish.hide(summary.recordName)
                hideConfirm = true
            } label: {
                Label("Hide this post", systemImage: "eye.slash")
            }
            .disabled(publish.isHidden(summary.recordName))

            Button(role: .destructive) {
                showReportDialog = true
            } label: {
                Label("Report", systemImage: "flag")
            }
            .disabled(publish.hasReported(summary.recordName))
            Button(role: .destructive) {
                showBlockConfirm = true
            } label: {
                Label("Block author", systemImage: "hand.raised")
            }
            .disabled(summary.authorUserID == nil
                      || (summary.authorUserID.map(publish.isAuthorBlocked(userID:)) ?? false))
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(Theme.ndTextPrimary.resolve(for: colorScheme))
                .frame(width: 36, height: 36)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.ndBorder.resolve(for: colorScheme))
            .frame(height: 1)
            .padding(.horizontal, Theme.spaceMD)
    }

    // MARK: - Items (no bullets, matches the plain "list" type from list creation)

    private var itemsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(liveSummary.items.enumerated()), id: \.offset) { _, item in
                    Text(item)
                        .font(Theme.bodyFont())
                        .foregroundStyle(Theme.ndTextPrimary.resolve(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Theme.spaceMD)
                        .padding(.vertical, Theme.spaceSM + 2)
                        .contextMenu {
                            addToListMenu(item: item)
                        }

                    Rectangle()
                        .fill(Theme.ndBorder.resolve(for: colorScheme))
                        .frame(height: 1)
                        .padding(.horizontal, Theme.spaceMD)
                }
            }
            .padding(.top, Theme.spaceMD)
        }
    }

    @ViewBuilder
    private func addToListMenu(item: String) -> some View {
        Section("Add to a list") {
            ForEach(store.lists) { list in
                Button {
                    addItem(item, to: list)
                } label: {
                    Label(list.title, systemImage: list.type == .checklist ? "checklist" : "list.bullet")
                }
            }
            Button {
                newListTitle = ""
                newListPromptItem = item
            } label: {
                Label("New list…", systemImage: "plus")
            }
        }
    }

    // MARK: - Actions

    private func addItem(_ text: String, to list: ItemList) {
        var updated = list
        updated.items.append(ListItem(text: text))
        store.update(updated)
    }

    private func createListFromItem() {
        guard let item = newListPromptItem else { return }
        let trimmed = newListTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var newList = store.create(title: trimmed, type: .list)
        newList.items.append(ListItem(text: item))
        store.update(newList)
        newListPromptItem = nil
        newListTitle = ""
    }

    private func copyListToLocal() {
        var newList = store.create(title: liveSummary.title, type: .list)
        newList.items.append(contentsOf: liveSummary.items.map { ListItem(text: $0) })
        store.update(newList)
        copyConfirm = true
        Analytics.listCopiedToLocal(title: liveSummary.title, itemCount: liveSummary.items.count)
    }
}
