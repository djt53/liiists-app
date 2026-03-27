import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: ListStore
    @State private var showNewList = false
    @State private var newListTitle = ""
    @State private var newListType: ItemList.ListType = .list

    var body: some View {
        NavigationStack {
            Group {
                if !store.isLoaded {
                    ProgressView()
                } else if store.lists.isEmpty {
                    EmptyStateView(onCreateList: { showNewList = true })
                } else {
                    listsView
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
            .sheet(isPresented: $showNewList) {
                NewListSheet(
                    title: $newListTitle,
                    listType: $newListType,
                    onCreate: {
                        let trimmed = newListTitle.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        _ = store.create(title: trimmed, type: newListType)
                        Theme.mediumHaptic()
                        newListTitle = ""
                        newListType = .list
                        showNewList = false
                    }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private var listsView: some View {
        List {
            ForEach(store.lists) { list in
                NavigationLink(value: list.id) {
                    ListRow(list: list)
                }
            }
            .onDelete { offsets in
                for index in offsets {
                    store.delete(store.lists[index])
                }
            }
        }
        .listStyle(.insetGrouped)
        .contentMargins(.top, 12, for: .scrollContent)
        .navigationDestination(for: UUID.self) { listId in
            if let list = store.lists.first(where: { $0.id == listId }) {
                ListView(list: list)
            }
        }
    }
}

// MARK: - List Row

struct ListRow: View {
    let list: ItemList

    var body: some View {
        HStack(spacing: 12) {
            // Type icon
            Image(systemName: list.type == .checklist ? "checklist" : "list.bullet")
                .font(.body)
                .foregroundStyle(Theme.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(list.title)
                    .font(.body)

                if list.type == .checklist && list.itemCount > 0 {
                    Text("\(list.checkedCount) of \(list.itemCount)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if list.itemCount > 0 {
                    Text("\(list.itemCount) items")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(minHeight: Theme.rowMinHeight)
    }
}

// MARK: - New List Sheet

struct NewListSheet: View {
    @Binding var title: String
    @Binding var listType: ItemList.ListType
    var onCreate: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("List name", text: $title)
                        .font(.title2)
                        .focused($isFocused)
                        .submitLabel(.done)
                        .onSubmit(onCreate)
                }

                Section {
                    Picker("Type", selection: $listType) {
                        Label("List", systemImage: "list.bullet")
                            .tag(ItemList.ListType.list)
                        Label("Checklist", systemImage: "checklist")
                            .tag(ItemList.ListType.checklist)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            .navigationTitle("New List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        title = ""
                        listType = .list
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: onCreate)
                        .fontWeight(.semibold)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { isFocused = true }
        }
    }
}
