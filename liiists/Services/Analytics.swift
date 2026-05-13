import Foundation
import PostHog

/// PostHog event wiring. Every `capture` site here is reviewed against the
/// privacy policy at djt53.github.io/liiists-www/privacy/ — list titles,
/// item text, and other user-generated content must never appear in event
/// properties. Counts, types, durations, and event names are fine.
///
/// Function signatures still accept titles so callers don't need to change,
/// but those parameters are intentionally unused here.
enum Analytics {
    private static let apiKey = "phc_CYZfwiiqycRoarhRVdPjGDUmSkpAy8DKu3hFBeswh7xX"

    static func setup() {
        let config = PostHogConfig(apiKey: apiKey, host: "https://us.i.posthog.com")
        config.captureApplicationLifecycleEvents = true
        config.captureScreenViews = false
        PostHogSDK.shared.setup(config)
    }

    // MARK: - List Events

    static func listCreated(title: String, type: String) {
        PostHogSDK.shared.capture("list_created", properties: [
            "list_type": type,
        ])
    }

    static func listDeleted(title: String) {
        PostHogSDK.shared.capture("list_deleted")
    }

    static func listRenamed(from oldTitle: String, to newTitle: String) {
        PostHogSDK.shared.capture("list_renamed")
    }

    // MARK: - Item Events

    static func itemAdded(listTitle: String, itemCount: Int) {
        PostHogSDK.shared.capture("item_added", properties: [
            "item_count": itemCount,
        ])
    }

    static func itemDeleted(listTitle: String) {
        PostHogSDK.shared.capture("item_deleted")
    }

    static func itemChecked(listTitle: String, checked: Bool) {
        PostHogSDK.shared.capture("item_checked", properties: [
            "checked": checked,
        ])
    }

    static func itemEdited(listTitle: String) {
        PostHogSDK.shared.capture("item_edited")
    }

    static func itemReordered(listTitle: String) {
        PostHogSDK.shared.capture("item_reordered")
    }

    // MARK: - Navigation

    static func screenViewed(_ screen: String, properties: [String: Any] = [:]) {
        var props: [String: Any] = ["screen": screen]
        props.merge(properties) { _, new in new }
        PostHogSDK.shared.capture("screen_viewed", properties: props)
    }

    static func searchUsed(query: String, screen: String, resultCount: Int) {
        PostHogSDK.shared.capture("search_used", properties: [
            "query_length": query.count,
            "screen": screen,
            "result_count": resultCount,
        ])
    }

    // MARK: - Discover / Social

    static func discoverViewed(tab: String) {
        PostHogSDK.shared.capture("discover_viewed", properties: [
            "tab": tab,
        ])
    }

    static func discoverTabSwitched(to tab: String) {
        PostHogSDK.shared.capture("discover_tab_switched", properties: [
            "tab": tab,
        ])
    }

    static func publicListViewed(title: String, author: String?) {
        PostHogSDK.shared.capture("public_list_viewed", properties: [
            "has_author": author != nil,
        ])
    }

    static func upvoteToggled(listTitle: String, isUpvoted: Bool) {
        PostHogSDK.shared.capture("upvote_toggled", properties: [
            "is_upvoted": isUpvoted,
        ])
    }

    static func saveToggled(listTitle: String, isSaved: Bool) {
        PostHogSDK.shared.capture("save_toggled", properties: [
            "is_saved": isSaved,
        ])
    }

    static func listCopiedToLocal(title: String, itemCount: Int) {
        PostHogSDK.shared.capture("list_copied_to_local", properties: [
            "item_count": itemCount,
        ])
    }

    static func listPublished(title: String) {
        PostHogSDK.shared.capture("list_published")
    }

    static func listUnpublished(title: String) {
        PostHogSDK.shared.capture("list_unpublished")
    }

    // MARK: - Streaks

    static func streakLogged(listTitle: String) {
        PostHogSDK.shared.capture("streak_logged")
    }

    static func streakListCreated(title: String, cadence: String) {
        PostHogSDK.shared.capture("streak_list_created", properties: [
            "cadence": cadence,
        ])
    }

    // MARK: - Paywall

    static func paywallShown(reason: String) {
        PostHogSDK.shared.capture("paywall_shown", properties: [
            "reason": reason,
        ])
    }

    static func paywallDismissed(reason: String) {
        PostHogSDK.shared.capture("paywall_dismissed", properties: [
            "reason": reason,
        ])
    }

    static func purchaseCompleted(productID: String) {
        PostHogSDK.shared.capture("purchase_completed", properties: [
            "product_id": productID,
        ])
    }

    static func purchaseCancelled(productID: String) {
        PostHogSDK.shared.capture("purchase_cancelled", properties: [
            "product_id": productID,
        ])
    }

    static func purchaseFailed(productID: String, error: String) {
        PostHogSDK.shared.capture("purchase_failed", properties: [
            "product_id": productID,
            "error": error,
        ])
    }

    static func purchaseRestored() {
        PostHogSDK.shared.capture("purchase_restored")
    }

    // MARK: - Share Extension

    static func shareExtensionUsed(listTitle: String, contentType: String) {
        PostHogSDK.shared.capture("share_extension_used", properties: [
            "content_type": contentType,
        ])
    }

    // MARK: - Suggest More (decision 011)

    static func suggestMoreInvoked(listTitle: String, itemCount: Int) {
        PostHogSDK.shared.capture("suggest_more_invoked", properties: [
            "item_count": itemCount,
        ])
    }

    static func suggestMoreSucceeded(listTitle: String, itemCount: Int) {
        PostHogSDK.shared.capture("suggest_more_succeeded", properties: [
            "item_count": itemCount,
        ])
    }

    static func suggestMoreFailed(listTitle: String, errorType: String) {
        PostHogSDK.shared.capture("suggest_more_failed", properties: [
            "error_type": errorType,
        ])
    }

    static func suggestMorePaywallHit(listTitle: String) {
        PostHogSDK.shared.capture("suggest_more_paywall_hit")
    }

    static func suggestMoreAdded(listTitle: String, selectedCount: Int, totalCount: Int) {
        PostHogSDK.shared.capture("suggest_more_added", properties: [
            "selected_count": selectedCount,
            "total_count": totalCount,
        ])
    }
}
