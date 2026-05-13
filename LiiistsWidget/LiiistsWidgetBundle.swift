import SwiftUI
import WidgetKit

@main
struct LiiistsWidgetBundle: WidgetBundle {
    var body: some Widget {
        SingleListWidget()
        AllListsWidget()
        QuickAddWidget()
        QuickAddRowWidget()
        // StreakWidget hidden in v1.0 — re-add when streaks ship. See log.md session 10.
    }
}
