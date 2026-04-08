import SwiftUI
import AuthenticationServices

/// Single-sheet onboarding for the social Discover surface.
/// State machine: explainer → signing-in → handlePicker → done.
/// See decision 008.
struct PublishOnboardingSheet: View {
    @EnvironmentObject private var account: AccountStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    /// Called when the sheet finishes — either completion or explicit dismiss.
    /// Either path flips `socialEngaged` so the bottom CTA never returns.
    let onFinish: () -> Void

    enum Phase: Equatable {
        case explainer
        case signingIn
        case handlePicker
    }

    @State private var phase: Phase = .explainer
    @State private var useHandle: Bool = false
    @State private var handleText: String = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch phase {
            case .explainer:
                explainer
            case .signingIn:
                signingIn
            case .handlePicker:
                handlePicker
            }
        }
        .padding(.horizontal, Theme.spaceLG)
        .padding(.top, Theme.spaceXL)
        .padding(.bottom, Theme.spaceLG)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.ndBlack.resolve(for: colorScheme))
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(phase == .signingIn)
    }

    // MARK: - Explainer

    private var explainer: some View {
        VStack(alignment: .leading, spacing: Theme.spaceLG) {
            Text("Publish a list")
                .font(Theme.headingFont(size: Theme.headingSize, weight: .medium))
                .foregroundStyle(Theme.ndTextDisplay.resolve(for: colorScheme))

            VStack(alignment: .leading, spacing: Theme.spaceMD) {
                explainerRow("Your published lists appear in Discover for everyone to see and upvote.")
                explainerRow("Anonymous by default — no name shown unless you choose one.")
                explainerRow("You can unpublish any list at any time.")
            }

            Spacer(minLength: 0)

            VStack(spacing: Theme.spaceSM) {
                Button {
                    Task { await beginSignIn() }
                } label: {
                    HStack(spacing: Theme.spaceSM) {
                        Image(systemName: "applelogo")
                        Text("Continue with Apple")
                            .font(Theme.bodyFont(weight: .medium))
                    }
                    .frame(maxWidth: .infinity, minHeight: Theme.buttonMinHeight)
                    .foregroundStyle(Theme.ndBlack.resolve(for: colorScheme))
                    .background(Theme.ndTextDisplay.resolve(for: colorScheme))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                }

                Button {
                    finish()
                } label: {
                    Text("Not now")
                        .font(Theme.bodyFont())
                        .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                        .frame(maxWidth: .infinity, minHeight: Theme.buttonMinHeight)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(Theme.bodyFont(size: Theme.bodySM))
                    .foregroundStyle(Theme.ndAccent)
            }
        }
    }

    private func explainerRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.spaceSM) {
            Circle()
                .fill(Theme.ndTextSecondary.resolve(for: colorScheme))
                .frame(width: 4, height: 4)
                .padding(.top, 8)
            Text(text)
                .font(Theme.bodyFont())
                .foregroundStyle(Theme.ndTextPrimary.resolve(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Signing in

    private var signingIn: some View {
        VStack(spacing: Theme.spaceLG) {
            Spacer()
            ProgressView()
                .progressViewStyle(.circular)
                .tint(Theme.ndTextDisplay.resolve(for: colorScheme))
            Text("Signing in…")
                .font(Theme.bodyFont())
                .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Handle picker

    private var handlePicker: some View {
        VStack(alignment: .leading, spacing: Theme.spaceLG) {
            Text("How should you appear?")
                .font(Theme.headingFont(size: Theme.headingSize, weight: .medium))
                .foregroundStyle(Theme.ndTextDisplay.resolve(for: colorScheme))

            VStack(alignment: .leading, spacing: Theme.spaceMD) {
                identityOption(
                    title: "Anonymous",
                    subtitle: "Your lists publish without a name.",
                    selected: !useHandle
                ) {
                    useHandle = false
                }

                identityOption(
                    title: "Pick a handle",
                    subtitle: useHandle ? nil : "Show a name on every list you publish.",
                    selected: useHandle
                ) {
                    useHandle = true
                }

                if useHandle {
                    handleField
                }
            }

            Spacer(minLength: 0)

            Button {
                completeHandlePicker()
            } label: {
                Text("Done")
                    .font(Theme.bodyFont(weight: .medium))
                    .frame(maxWidth: .infinity, minHeight: Theme.buttonMinHeight)
                    .foregroundStyle(Theme.ndBlack.resolve(for: colorScheme))
                    .background(doneEnabled
                                ? Theme.ndTextDisplay.resolve(for: colorScheme)
                                : Theme.ndTextDisplay.resolve(for: colorScheme).opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
            }
            .disabled(!doneEnabled)
        }
    }

    private func identityOption(title: String, subtitle: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Theme.spaceMD) {
                ZStack {
                    Circle()
                        .strokeBorder(Theme.ndBorderVisible.resolve(for: colorScheme), lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                    if selected {
                        Circle()
                            .fill(Theme.ndTextDisplay.resolve(for: colorScheme))
                            .frame(width: 10, height: 10)
                    }
                }
                .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.bodyFont(weight: .medium))
                        .foregroundStyle(Theme.ndTextPrimary.resolve(for: colorScheme))
                    if let subtitle {
                        Text(subtitle)
                            .font(Theme.bodyFont(size: Theme.bodySM))
                            .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                        // Coerce as the user types — keep it tidy.
                        let lowered = new.lowercased()
                        let allowed = lowered.filter { $0.isLetter || $0.isNumber || $0 == "_" }
                        if allowed != handleText { handleText = String(allowed.prefix(HandleValidator.maxLength)) }
                    }
            }
            .padding(.horizontal, Theme.spaceMD)
            .padding(.vertical, Theme.spaceSM)
            .background(Theme.ndSurfaceRaised.resolve(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))

            if let message = validation.message {
                Text(message)
                    .font(Theme.bodyFont(size: Theme.captionSize))
                    .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
            }
        }
    }

    private var doneEnabled: Bool {
        if !useHandle { return true }
        return HandleValidator.validate(handleText) == .valid
    }

    // MARK: - Actions

    private func beginSignIn() async {
        errorMessage = nil
        guard let anchor = ASPresentationAnchor.current else {
            errorMessage = "Couldn't present sign-in. Try again."
            return
        }
        phase = .signingIn
        await account.signIn(presentationAnchor: anchor)
        switch account.state {
        case .signedIn:
            phase = .handlePicker
        case .error(let msg):
            errorMessage = msg
            phase = .explainer
        default:
            phase = .explainer
        }
    }

    private func completeHandlePicker() {
        if useHandle, HandleValidator.validate(handleText) == .valid {
            account.displayName = handleText
        } else {
            account.displayName = nil
        }
        finish()
    }

    private func finish() {
        onFinish()
        dismiss()
    }
}

// MARK: - Presentation anchor lookup

extension ASPresentationAnchor {
    /// Best-effort lookup of the active key window for ASAuthorizationController
    /// presentation. Avoids passing UIWindow plumbing through SwiftUI views.
    static var current: ASPresentationAnchor? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })
    }
}
