import Foundation
import PostHog

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
            "list_title": title,
            "list_type": type,
        ])
    }

    static func listDeleted(title: String) {
        PostHogSDK.shared.capture("list_deleted", properties: [
            "list_title": title,
        ])
    }

    static func listRenamed(from oldTitle: String, to newTitle: String) {
        PostHogSDK.shared.capture("list_renamed", properties: [
            "old_title": oldTitle,
            "new_title": newTitle,
        ])
    }

    // MARK: - Item Events

    static func itemAdded(listTitle: String, itemCount: Int) {
        PostHogSDK.shared.capture("item_added", properties: [
            "list_title": listTitle,
            "item_count": itemCount,
        ])
    }

    static func itemDeleted(listTitle: String) {
        PostHogSDK.shared.capture("item_deleted", properties: [
            "list_title": listTitle,
        ])
    }

    static func itemChecked(listTitle: String, checked: Bool) {
        PostHogSDK.shared.capture("item_checked", properties: [
            "list_title": listTitle,
            "checked": checked,
        ])
    }

    static func itemEdited(listTitle: String) {
        PostHogSDK.shared.capture("item_edited", properties: [
            "list_title": listTitle,
        ])
    }

    static func itemReordered(listTitle: String) {
        PostHogSDK.shared.capture("item_reordered", properties: [
            "list_title": listTitle,
        ])
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
            "list_title": title,
            "author": author ?? "anonymous",
        ])
    }

    static func upvoteToggled(listTitle: String, isUpvoted: Bool) {
        PostHogSDK.shared.capture("upvote_toggled", properties: [
            "list_title": listTitle,
            "is_upvoted": isUpvoted,
        ])
    }

    static func saveToggled(listTitle: String, isSaved: Bool) {
        PostHogSDK.shared.capture("save_toggled", properties: [
            "list_title": listTitle,
            "is_saved": isSaved,
        ])
    }

    static func listCopiedToLocal(title: String, itemCount: Int) {
        PostHogSDK.shared.capture("list_copied_to_local", properties: [
            "list_title": title,
            "item_count": itemCount,
        ])
    }

    static func listPublished(title: String) {
        PostHogSDK.shared.capture("list_published", properties: [
            "list_title": title,
        ])
    }

    static func listUnpublished(title: String) {
        PostHogSDK.shared.capture("list_unpublished", properties: [
            "list_title": title,
        ])
    }

    // MARK: - Streaks

    static func streakLogged(listTitle: String) {
        PostHogSDK.shared.capture("streak_logged", properties: [
            "list_title": listTitle,
        ])
    }

    static func streakListCreated(title: String, cadence: String) {
        PostHogSDK.shared.capture("streak_list_created", properties: [
            "list_title": title,
            "cadence": cadence,
        ])
    }

    // MARK: - Share Extension

    static func shareExtensionUsed(listTitle: String, contentType: String) {
        PostHogSDK.shared.capture("share_extension_used", properties: [
            "list_title": listTitle,
            "content_type": contentType,
        ])
    }

    // MARK: - Suggest More (decision 011)

    static func suggestMoreInvoked(listTitle: String, itemCount: Int) {
        PostHogSDK.shared.capture("suggest_more_invoked", properties: [
            "list_title": listTitle,
            "item_count": itemCount,
        ])
    }

    static func suggestMoreSucceeded(listTitle: String, itemCount: Int) {
        PostHogSDK.shared.capture("suggest_more_succeeded", properties: [
            "list_title": listTitle,
            "item_count": itemCount,
        ])
    }

    static func suggestMoreFailed(listTitle: String, errorType: String) {
        PostHogSDK.shared.capture("suggest_more_failed", properties: [
            "list_title": listTitle,
            "error_type": errorType,
        ])
    }

    static func suggestMorePaywallHit(listTitle: String) {
        PostHogSDK.shared.capture("suggest_more_paywall_hit", properties: [
            "list_title": listTitle,
        ])
    }

    static func suggestMoreAdded(listTitle: String, selectedCount: Int, totalCount: Int) {
        PostHogSDK.shared.capture("suggest_more_added", properties: [
            "list_title": listTitle,
            "selected_count": selectedCount,
            "total_count": totalCount,
        ])
    }
}
