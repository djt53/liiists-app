import SwiftUI

struct EmptyStateView: View {
    var onCreateList: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No Lists Yet", systemImage: "list.bullet.rectangle.portrait")
        } description: {
            Text("Create your first list to get started.")
        } actions: {
            Button("Create a List") {
                onCreateList()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
