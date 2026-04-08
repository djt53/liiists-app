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
            /// Sortable so the Discover feed can show "X items" without fetching
            /// the body.
            static let itemCount = "itemCount"
            /// CKReference to the author's CKUser record (public DB).
            static let authorRef = "authorRef"
            /// Snapshot of the author's chosen display name at publish/update time.
            /// `nil` means anonymous (decision 006).
            static let authorDisplayName = "authorDisplayName"
            static let publishedAt = "publishedAt"
            static let updatedAt = "updatedAt"
            /// Denormalized counter incremented client-side on every Upvote create.
            /// Eventually consistent — fine at v1 scale (decision 006).
            static let upvoteCount = "upvoteCount"
            /// Original local filename, used by the author to find/unpublish their
            /// own list. Not exposed in the feed.
            static let sourceFilename = "sourceFilename"
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

    // MARK: - Report (deferred to T-51i)

    enum Report {
        static let recordType = "Report"

        enum Field {
            static let listRef = "listRef"
            static let reporterRef = "reporterRef"
            static let reason = "reason"
            static let createdAt = "createdAt"
        }
    }
}
