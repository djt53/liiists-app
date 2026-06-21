import Foundation
import WatchConnectivity

/// WatchConnectivity client on the watch side. Sends payloads to the iPhone
/// for the actual markdown write. Falls back to `transferUserInfo` when the
/// iPhone is unreachable — WC delivers next time both devices are awake.
@MainActor
final class WatchPhoneClient: NSObject, ObservableObject {
    static let shared = WatchPhoneClient()

    @Published private(set) var lastError: String?
    @Published private(set) var pendingCount: Int = 0

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Sends a payload to the iPhone. Completion is called with `nil` on
    /// success, or a short error string on failure. When the iPhone is
    /// unreachable the payload is queued via `transferUserInfo`; the
    /// completion still fires with `nil` because the delivery is guaranteed
    /// (eventually) — caller treats it as success for UX purposes.
    func send(_ payload: WatchPayload, completion: ((String?) -> Void)? = nil) {
        let message = payload.dictionary
        let session = WCSession.default

        guard session.activationState == .activated else {
            self.lastError = "session_inactive"
            completion?("session_inactive")
            return
        }

        if session.isReachable {
            session.sendMessage(message, replyHandler: { [weak self] reply in
                Task { @MainActor in
                    guard let self else { return }
                    if let ok = reply["ok"] as? Bool, ok {
                        self.lastError = nil
                        completion?(nil)
                    } else {
                        let err = (reply["error"] as? String) ?? "unknown"
                        self.lastError = err
                        completion?(err)
                    }
                }
            }, errorHandler: { [weak self] error in
                Task { @MainActor in
                    guard let self else { return }
                    self.queue(message: message)
                    self.lastError = error.localizedDescription
                    completion?(nil)
                }
            })
        } else {
            queue(message: message)
            completion?(nil)
        }
    }

    private func queue(message: [String: Any]) {
        WCSession.default.transferUserInfo(message)
        pendingCount += 1
    }
}

extension WatchPhoneClient: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    nonisolated func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        Task { @MainActor in
            if self.pendingCount > 0 { self.pendingCount -= 1 }
        }
    }
}
