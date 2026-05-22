import Foundation
import AuthenticationServices
import CloudKit
import Security
import SwiftUI

/// Manages Sign in with Apple credentials and the corresponding CloudKit user record.
///
/// Identity is anonymous-first: the Apple credential gives us a stable user ID and a
/// (one-time) full name, but the user can opt out of exposing any name on published
/// content via `displayName`. The Apple full name is never persisted.
///
/// See: decisions 005 (CloudKit identity), 006 (social architecture).
@MainActor
final class AccountStore: NSObject, ObservableObject {
    enum State: Equatable {
        case signedOut
        case signingIn
        case signedIn(userID: String)
        case error(String)
    }

    @Published private(set) var state: State = .signedOut
    @Published private(set) var ckUserRecordID: CKRecord.ID?

    /// Optional display name shown on published lists. `nil` means anonymous.
    @Published var displayName: String? {
        didSet { Keychain.set(displayName, for: Keys.displayName) }
    }

    private enum Keys {
        static let appleUserID = "liiists.appleUserID"
        static let displayName = "liiists.displayName"
    }

    private var revokeObserver: NSObjectProtocol?

    override init() {
        self.displayName = Keychain.get(Keys.displayName)
        super.init()
        observeRevokeNotifications()
    }

    deinit {
        if let revokeObserver {
            NotificationCenter.default.removeObserver(revokeObserver)
        }
    }

    var isSignedIn: Bool {
        if case .signedIn = state { return true }
        return false
    }

    /// Call on app launch. Verifies any persisted Apple credential is still valid
    /// and bootstraps the CloudKit user record ID.
    func refreshCredentialState() async {
        guard let userID = Keychain.get(Keys.appleUserID) else {
            state = .signedOut
            return
        }
        let provider = ASAuthorizationAppleIDProvider()
        do {
            let credentialState = try await provider.credentialState(forUserID: userID)
            switch credentialState {
            case .authorized:
                state = .signedIn(userID: userID)
                await fetchCKUserRecordID()
            case .revoked, .notFound, .transferred:
                clearCredential()
            @unknown default:
                clearCredential()
            }
        } catch {
            // Network or transient — leave state as-is rather than signing user out.
        }
    }

    /// Begins the Sign in with Apple flow. Caller passes a presentation anchor.
    func signIn(presentationAnchor: ASPresentationAnchor) async {
        state = .signingIn
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        let delegate = SignInDelegate(presentationAnchor: presentationAnchor)
        controller.delegate = delegate
        controller.presentationContextProvider = delegate

        do {
            let credential = try await delegate.perform(on: controller)
            Keychain.set(credential.user, for: Keys.appleUserID)
            state = .signedIn(userID: credential.user)
            await fetchCKUserRecordID()
        } catch {
            state = .error((error as NSError).localizedDescription)
        }
    }

    /// Local sign-out. Apple does not support programmatic credential revocation —
    /// the user must revoke from Settings → Apple ID → Sign in with Apple.
    func signOut() {
        clearCredential()
    }

    /// Local-side teardown for the account-deletion flow (guideline 5.1.1(v)).
    /// Pairs with `PublishStore.deleteAccount()` which clears the CK side.
    /// Does NOT revoke the Sign in with Apple credential itself — that's
    /// user-driven via iOS Settings, and App Review accepts the in-app text
    /// pointing users there.
    func deleteAccount() {
        Keychain.delete(Keys.appleUserID)
        Keychain.delete(Keys.displayName)
        displayName = nil
        ckUserRecordID = nil

        // Reset onboarding so a fresh sign-in returns to the publish prompt.
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "social_engaged")
        defaults.removeObject(forKey: "eula_accepted_version")

        state = .signedOut
    }

    private func clearCredential() {
        Keychain.delete(Keys.appleUserID)
        ckUserRecordID = nil
        state = .signedOut
    }

    private func fetchCKUserRecordID() async {
        do {
            let id = try await CKContainer.default().userRecordID()
            ckUserRecordID = id
        } catch {
            // Not fatal for sign-in itself; CK calls will surface errors when used.
        }
    }

    private func observeRevokeNotifications() {
        revokeObserver = NotificationCenter.default.addObserver(
            forName: ASAuthorizationAppleIDProvider.credentialRevokedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.clearCredential() }
        }
    }
}

// MARK: - Sign-in delegate

private final class SignInDelegate: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private let anchor: ASPresentationAnchor
    private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?

    init(presentationAnchor: ASPresentationAnchor) {
        self.anchor = presentationAnchor
    }

    func perform(on controller: ASAuthorizationController) async throws -> ASAuthorizationAppleIDCredential {
        try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            controller.performRequests()
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        anchor
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            continuation?.resume(throwing: NSError(domain: "AccountStore", code: -1))
            return
        }
        continuation?.resume(returning: credential)
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

// MARK: - Keychain helpers

private enum Keychain {
    static func set(_ value: String?, for key: String) {
        guard let value, let data = value.data(using: .utf8) else {
            delete(key)
            return
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)

        var attrs = query
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attrs as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
