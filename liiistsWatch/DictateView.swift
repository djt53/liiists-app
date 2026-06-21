import SwiftUI

/// Dictation flow — the marquee surface. List picker (skipped if preselected
/// from a log list) → system text input controller (dictation default on
/// watches that support it) → WC send → confirmation. Uses
/// `TextFieldLink` to present the watchOS-native input panel rather than
/// rolling our own `SFSpeechRecognizer` UI.
struct DictateView: View {
    var preselectedFilename: String? = nil

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var catalog: WatchCatalogStore
    @EnvironmentObject var phone: WatchPhoneClient

    @State private var selectedFilename: String?
    @State private var phase: Phase = .selectingList
    @State private var sendError: String?

    enum Phase: Equatable {
        case selectingList
        case input
        case sending
        case sent
        case failed
    }

    var body: some View {
        Group {
            switch phase {
            case .selectingList:
                if let preselected = preselectedFilename ?? defaultSelection() {
                    Color.clear.onAppear {
                        selectedFilename = preselected
                        phase = .input
                    }
                } else {
                    listPicker
                }
            case .input:
                inputScreen
            case .sending:
                ProgressView("Sending…")
                    .progressViewStyle(.circular)
            case .sent:
                sentScreen
            case .failed:
                failedScreen
            }
        }
    }

    // MARK: - List picker

    private var listPicker: some View {
        List {
            Section {
                if catalog.entries.isEmpty {
                    Text("No lists yet. Create one on your iPhone.")
                        .font(Theme.bodyFont(size: 12))
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(catalog.entries) { entry in
                        Button {
                            selectedFilename = entry.filename
                            Theme.lightHaptic()
                            phase = .input
                        } label: {
                            HStack(spacing: Theme.spaceSM) {
                                Image(systemName: typeIcon(for: entry.type))
                                    .foregroundStyle(.secondary)
                                Text(entry.title)
                                    .font(Theme.bodyFont(size: 14))
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("ADD TO")
                    .font(Theme.labelFont(size: 10))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.carousel)
        .navigationTitle("Dictate")
    }

    // MARK: - Input screen

    private var inputScreen: some View {
        VStack(spacing: Theme.spaceMD) {
            if let entry = currentEntry {
                Text(entry.title.uppercased())
                    .font(Theme.labelFont(size: 10))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "mic.fill")
                .font(.system(size: 32))
                .foregroundStyle(Theme.ndAccent)
            TextFieldLink(prompt: Text("Dictate")) {
                Text("TAP TO DICTATE")
                    .font(Theme.labelFont(size: 12))
                    .tracking(1.2)
            } onSubmit: { text in
                send(text: text)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.ndAccent)
        }
        .padding(.horizontal)
    }

    // MARK: - Send

    private func send(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let filename = selectedFilename, !trimmed.isEmpty else { return }
        guard let entry = catalog.entry(filename: filename) else {
            sendError = "list_not_found"
            phase = .failed
            return
        }

        phase = .sending
        let payload: WatchPayload = (entry.type == "log")
            ? .appendLogEntry(filename: filename, text: trimmed)
            : .addItem(filename: filename, text: trimmed)

        phone.send(payload) { error in
            if let error {
                sendError = error
                phase = .failed
                Theme.warningHaptic()
            } else {
                phase = .sent
                Theme.mediumHaptic()
                Task {
                    try? await Task.sleep(nanoseconds: 900_000_000)
                    if phase == .sent { dismiss() }
                }
            }
        }
    }

    // MARK: - Sent / failed screens

    private var sentScreen: some View {
        VStack(spacing: Theme.spaceSM) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Theme.ndSuccess)
            Text("SENT")
                .font(Theme.labelFont(size: 12))
                .tracking(1.2)
                .foregroundStyle(.secondary)
        }
    }

    private var failedScreen: some View {
        VStack(spacing: Theme.spaceSM) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(Theme.ndWarning)
            Text("COULDN'T SEND")
                .font(Theme.labelFont(size: 11))
                .tracking(1.2)
                .foregroundStyle(.secondary)
            if let err = sendError {
                Text(err)
                    .font(Theme.bodyFont(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Try Again") { phase = .input }
                .buttonStyle(.bordered)
        }
        .padding()
    }

    // MARK: - Helpers

    private var currentEntry: WatchCatalogEntry? {
        guard let filename = selectedFilename else { return nil }
        return catalog.entry(filename: filename)
    }

    private func defaultSelection() -> String? {
        // Skip picker entirely when there's only one list — no ambiguity.
        return catalog.entries.count == 1 ? catalog.entries.first?.filename : nil
    }

    private func typeIcon(for type: String) -> String {
        switch type {
        case "checklist": return "checklist"
        case "log": return "clock"
        case "streak": return "flame"
        default: return "list.bullet"
        }
    }
}
