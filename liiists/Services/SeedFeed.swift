import Foundation

/// Static seed content for the Discover feed so the social surface has
/// something to look at before real users start publishing. Seeds are
/// identified by a `seed-` prefix on `recordName`; PublishStore short-
/// circuits toggleUpvote on those records to do a local-only count
/// update instead of writing to CloudKit.
enum SeedFeed {

    /// All seed lists, in their canonical order. Final feed sort is done
    /// by PublishStore by merging these with the real fetched records.
    static let lists: [PublishedListSummary] = [
        PublishedListSummary(
            recordName: "seed-ambient-electronica",
            title: "Top ambient electronica albums",
            items: [
                "Music Has the Right to Children — Boards of Canada",
                "Selected Ambient Works Volume II — Aphex Twin",
                "Untrue — Burial",
                "Ravedeath, 1972 — Tim Hecker",
                "Substrata — Biosphere",
                "Person Pitch — Panda Bear",
                "Geogaddi — Boards of Canada",
                "Loveless — My Bloody Valentine"
            ],
            authorDisplayName: "ambient_listener",
            publishedAt: Date(timeIntervalSinceNow: -3 * 24 * 60 * 60),
            upvoteCount: 47
        ),
        PublishedListSummary(
            recordName: "seed-calgary-restaurants",
            title: "Calgary restaurants",
            items: [
                "Pigeonhole",
                "Model Milk",
                "Major Tom",
                "River Cafe",
                "Ten Foot Henry",
                "Native Tongues",
                "Anju",
                "Foreign Concept"
            ],
            authorDisplayName: "yyc_eats",
            publishedAt: Date(timeIntervalSinceNow: -1 * 24 * 60 * 60),
            upvoteCount: 23
        ),
        PublishedListSummary(
            recordName: "seed-indoor-plants",
            title: "Indoor plants I own",
            items: [
                "Monstera deliciosa",
                "Fiddle leaf fig",
                "Snake plant",
                "Pothos",
                "ZZ plant",
                "Bird of paradise",
                "Rubber plant",
                "Philodendron"
            ],
            authorDisplayName: nil,
            publishedAt: Date(timeIntervalSinceNow: -5 * 60 * 60),
            upvoteCount: 18
        ),
        PublishedListSummary(
            recordName: "seed-winter-rereads",
            title: "Books I reread every winter",
            items: [
                "The Lord of the Rings — J.R.R. Tolkien",
                "Wind, Sand and Stars — Antoine de Saint-Exupéry",
                "Annihilation — Jeff VanderMeer",
                "The Long Way to a Small, Angry Planet — Becky Chambers",
                "Pilgrim at Tinker Creek — Annie Dillard"
            ],
            authorDisplayName: "reading_chair",
            publishedAt: Date(timeIntervalSinceNow: -6 * 24 * 60 * 60),
            upvoteCount: 12
        ),
        PublishedListSummary(
            recordName: "seed-productivity-tools",
            title: "Productivity tools that actually work",
            items: [
                "Things 3",
                "Obsidian",
                "Raycast",
                "Linear",
                "Arc"
            ],
            authorDisplayName: nil,
            publishedAt: Date(timeIntervalSinceNow: -12 * 60 * 60),
            upvoteCount: 8
        )
    ]

    static func isSeed(recordName: String) -> Bool {
        recordName.hasPrefix("seed-")
    }
}
