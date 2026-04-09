import SwiftUI

/// The Discover surface — two columns: Trending (top-by-upvotes-7d feed)
/// and Saved (lists the user has bookmarked). T-51e + tweaks pass 1.
struct DiscoverView: View {
    @EnvironmentObject private var publish: PublishStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    enum FeedTab: String, CaseIterable, Identifiable {
        case trending = "Trending"
        case saved = "Saved"
        var id: String { rawValue }
    }

    @State private var section: FeedTab = .trending
    @State private var hasLoaded = false
    @State private var animatingCharIndex: Int? = nil

    private var displayedRows: [PublishedListSummary] {
        switch section {
        case .trending: return publish.feed
        case .saved: return publish.savedSummaries
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            sectionPicker
                .padding(.horizontal, Theme.spaceMD)
                .padding(.bottom, Theme.spaceMD)

            content
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
        .navigationDestination(for: PublishedListSummary.self) { summary in
            PublicListView(summary: summary)
        }
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await publish.loadFeed()
        }
        .refreshable {
            if section == .trending {
                await publish.loadFeed()
            }
        }
        .onAppear { runTitleAnimation() }
        .enableSwipeBack()
    }

    @ViewBuilder
    private var content: some View {
        if section == .trending && publish.isLoadingFeed && publish.feed.isEmpty {
            Spacer()
            ProgressView()
                .tint(Theme.ndTextSecondary.resolve(for: colorScheme))
            Spacer()
        } else if displayedRows.isEmpty {
            if section == .trending { emptyTrending } else { emptySaved }
        } else {
            feedList(rows: displayedRows)
        }
    }

    // MARK: - Header (Doto display title with red animation, mirroring HomeView)

    private var header: some View {
        HStack(alignment: .center) {
            HStack(spacing: -0.02 * Theme.displayLG) {
                let title = Array("diiiscover")
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
        }
        .padding(.horizontal, Theme.spaceMD)
        .padding(.top, Theme.space3XL)
        .padding(.bottom, Theme.spaceLG)
    }

    // MARK: - FeedTab picker

    private var sectionPicker: some View {
        Picker("FeedTab", selection: $section) {
            ForEach(FeedTab.allCases) { s in
                Text(s.rawValue).tag(s)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Empty states

    private var emptyTrending: some View {
        VStack(spacing: Theme.spaceMD) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 32, weight: .ultraLight))
                .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
            Text("Nothing here yet")
                .font(Theme.bodyFont(weight: .medium))
                .foregroundStyle(Theme.ndTextPrimary.resolve(for: colorScheme))
            Text("Be the first to publish a list.")
                .font(Theme.bodyFont(size: Theme.bodySM))
                .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptySaved: some View {
        VStack(spacing: Theme.spaceMD) {
            Spacer()
            Image(systemName: "bookmark")
                .font(.system(size: 32, weight: .ultraLight))
                .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
            Text("Nothing saved yet")
                .font(Theme.bodyFont(weight: .medium))
                .foregroundStyle(Theme.ndTextPrimary.resolve(for: colorScheme))
            Text("Tap the bookmark on a list to save it for later.")
                .font(Theme.bodyFont(size: Theme.bodySM))
                .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.spaceLG)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Shared list renderer

    private func feedList(rows: [PublishedListSummary]) -> some View {
        List {
            ForEach(rows) { summary in
                NavigationLink(value: summary) {
                    DiscoverRow(summary: summary)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: Theme.spaceSM, leading: Theme.spaceMD, bottom: Theme.spaceSM, trailing: Theme.spaceMD))
                .listRowSeparatorTint(Theme.ndBorder.resolve(for: colorScheme))
                .onAppear {
                    if section == .trending && summary.id == publish.feed.last?.id {
                        Task { await publish.fetchNextFeedPage() }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Title animation (mirrors HomeView)

    private func runTitleAnimation() {
        let charCount = 9 // "Diiiscover" = 10 chars, indices 0-9
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

// MARK: - Row

private struct DiscoverRow: View {
    let summary: PublishedListSummary
    @EnvironmentObject private var publish: PublishStore
    @Environment(\.colorScheme) private var colorScheme

    private var isUpvoted: Bool {
        publish.upvotedRecordNames.contains(summary.recordName)
    }

    private var authorLine: String {
        let author = summary.authorDisplayName.map { "@\($0)" } ?? "Anonymous"
        let items = "\(summary.itemCount) item\(summary.itemCount == 1 ? "" : "s")"
        return "\(author) · \(items) · \(relativeTime(from: summary.publishedAt))"
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.spaceMD) {
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.title)
                    .font(Theme.bodyFont(size: Theme.subheadingSize, weight: .medium))
                    .foregroundStyle(Theme.ndTextPrimary.resolve(for: colorScheme))
                    .lineLimit(2)
                Text(authorLine)
                    .font(Theme.bodyFont(size: Theme.bodySM))
                    .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.spaceSM)
            VStack(spacing: 2) {
                Image(systemName: isUpvoted ? "arrowtriangle.up.fill" : "arrowtriangle.up")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(isUpvoted ? Theme.ndAccent : Theme.ndTextSecondary.resolve(for: colorScheme))
                Text("\(summary.upvoteCount)")
                    .font(Theme.monoFont(size: Theme.bodySM))
                    .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
            }
            .frame(minWidth: 32)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func relativeTime(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 3600 {
            let m = Int(interval / 60)
            return m <= 1 ? "just now" : "\(m)m ago"
        }
        if interval < 86400 {
            return "\(Int(interval / 3600))h ago"
        }
        let days = Int(interval / 86400)
        if days < 7 { return "\(days)d ago" }
        let weeks = days / 7
        return "\(weeks)w ago"
    }
}
