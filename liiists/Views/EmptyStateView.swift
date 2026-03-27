import SwiftUI

struct EmptyStateView: View {
    var onCreateList: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No Lists Yet", systemImage: "list.bullet.rectangle.portrait")
                .foregroundStyle(.secondary)
        } description: {
            Text("Create your first list to get started.")
                .foregroundStyle(.tertiary)
        } actions: {
            Button(action: onCreateList) {
                Text("Create a List")
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}
