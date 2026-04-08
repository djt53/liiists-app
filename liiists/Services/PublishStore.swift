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

    @Published private(set) var isLoadingFeed = false
    @Published private(set) var lastError: String?

    // MARK: - Dependencies

    private unowned let account: AccountStore

    private let publicDB = CKSchema.publicDB
    private let defaults = UserDefaults.standard
    private let publishedIndexKey = "liiists.publishedIndex"
    private let upvotedKey = "liiists.upvotedRecordNames"

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
    }

    private func persistPublishedIndex() {
        defaults.set(publishedIndex, forKey: publishedIndexKey)
    }

    private func persistUpvoted() {
        defaults.set(Array(upvotedRecordNames), forKey: upvotedKey)
    }

    func isPublished(filename: String) -> Bool {
        publishedIndex[filename] != nil
    }

    // MARK: - Publish / unpublish

    /// Publish a list to the public DB. If it's already published, performs
    /// an update instead (auto-republish — decision 006).
    func publish(_ list: ItemList) async {
        guard account.isSignedIn else {
            lastError = "Sign in to publish."
            return
        }

        do {
            if let existingRecordName = publishedIndex[list.filename] {
                try await updatePublished(list, recordName: existingRecordName)
            } else {
                try await createPublished(list)
            }
            lastError = nil
        } catch {
            lastError = (error as NSError).localizedDescription
        }
    }

    private func createPublished(_ list: ItemList) async throws {
        let record = CKRecord(recordType: CKSchema.PublishedList.recordType)
        applyListFields(list, to: record, isUpdate: false)

        let saved = try await publicDB.save(record)
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
        let now = Date()
        let itemTexts = list.items.map { $0.text }
        record[CKSchema.PublishedList.Field.title] = list.title as CKRecordValue
        record[CKSchema.PublishedList.Field.items] = itemTexts.joined(separator: "\n") as CKRecordValue
        record[CKSchema.PublishedList.Field.itemCount] = itemTexts.count as CKRecordValue
        record[CKSchema.PublishedList.Field.authorDisplayName] = (account.displayName ?? "") as CKRecordValue
        record[CKSchema.PublishedList.Field.updatedAt] = now as CKRecordValue
        record[CKSchema.PublishedList.Field.sourceFilename] = list.filename as CKRecordValue

        if !isUpdate {
            record[CKSchema.PublishedList.Field.publishedAt] = now as CKRecordValue
            record[CKSchema.PublishedList.Field.upvoteCount] = 0 as CKRecordValue
            if let userID = account.ckUserRecordID {
                let ref = CKRecord.Reference(recordID: userID, action: .none)
                record[CKSchema.PublishedList.Field.authorRef] = ref
            }
        }
    }

    // MARK: - Discover feed

    /// Load the first page of the top-by-upvotes-7d feed. Resets pagination.
    func loadFeed() async {
        isLoadingFeed = true
        feedCursor = nil
        feed = []
        await fetchNextFeedPage()
        isLoadingFeed = false
    }

    /// Fetch the next page of the feed using the saved cursor.
    func fetchNextFeedPage() async {
        let sevenDaysAgo = Date(timeIntervalSinceNow: -7 * 24 * 60 * 60)

        let query: CKQuery
        if feedCursor == nil {
            let predicate = NSPredicate(
                format: "%K > %@",
                CKSchema.PublishedList.Field.publishedAt,
                sevenDaysAgo as NSDate
            )
            query = CKQuery(recordType: CKSchema.PublishedList.recordType, predicate: predicate)
            query.sortDescriptors = [
                NSSortDescriptor(key: CKSchema.PublishedList.Field.upvoteCount, ascending: false),
                NSSortDescriptor(key: CKSchema.PublishedList.Field.publishedAt, ascending: false)
            ]
        } else {
            // Paginated continuations don't take a fresh query.
            query = CKQuery(recordType: CKSchema.PublishedList.recordType, predicate: NSPredicate(value: true))
        }

        do {
            let result: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
            if let cursor = feedCursor {
                result = try await publicDB.records(continuingMatchFrom: cursor, resultsLimit: 25)
            } else {
                result = try await publicDB.records(matching: query, resultsLimit: 25)
            }

            let newSummaries: [PublishedListSummary] = result.matchResults.compactMap { _, recordResult in
                guard case .success(let record) = recordResult else { return nil }
                return PublishedListSummary(record: record)
            }
            feed.append(contentsOf: newSummaries)
            feedCursor = result.queryCursor
            lastError = nil
        } catch {
            lastError = (error as NSError).localizedDescription
        }
    }

    // MARK: - Upvote

    /// Toggle an upvote for the given published list. Idempotent: tapping
    /// twice removes the vote. Updates the denormalized counter on
    /// PublishedList in the same operation; uses ifServerRecordUnchanged
    /// with one retry to handle counter races (decision 006, T-51a notes).
    func toggleUpvote(for summary: PublishedListSummary) async {
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

            let delta: Int64
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

            try await applyUpvoteDelta(to: listRecordID, delta: delta)
            lastError = nil
        } catch {
            lastError = (error as NSError).localizedDescription
        }
    }

    /// Read-modify-write the upvoteCount counter with one retry on conflict.
    private func applyUpvoteDelta(to listRecordID: CKRecord.ID, delta: Int64, retry: Bool = true) async throws {
        do {
            let record = try await publicDB.record(for: listRecordID)
            let current = (record[CKSchema.PublishedList.Field.upvoteCount] as? Int64) ?? 0
            record[CKSchema.PublishedList.Field.upvoteCount] = max(0, current + delta) as CKRecordValue

            let op = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            op.savePolicy = .ifServerRecordUnchanged
            op.qualityOfService = .userInitiated

            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                op.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success: cont.resume()
                    case .failure(let error): cont.resume(throwing: error)
                    }
                }
                publicDB.add(op)
            }

            // Optimistic local update of the in-memory feed copy.
            if let idx = feed.firstIndex(where: { $0.recordName == listRecordID.recordName }) {
                feed[idx].upvoteCount = max(0, feed[idx].upvoteCount + Int(delta))
            }
        } catch let error as CKError where error.code == .serverRecordChanged && retry {
            try await applyUpvoteDelta(to: listRecordID, delta: delta, retry: false)
        }
    }
}

// MARK: - Feed summary

/// Lightweight projection of a PublishedList for feed rendering. Avoids
/// passing CKRecord around the view layer.
struct PublishedListSummary: Identifiable, Equatable {
    let recordName: String
    let title: String
    let items: [String]
    let itemCount: Int
    let authorDisplayName: String?
    let publishedAt: Date
    var upvoteCount: Int

    var id: String { recordName }

    init?(record: CKRecord) {
        guard
            let title = record[CKSchema.PublishedList.Field.title] as? String,
            let publishedAt = record[CKSchema.PublishedList.Field.publishedAt] as? Date
        else { return nil }

        self.recordName = record.recordID.recordName
        self.title = title
        let itemsBlob = (record[CKSchema.PublishedList.Field.items] as? String) ?? ""
        self.items = itemsBlob.split(separator: "\n").map(String.init)
        self.itemCount = (record[CKSchema.PublishedList.Field.itemCount] as? Int) ?? items.count
        let name = record[CKSchema.PublishedList.Field.authorDisplayName] as? String
        self.authorDisplayName = (name?.isEmpty == false) ? name : nil
        self.publishedAt = publishedAt
        self.upvoteCount = Int((record[CKSchema.PublishedList.Field.upvoteCount] as? Int64) ?? 0)
    }
}
