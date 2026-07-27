//
//  PinPromptPresenter.swift
//  DashWallet
//
//  Presents `PinPromptView` over the top-most view controller from any
//  context — the auth gate is invoked from ObjC completion facades and
//  async Swift alike, none of which own a presentation anchor.
//
//  If no anchor can be resolved (app backgrounded, no key window), the
//  prompt resolves `.failed` immediately rather than hanging silently —
//  the failure mode that motivated the pod-era 120 s watchdog.
//

import SwiftUI

@MainActor
enum PinPromptPresenter {

    /// Present the PIN modal and resume once with the user's outcome.
    static func present(service: AuthenticationServiceProtocol = AuthenticationService.shared) async -> PinPromptResult {
        guard let anchor = topPresentedController() else {
            NSLog("🔐 PINPROMPT :: no presentation anchor — resolving .failed")
            return .failed
        }

        return await withCheckedContinuation { continuation in
            var didResume = false
            func resume(_ result: PinPromptResult, dismiss host: UIViewController?) {
                guard !didResume else { return }
                didResume = true
                if let host {
                    host.dismiss(animated: true) { continuation.resume(returning: result) }
                } else {
                    continuation.resume(returning: result)
                }
            }

            let viewModel = PinPromptViewModel(service: service) { [weak anchor] result in
                // Capture the hosting controller lazily: the closure fires
                // after presentation, so `anchor.presentedViewController` is
                // the modal we put up.
                resume(result, dismiss: anchor?.presentedViewController)
            }
            let host = UIHostingController(rootView: PinPromptView(viewModel: viewModel))
            host.modalPresentationStyle = .overFullScreen
            host.modalTransitionStyle = .crossDissolve
            // Transparent so the SwiftUI dimmed backdrop is the only overlay
            // and the send screen stays visible behind the card.
            host.view.backgroundColor = .clear
            anchor.present(host, animated: true)

            // UIKit can reject a presentation without calling a completion
            // handler (for example when a SwiftUI sheet is being replaced).
            // Do not leak the continuation and leave AuthenticationGate
            // waiting for its watchdog in that case.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard !didResume else { return }
                guard host.presentingViewController != nil,
                      host.viewIfLoaded?.window != nil else {
                    NSLog("🔐 PINPROMPT :: presentation rejected — resolving .failed")
                    resume(.failed, dismiss: nil)
                    return
                }
            }
        }
    }

    /// The controller a modal should be presented from: the top of the key
    /// window's presentation stack.
    private static func topPresentedController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }

        // This app still owns its UIWindow in AppDelegate and does not use a
        // SceneDelegate. On those launches `connectedScenes` can be empty
        // even while the legacy DWWindow is visible. Conversely, after the
        // lock-window handoff, neither the app-delegate window nor the
        // formerly-key lock window is guaranteed to be returned by the
        // foreground-scene-only path. Include all three sources and validate
        // attachment below.
        //
        // Keep the app window first. While a SwiftUI text field resigns first
        // responder, a transient keyboard window can briefly become key;
        // presenting from it produces a detached hosting controller.
        var windows: [UIWindow] = []
        if let appWindow = UIApplication.shared.delegate?.window ?? nil {
            windows.append(appWindow)
        }
        windows.append(contentsOf: scenes.flatMap(\.windows))
        // Legacy-window fallback is required for the AppDelegate-managed
        // lifecycle above. `UIApplication.windows` is deprecated for
        // scene-based apps, but here it is deliberately the compatibility
        // source when there is no active UIWindowScene.
        windows.append(contentsOf: UIApplication.shared.windows)

        var seen = Set<ObjectIdentifier>()
        for window in windows where seen.insert(ObjectIdentifier(window)).inserted {
            guard !window.isHidden,
                  window.alpha > 0,
                  window.windowLevel == .normal,
                  let root = window.rootViewController
            else {
                continue
            }

            if let anchor = attachedTopController(from: root, in: window) {
                return anchor
            }

            // Defensive compatibility path for custom containers that do not
            // expose their current controller through `children`. It is still
            // safe because we require the resolved view to be attached to the
            // exact candidate window and reject dismissing controllers.
            let fallback = root.topController()
            if fallback.viewIfLoaded?.window === window,
               !fallback.isBeingDismissed {
                return fallback
            }
        }

        NSLog(
            "🔐 PINPROMPT :: anchor scan exhausted — windows=%ld scenes=%ld appWindow=%@",
            windows.count,
            scenes.count,
            (UIApplication.shared.delegate?.window ?? nil) == nil ? "nil" : "set")
        return nil
    }

    /// Walk only the visible, attached presentation/container path. The
    /// generic `topController()` intentionally follows every
    /// `presentedViewController`, including a SwiftUI presentation host that
    /// is already being removed. Such a controller is not a valid presenter.
    private static func attachedTopController(
        from controller: UIViewController,
        in window: UIWindow
    ) -> UIViewController? {
        guard !controller.isBeingDismissed else {
            return nil
        }

        // Permit an unloaded container while walking down to its visible
        // child, but reject a controller that is attached elsewhere.
        if let attachedWindow = controller.viewIfLoaded?.window,
           attachedWindow !== window {
            return nil
        }

        if let presented = controller.presentedViewController,
           let top = attachedTopController(from: presented, in: window) {
            return top
        }

        if let tab = controller as? UITabBarController,
           let selected = tab.selectedViewController,
           let top = attachedTopController(from: selected, in: window) {
            return top
        }

        if let navigation = controller as? UINavigationController,
           let visible = navigation.visibleViewController,
           let top = attachedTopController(from: visible, in: window) {
            return top
        }

        if let split = controller as? UISplitViewController {
            for child in split.viewControllers.reversed() {
                if let top = attachedTopController(from: child, in: window) {
                    return top
                }
            }
        }

        // DWInitialViewController and SwiftUI presentation hosts are custom
        // containers. Following generic children is what reaches the visible
        // Send confirmation sheet instead of stopping at the app root.
        for child in controller.children.reversed() {
            if let top = attachedTopController(from: child, in: window) {
                return top
            }
        }

        guard controller.viewIfLoaded?.window === window else { return nil }
        return controller
    }
}
