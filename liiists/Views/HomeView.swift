import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: ListStore
    @State private var showNewList = false
    @State private var newListTitle = ""

    var body: some View {
        NavigationStack {
            Group {
                if !store.isLoaded {
                    ProgressView()
                } else if store.lists.isEmpty {
                    EmptyStateView(onCreateList: { showNewList = true })
                } else {
                    listGrid
                }
            }
            .navigationTitle("liiists")
            .toolbar {
                if !store.lists.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showNewList = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .alert("New List", isPresented: $showNewList) {
                TextField("List name", text: $newListTitle)
                Button("Create") {
                    guard !newListTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    _ = store.create(title: newListTitle.trimmingCharacters(in: .whitespaces))
                    newListTitle = ""
                }
                Button("Cancel", role: .cancel) {
                    newListTitle = ""
                }
            }
        }
    }

    private var listGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 16
            ) {
                ForEach(store.lists) { list in
                    NavigationLink(value: list.id) {
                        ListCard(list: list)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .navigationDestination(for: UUID.self) { listId in
            if let list = store.lists.first(where: { $0.id == listId }) {
                ListView(list: list)
            }
        }
    }
}

// MARK: - List Card

struct ListCard: View {
    let list: ItemList

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(list.title)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Spacer()

            HStack {
                if list.type == .checklist {
                    Text("\(list.checkedCount)/\(list.itemCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(list.itemCount) items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: list.type == .checklist ? "checklist" : "list.bullet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
    }
}
