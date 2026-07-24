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
        let foregroundScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }

        // Prefer the app delegate's long-lived DWWindow. While a SwiftUI text
        // field resigns first responder, a transient presentation/keyboard
        // window can briefly become `isKeyWindow`; resolving from it produced
        // a detached PresentationHostingController and UIKit dropped the PIN.
        var windows: [UIWindow] = []
        if let appWindow = UIApplication.shared.delegate?.window ?? nil {
            windows.append(appWindow)
        }
        windows.append(contentsOf: foregroundScenes.flatMap(\.windows))

        var seen = Set<ObjectIdentifier>()
        for window in windows where seen.insert(ObjectIdentifier(window)).inserted {
            guard !window.isHidden,
                  window.alpha > 0,
                  window.windowLevel == .normal,
                  let root = window.rootViewController,
                  let anchor = attachedTopController(from: root, in: window)
            else {
                continue
            }
            return anchor
        }
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
        guard controller.viewIfLoaded?.window === window,
              !controller.isBeingDismissed else {
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

        return controller
    }
}
