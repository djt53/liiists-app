import SwiftUI
import UIKit

/// Re-enables iOS's edge-swipe-to-go-back gesture on screens that hide the
/// system back button via `.navigationBarBackButtonHidden(true)`. SwiftUI
/// disables the gesture along with the button; this helper finds the host
/// UINavigationController and clears the gesture's delegate so the swipe
/// works again. Apply via `.enableSwipeBack()` on the destination view.
private struct SwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        DispatchQueue.main.async {
            vc.navigationController?.interactivePopGestureRecognizer?.delegate = nil
            vc.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

extension View {
    /// Restores the iOS edge-swipe-to-go-back gesture on screens that
    /// hide the system back button.
    func enableSwipeBack() -> some View {
        self.background(SwipeBackEnabler().frame(width: 0, height: 0))
    }
}
