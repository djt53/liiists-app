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

    // MARK: - Share Extension

    static func shareExtensionUsed(listTitle: String, contentType: String) {
        PostHogSDK.shared.capture("share_extension_used", properties: [
            "list_title": listTitle,
            "content_type": contentType,
        ])
    }
}
