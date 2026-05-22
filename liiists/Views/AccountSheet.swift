import SwiftUI

/// Minimal account management surface — opens from the HomeView toolbar
/// when the user is signed in. T-51d (decision 008's "reset path").
struct AccountSheet: View {
    @EnvironmentObject private var account: AccountStore
    @EnvironmentObject private var publish: PublishStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @AppStorage("social_engaged") private var socialEngaged: Bool = false

    @State private var editingHandle = false
    @State private var handleText: String = ""
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spaceLG) {
            Text("Account")
                .font(Theme.headingFont(size: Theme.headingSize, weight: .medium))
                .foregroundStyle(Theme.ndTextDisplay.resolve(for: colorScheme))

            // Identity row
            VStack(alignment: .leading, spacing: Theme.spaceXS) {
                Text("APPEARS AS")
                    .nothingLabel()
                if editingHandle {
                    handleField
                } else {
                    HStack {
                        Text(displayLine)
                            .font(Theme.bodyFont(weight: .medium))
                            .foregroundStyle(Theme.ndTextPrimary.resolve(for: colorScheme))
                        Spacer()
                        Button("Edit") {
                            handleText = account.displayName ?? ""
                            editingHandle = true
                        }
                        .font(Theme.bodyFont(size: Theme.bodySM, weight: .medium))
                        .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                    }
                }
            }

            Divider()
                .background(Theme.ndBorder.resolve(for: colorScheme))

            // Reset onboarding toggle
            Toggle(isOn: Binding(
                get: { !socialEngaged },
                set: { socialEngaged = !$0 }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show publish prompt")
                        .font(Theme.bodyFont(weight: .medium))
                        .foregroundStyle(Theme.ndTextPrimary.resolve(for: colorScheme))
                    Text("Restores the bottom CTA on the home screen.")
                        .font(Theme.bodyFont(size: Theme.bodySM))
                        .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                }
            }
            .tint(Theme.ndAccent)

            if !publish.blockedAuthors.isEmpty {
                Divider()
                    .background(Theme.ndBorder.resolve(for: colorScheme))

                VStack(alignment: .leading, spacing: Theme.spaceSM) {
                    Text("BLOCKED")
                        .nothingLabel()
                    ForEach(publish.blockedAuthors) { blocked in
                        HStack {
                            Text(blocked.displayLabel)
                                .font(Theme.bodyFont())
                                .foregroundStyle(Theme.ndTextPrimary.resolve(for: colorScheme))
                            Spacer()
                            Button("Unblock") {
                                publish.unblockAuthor(userID: blocked.userID)
                            }
                            .font(Theme.bodyFont(size: Theme.bodySM, weight: .medium))
                            .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                        }
                    }
                }
            }

            if !publish.hiddenRecordNames.isEmpty {
                Divider()
                    .background(Theme.ndBorder.resolve(for: colorScheme))

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("HIDDEN POSTS")
                            .nothingLabel()
                        Text("\(publish.hiddenRecordNames.count) hidden from your feed")
                            .font(Theme.bodyFont(size: Theme.bodySM))
                            .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                    }
                    Spacer()
                    Button("Clear") {
                        publish.clearHidden()
                    }
                    .font(Theme.bodyFont(size: Theme.bodySM, weight: .medium))
                    .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                }
            }

            Spacer(minLength: 0)

            // Sign out
            Button(role: .destructive) {
                account.signOut()
                dismiss()
            } label: {
                Text("Sign out")
                    .font(Theme.bodyFont(weight: .medium))
                    .frame(maxWidth: .infinity, minHeight: Theme.buttonMinHeight)
                    .foregroundStyle(Theme.ndAccent)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cornerRadius)
                            .strokeBorder(Theme.ndAccent.opacity(0.4), lineWidth: 1)
                    )
            }
            .disabled(isDeleting)

            // Delete account — guideline 5.1.1(v). Wipes published lists,
            // upvotes, display name, and the local Apple credential link.
            Button(role: .destructive) {
                Analytics.accountDeleteInitiated()
                showDeleteConfirm = true
            } label: {
                Text("Delete account")
                    .font(Theme.bodyFont(weight: .medium))
                    .frame(maxWidth: .infinity, minHeight: Theme.buttonMinHeight)
                    .foregroundStyle(.red)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cornerRadius)
                            .strokeBorder(Color.red.opacity(0.4), lineWidth: 1)
                    )
            }
            .disabled(isDeleting)
            .alert("Delete your account?", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    Analytics.accountDeleteConfirmed()
                    Task { await performDelete() }
                }
            } message: {
                Text("Permanently removes your published lists, your upvotes, and your display name. Your local lists are not affected. To fully sign out of Apple, visit Settings → Apple ID → Sign in with Apple → liiists. This cannot be undone.")
            }

            if isDeleting {
                HStack(spacing: Theme.spaceSM) {
                    ProgressView()
                    Text("Deleting…")
                        .font(Theme.bodyFont(size: Theme.bodySM))
                        .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                }
            }

            if let deleteError {
                Text(deleteError)
                    .font(Theme.bodyFont(size: Theme.captionSize))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Sign in with Apple manages itself in iOS Settings → Apple ID. Signing out here just clears the local credential.")
                .font(Theme.bodyFont(size: Theme.captionSize))
                .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.spaceLG)
        .padding(.top, Theme.spaceXL)
        .padding(.bottom, Theme.spaceLG)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.ndBlack.resolve(for: colorScheme))
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    @MainActor
    private func performDelete() async {
        isDeleting = true
        deleteError = nil
        do {
            try await publish.deleteAccount()
            account.deleteAccount()
            Analytics.accountDeleteSucceeded()
            isDeleting = false
            dismiss()
        } catch {
            let nsError = error as NSError
            isDeleting = false
            deleteError = "Couldn't delete your account. \(nsError.localizedDescription)"
            Analytics.accountDeleteFailed(errorType: "\(nsError.domain)_\(nsError.code)")
        }
    }

    private var displayLine: String {
        if let handle = account.displayName, !handle.isEmpty {
            return "@\(handle)"
        }
        return "Anonymous"
    }

    private var handleField: some View {
        let validation = HandleValidator.validate(handleText)
        return VStack(alignment: .leading, spacing: Theme.spaceXS) {
            HStack(spacing: 0) {
                Text("@")
                    .font(Theme.monoFont())
                    .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                TextField("yourhandle", text: $handleText)
                    .font(Theme.monoFont())
                    .foregroundStyle(Theme.ndTextPrimary.resolve(for: colorScheme))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .onChange(of: handleText) { _, new in
                        let lowered = new.lowercased()
                        let allowed = lowered.filter { $0.isLetter || $0.isNumber || $0 == "_" }
                        if allowed != handleText { handleText = String(allowed.prefix(HandleValidator.maxLength)) }
                    }
            }
            .padding(.horizontal, Theme.spaceMD)
            .padding(.vertical, Theme.spaceSM)
            .background(Theme.ndSurfaceRaised.resolve(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))

            HStack {
                if let message = validation.message {
                    Text(message)
                        .font(Theme.bodyFont(size: Theme.captionSize))
                        .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                }
                Spacer()
                Button("Anonymous") {
                    account.displayName = nil
                    editingHandle = false
                }
                .font(Theme.bodyFont(size: Theme.bodySM))
                .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                Button("Save") {
                    if HandleValidator.validate(handleText) == .valid {
                        account.displayName = handleText
                        editingHandle = false
                    } else if handleText.isEmpty {
                        account.displayName = nil
                        editingHandle = false
                    }
                }
                .font(Theme.bodyFont(size: Theme.bodySM, weight: .medium))
                .foregroundStyle(Theme.ndTextDisplay.resolve(for: colorScheme))
                .disabled(!handleText.isEmpty && validation != .valid)
            }
        }
    }
}
