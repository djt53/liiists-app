import Foundation
import CloudKit

/// CloudKit public-database schema for the social Discover surface.
///
/// Record types are provisioned in the CloudKit Dashboard for the
/// `iCloud.com.davidtingle.liiists` container. See `docs/cloudkit-schema.md`
/// in this repo (or the project vault) for the human-readable spec.
///
/// All field names and record-type identifiers live here so the rest of
/// the app references typed constants rather than string literals.
enum CKSchema {

    // MARK: - Containers

    static let container = CKContainer(identifier: "iCloud.com.davidtingle.liiists")
    static var publicDB: CKDatabase { container.publicCloudDatabase }
    static var privateDB: CKDatabase { container.privateCloudDatabase }

    // MARK: - PublishedList

    enum PublishedList {
        static let recordType = "PublishedList"

        enum Field {
            static let title = "title"
            /// Newline-joined item strings (one per line). Plain text — the markdown
            /// item prefix (`- `) is stripped before storing.
            static let items = "items"
            /// Denormalized count of items, kept in sync on every publish/update.
            static let itemCount = "itemCount"
            /// Snapshot of the author's chosen display name at publish/update time.
            /// `nil` means anonymous (decision 006). Authority for "who wrote this"
            /// is the CK system field `creatorUserRecordID`, not this — this is
            /// just the rendering hint.
            static let authorDisplayName = "authorDisplayName"
            /// Original local filename, used by the author to find/unpublish their
            /// own list. Not exposed in the feed.
            static let sourceFilename = "sourceFilename"

            // Removed (decision 010 — security hardening):
            // - publishedAt / updatedAt → use record.creationDate / .modificationDate
            // - authorRef → use record.creatorUserRecordID
            // - upvoteCount → count Upvote records on read instead of denormalizing
        }
    }

    // MARK: - Upvote

    enum Upvote {
        static let recordType = "Upvote"

        enum Field {
            /// CKReference to the PublishedList. Delete action: deleteSelf — when
            /// the author unpublishes, all upvotes for that list are removed.
            static let listRef = "listRef"
            /// CKReference to the voter's CKUser record. One Upvote per
            /// (list, voter) pair, enforced client-side via a query before save.
            static let voterRef = "voterRef"
        }
    }

    // MARK: - Report

    /// Apple guideline 1.2 — UGC apps need a flag mechanism. Reports go to a
    /// public-DB record type; we count distinct reporters per list and hide
    /// any list with ≥ `Report.hideThreshold` reports. Reporter identity is
    /// the CK system field `creatorUserRecordID` (decision 010 hardening).
    enum Report {
        static let recordType = "Report"

        /// Distinct-reporter threshold above which a list is hidden from
        /// every feed (not just the reporter's). Tunable.
        static let hideThreshold: Int = 3

        enum Field {
            /// CKReference to PublishedList. Delete action: deleteSelf — when
            /// a list is unpublished or removed, its reports go too.
            static let listRef = "listRef"
            /// Optional reason category — "hate", "sexual", "illegal",
            /// "spam", "other". Free-form on the wire so we can add reasons
            /// without a schema change. Empty string means unspecified.
            static let reason = "reason"
        }
    }
}
