import Foundation
import CloudKit
import SwiftUI

/// Owns all interaction with the CloudKit public database for the social
/// Discover surface: publish/unpublish, auto-republish on local edits,
/// the top-by-upvotes feed, and upvotes.
///
/// See decisions 005 (CloudKit identity), 006 (social architecture),
/// 007 (moderation v1).
@MainActor
final class PublishStore: ObservableObject {

    // MARK: - Published state

    /// Map from local filename → CK record ID for currently-published lists.
    /// Loaded from UserDefaults on init, refreshed by `refreshPublishedIndex()`.
    @Published private(set) var publishedIndex: [String: String] = [:]

    /// Most recent Discover feed page.
    @Published private(set) var feed: [PublishedListSummary] = []

    /// Set of PublishedList record names the current user has upvoted.
    /// Loaded lazily as the feed comes in.
    @Published private(set) var upvotedRecordNames: Set<String> = []

    /// Lists the user has saved for later. Stored as full summaries (not
    /// just record names) so saved entries remain browsable even after
    /// they fall out of the trending 7-day window.
    @Published private(set) var savedSummaries: [PublishedListSummary] = []

    @Published private(set) var isLoadingFeed = false
    @Published private(set) var lastError: String?

    // MARK: - Dependencies

    private unowned let account: AccountStore

    private let publicDB = CKSchema.publicDB
    private let defaults = UserDefaults.standard
    private let publishedIndexKey = "liiists.publishedIndex"
    private let upvotedKey = "liiists.upvotedRecordNames"
    private let savedKey = "liiists.savedSummaries"

    private var feedCursor: CKQueryOperation.Cursor?

    // MARK: - Init

    init(account: AccountStore) {
        self.account = account
        loadLocalState()
    }

    // MARK: - Local cache

    private func loadLocalState() {
        if let dict = defaults.dictionary(forKey: publishedIndexKey) as? [String: String] {
            publishedIndex = dict
        }
        if let arr = defaults.stringArray(forKey: upvotedKey) {
            upvotedRecordNames = Set(arr)
        }
        if let data = defaults.data(forKey: savedKey),
           let decoded = try? JSONDecoder().decode([PublishedListSummary].self, from: data) {
            savedSummaries = decoded
        }
    }

    private func persistPublishedIndex() {
        defaults.set(publishedIndex, forKey: publishedIndexKey)
    }

    private func persistUpvoted() {
        defaults.set(Array(upvotedRecordNames), forKey: upvotedKey)
    }

    private func persistSaved() {
        if let data = try? JSONEncoder().encode(savedSummaries) {
            defaults.set(data, forKey: savedKey)
        }
    }

    func isPublished(filename: String) -> Bool {
        publishedIndex[filename] != nil
    }

    func isSaved(_ summary: PublishedListSummary) -> Bool {
        savedSummaries.contains(where: { $0.recordName == summary.recordName })
    }

    /// Toggle whether a published list lives in the user's Saved column.
    /// Local-only; doesn't write to CloudKit.
    func toggleSaved(_ summary: PublishedListSummary) {
        if let idx = savedSummaries.firstIndex(where: { $0.recordName == summary.recordName }) {
            savedSummaries.remove(at: idx)
        } else {
            // Capture the current live summary so saved entries reflect the
            // upvote count and items at save time.
            let live = feed.first(where: { $0.recordName == summary.recordName }) ?? summary
            savedSummaries.insert(live, at: 0)
        }
        persistSaved()
    }

    func clearError() {
        lastError = nil
    }

    // MARK: - Publish / unpublish

    /// Publish a list to the public DB. If it's already published, performs
    /// an update instead (auto-republish — decision 006).
    func publish(_ list: ItemList) async {
        print("[PublishStore] publish() called — signedIn=\(account.isSignedIn), filename=\(list.filename)")
        guard account.isSignedIn else {
            lastError = "Sign in to publish."
            print("[PublishStore] publish aborted — not signed in")
            return
        }

        do {
            if let existingRecordName = publishedIndex[list.filename] {
                try await updatePublished(list, recordName: existingRecordName)
            } else {
                try await createPublished(list)
            }
            lastError = nil
            print("[PublishStore] publish succeeded")
        } catch {
            let nsError = error as NSError
            lastError = "\(nsError.localizedDescription) [\(nsError.domain) \(nsError.code)]"
            print("[PublishStore] publish FAILED: \(nsError.domain) \(nsError.code) — \(nsError.localizedDescription)")
            print("[PublishStore] userInfo: \(nsError.userInfo)")
        }
    }

    private func createPublished(_ list: ItemList) async throws {
        let record = CKRecord(recordType: CKSchema.PublishedList.recordType)
        applyListFields(list, to: record, isUpdate: false)

        print("[PublishStore] saving new PublishedList for \(list.filename) — title=\(list.title), items=\(list.items.count)")
        let saved = try await publicDB.save(record)
        print("[PublishStore] saved PublishedList recordName=\(saved.recordID.recordName)")
        publishedIndex[list.filename] = saved.recordID.recordName
        persistPublishedIndex()
    }

    private func updatePublished(_ list: ItemList, recordName: String) async throws {
        let recordID = CKRecord.ID(recordName: recordName)
        let record: CKRecord
        do {
            record = try await publicDB.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            // Server-side record vanished — fall back to a fresh create.
            publishedIndex.removeValue(forKey: list.filename)
            persistPublishedIndex()
            try await createPublished(list)
            return
        }
        applyListFields(list, to: record, isUpdate: true)
        _ = try await publicDB.save(record)
    }

    /// Auto-republish hook. Call from ListStore after a local save. No-op if
    /// the list isn't currently published or the user isn't signed in.
    func republishIfNeeded(_ list: ItemList) {
        guard account.isSignedIn, isPublished(filename: list.filename) else { return }
        Task { await publish(list) }
    }

    /// Remove a published list from the public DB. Upvotes cascade away
    /// because the schema sets `Upvote.listRef`'s delete action to deleteSelf.
    func unpublish(_ list: ItemList) async {
        guard let recordName = publishedIndex[list.filename] else { return }
        let recordID = CKRecord.ID(recordName: recordName)
        do {
            _ = try await publicDB.deleteRecord(withID: recordID)
            publishedIndex.removeValue(forKey: list.filename)
            persistPublishedIndex()
            lastError = nil
        } catch {
            lastError = (error as NSError).localizedDescription
        }
    }

    private func applyListFields(_ list: ItemList, to record: CKRecord, isUpdate: Bool) {
        // Decision 010: only client-controlled fields go on the record. Author,
        // timestamps, and upvote count are derived from CK system fields and
        // separately-counted Upvote records on read.
        let itemTexts = list.items.map { $0.text }
        record[CKSchema.PublishedList.Field.title] = list.title as CKRecordValue
        record[CKSchema.PublishedList.Field.items] = itemTexts.joined(separator: "\n") as CKRecordValue
        record[CKSchema.PublishedList.Field.itemCount] = itemTexts.count as CKRecordValue
        record[CKSchema.PublishedList.Field.authorDisplayName] = (account.displayName ?? "") as CKRecordValue
        record[CKSchema.PublishedList.Field.sourceFilename] = list.filename as CKRecordValue
    }

    // MARK: - Discover feed

    /// Load the first page of the top-by-upvotes-7d feed. Resets pagination
    /// and seeds the feed with the static SeedFeed entries so the surface
    /// looks alive before real users start publishing.
    func loadFeed() async {
        isLoadingFeed = true
        feedCursor = nil
        feed = SeedFeed.lists
        await fetchNextFeedPage()
        sortFeed()
        isLoadingFeed = false
    }

    /// Sort the merged feed by upvotes desc then publishedAt desc — matches
    /// the CK query ordering so seeds and real records interleave naturally.
    private func sortFeed() {
        feed.sort { a, b in
            if a.upvoteCount != b.upvoteCount { return a.upvoteCount > b.upvoteCount }
            return a.publishedAt > b.publishedAt
        }
    }

    /// Fetch the next page of the feed using the saved cursor.
    ///
    /// Decision 010: feed is queried by CK's `creationDate` system field
    /// (server-stamped, untamperable). Upvote counts are computed by a
    /// secondary query against the Upvote record type and merged in
    /// before sort. The trending sort is then performed client-side.
    func fetchNextFeedPage() async {
        let sevenDaysAgo = Date(timeIntervalSinceNow: -7 * 24 * 60 * 60)

        let query: CKQuery
        if feedCursor == nil {
            // CK exposes the system creationDate via the special key
            // "creationDate" in NSPredicate.
            let predicate = NSPredicate(format: "creationDate > %@", sevenDaysAgo as NSDate)
            query = CKQuery(recordType: CKSchema.PublishedList.recordType, predicate: predicate)
            query.sortDescriptors = [
                NSSortDescriptor(key: "creationDate", ascending: false)
            ]
        } else {
            query = CKQuery(recordType: CKSchema.PublishedList.recordType, predicate: NSPredicate(value: true))
        }

        do {
            let result: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
            if let cursor = feedCursor {
                result = try await publicDB.records(continuingMatchFrom: cursor, resultsLimit: 25)
            } else {
                result = try await publicDB.records(matching: query, resultsLimit: 25)
            }

            var newSummaries: [PublishedListSummary] = result.matchResults.compactMap { _, recordResult in
                guard case .success(let record) = recordResult else { return nil }
                return PublishedListSummary(record: record)
            }

            // Inject upvote counts by querying Upvote records for the page.
            let counts = await fetchUpvoteCounts(for: newSummaries.map { $0.recordName })
            for i in newSummaries.indices {
                newSummaries[i].upvoteCount = counts[newSummaries[i].recordName] ?? 0
            }

            feed.append(contentsOf: newSummaries)
            sortFeed()
            feedCursor = result.queryCursor
            lastError = nil
        } catch {
            lastError = (error as NSError).localizedDescription
        }
    }

    /// Returns a map from PublishedList recordName → upvote count, computed
    /// by counting Upvote records that reference each list. Single CK query
    /// per page (uses an IN predicate), then bucket client-side.
    private func fetchUpvoteCounts(for recordNames: [String]) async -> [String: Int] {
        guard !recordNames.isEmpty else { return [:] }
        let refs = recordNames.map { CKRecord.Reference(recordID: CKRecord.ID(recordName: $0), action: .deleteSelf) }
        let predicate = NSPredicate(format: "%K IN %@", CKSchema.Upvote.Field.listRef, refs)
        let query = CKQuery(recordType: CKSchema.Upvote.recordType, predicate: predicate)

        do {
            // CK caps a single query response. 200 is plenty for our 25-record
            // page; if a single list has > 200 votes we'll undercount and
            // we can iterate via cursor. Acceptable at v1 scale.
            let result = try await publicDB.records(matching: query, resultsLimit: 200)
            var counts: [String: Int] = [:]
            for (_, recordResult) in result.matchResults {
                guard case .success(let record) = recordResult,
                      let ref = record[CKSchema.Upvote.Field.listRef] as? CKRecord.Reference else { continue }
                counts[ref.recordID.recordName, default: 0] += 1
            }
            return counts
        } catch {
            // Don't fail the whole feed load on a counting error — just show
            // zero votes and surface the error.
            print("[PublishStore] fetchUpvoteCounts failed: \(error.localizedDescription)")
            return [:]
        }
    }

    // MARK: - Upvote

    /// Toggle an upvote for the given published list. Idempotent: tapping
    /// twice removes the vote. Decision 010: there is no denormalized
    /// counter — we just create or delete the Upvote record. The displayed
    /// count is updated optimistically in the in-memory feed and recomputed
    /// from a fresh count query on the next feed refresh.
    func toggleUpvote(for summary: PublishedListSummary) async {
        // Seeds are local-only fixtures — toggle the in-memory count and
        // local upvote set without touching CloudKit.
        if summary.isSeed {
            let isUpvoted = upvotedRecordNames.contains(summary.recordName)
            if isUpvoted {
                upvotedRecordNames.remove(summary.recordName)
                if let idx = feed.firstIndex(where: { $0.recordName == summary.recordName }) {
                    feed[idx].upvoteCount = max(0, feed[idx].upvoteCount - 1)
                }
            } else {
                upvotedRecordNames.insert(summary.recordName)
                if let idx = feed.firstIndex(where: { $0.recordName == summary.recordName }) {
                    feed[idx].upvoteCount += 1
                }
            }
            persistUpvoted()
            return
        }

        guard account.isSignedIn, let voterID = account.ckUserRecordID else {
            lastError = "Sign in to upvote."
            return
        }

        let listRecordID = CKRecord.ID(recordName: summary.recordName)
        let voterRef = CKRecord.Reference(recordID: voterID, action: .none)
        let listRef = CKRecord.Reference(recordID: listRecordID, action: .deleteSelf)

        do {
            // Look for an existing upvote by this voter for this list.
            let predicate = NSPredicate(
                format: "%K == %@ AND %K == %@",
                CKSchema.Upvote.Field.listRef, listRef,
                CKSchema.Upvote.Field.voterRef, voterRef
            )
            let query = CKQuery(recordType: CKSchema.Upvote.recordType, predicate: predicate)
            let result = try await publicDB.records(matching: query, resultsLimit: 1)
            let existing = result.matchResults.compactMap { _, r -> CKRecord? in
                if case .success(let record) = r { return record }
                return nil
            }.first

            let delta: Int
            if let existing {
                _ = try await publicDB.deleteRecord(withID: existing.recordID)
                upvotedRecordNames.remove(summary.recordName)
                delta = -1
            } else {
                let upvote = CKRecord(recordType: CKSchema.Upvote.recordType)
                upvote[CKSchema.Upvote.Field.listRef] = listRef
                upvote[CKSchema.Upvote.Field.voterRef] = voterRef
                _ = try await publicDB.save(upvote)
                upvotedRecordNames.insert(summary.recordName)
                delta = 1
            }
            persistUpvoted()

            // Optimistic local update — the canonical count comes from the
            // next feed refresh / fetchUpvoteCounts call.
            if let idx = feed.firstIndex(where: { $0.recordName == listRecordID.recordName }) {
                feed[idx].upvoteCount = max(0, feed[idx].upvoteCount + delta)
            }
            lastError = nil
        } catch {
            lastError = (error as NSError).localizedDescription
        }
    }
}

// MARK: - Feed summary

/// Lightweight projection of a PublishedList for feed rendering. Avoids
/// passing CKRecord around the view layer.
struct PublishedListSummary: Identifiable, Equatable, Hashable, Codable {
    let recordName: String
    let title: String
    let items: [String]
    let itemCount: Int
    let authorDisplayName: String?
    let publishedAt: Date
    var upvoteCount: Int

    var id: String { recordName }
    var isSeed: Bool { SeedFeed.isSeed(recordName: recordName) }

    init(
        recordName: String,
        title: String,
        items: [String],
        authorDisplayName: String?,
        publishedAt: Date,
        upvoteCount: Int
    ) {
        self.recordName = recordName
        self.title = title
        self.items = items
        self.itemCount = items.count
        self.authorDisplayName = authorDisplayName
        self.publishedAt = publishedAt
        self.upvoteCount = upvoteCount
    }

    init?(record: CKRecord) {
        // Decision 010: trust CK system fields over client-set ones.
        // creationDate is server-stamped and untamperable.
        guard
            let title = record[CKSchema.PublishedList.Field.title] as? String,
            let publishedAt = record.creationDate
        else { return nil }

        self.recordName = record.recordID.recordName
        self.title = title
        let itemsBlob = (record[CKSchema.PublishedList.Field.items] as? String) ?? ""
        self.items = itemsBlob.split(separator: "\n").map(String.init)
        self.itemCount = (record[CKSchema.PublishedList.Field.itemCount] as? Int) ?? items.count
        let name = record[CKSchema.PublishedList.Field.authorDisplayName] as? String
        self.authorDisplayName = (name?.isEmpty == false) ? name : nil
        self.publishedAt = publishedAt
        // upvoteCount is filled in by PublishStore.fetchUpvoteCounts after
        // the initial decode — start at zero so the client never trusts a
        // client-supplied counter.
        self.upvoteCount = 0
    }
}
