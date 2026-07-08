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
        }
    }

    /// The controller a modal should be presented from: the top of the key
    /// window's presentation stack.
    private static func topPresentedController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first

        let keyWindow = scene?.windows.first(where: { $0.isKeyWindow }) ?? scene?.windows.first
        guard let root = keyWindow?.rootViewController else { return nil }
        return root.topController()
    }
}
