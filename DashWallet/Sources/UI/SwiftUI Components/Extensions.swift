//  
//  Created by Andrei Ashikhmin
//  Copyright © 2024 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import SwiftUI

extension View {
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        Group {
            if condition {
                transform(self)
            } else {
                self
            }
        }
    }
}

extension View {
    /// Closes the ways out of a screen that the screen's own Back button does
    /// not cover — the navigation edge swipe and a sheet's swipe-down — while
    /// `locked`, for a payment that is waiting on the network or whose result
    /// is on the screen unacknowledged. The screen keeps its own Back button
    /// out of reach for as long (disables it). While locked and visible, the
    /// screen also owns the app's routing and tab bar (`ExitHold`). A screen
    /// hidden by a push, another tab or a full-screen cover holds nothing (a
    /// cover is itself a presentation the router respects); one under a sheet
    /// or an alert keeps its hold.
    func lockingExit(_ locked: Bool) -> some View {
        background(ExitLockView(locked: locked))
            // A SwiftUI-presented sheet keeps its own dismissal preference.
            .interactiveDismissDisabled(locked)
    }
}

/// Whether a payment owns the screen — a send waiting on the network (each
/// Core send's network wait, `SwiftDashSDKTransactionSender.waitingForNetwork`;
/// the payment processor's broadcast through its outcome callback; the
/// DashSpend purchase and the swap submission as a whole) or a payment screen
/// with its exits held (`ExitHold`: during its send, or while it shows an
/// unacknowledged result inline) — each through a `PaymentInFlightHold`. With
/// what is presented on screen, it decides whether an incoming link may
/// replace what is shown (`refusesLink(over:)`) and whether the user may
/// switch tabs (`refusesTabChange()`).
@objc(DWPaymentInFlight)
final class PaymentInFlight: NSObject {
    /// How long after the last hold ends links are still refused.
    /// Some send results reach the screen a beat after the send returns — one
    /// executor hop or one render pass: the Home popup sweep's error dialog
    /// (its model is not main-actor), the Tools sweep's SwiftUI alert, the
    /// DashSpend purchase's error dialog. A link routed in that beat would
    /// dismiss or bury the result before it shows.
    static let resultGracePeriod: TimeInterval = 1

    /// Live `PaymentInFlightHold`s. Guarded by `lock`: a hold can be freed on
    /// any thread, and it ends there and then.
    private static var holds = Set<UInt64>()
    private static var nextHoldToken: UInt64 = 0
    /// When the last hold ended; links stay refused for `resultGracePeriod`.
    private static var lastHoldEnded: Date?
    private static let lock = NSLock()

    /// A hold is live: a send waits, or a payment screen holds its exits.
    /// Routing asks `isActiveOrSettling`, which adds the grace after.
    static var isActive: Bool { lock.withLock { !holds.isEmpty } }

    /// A hold is live (a send waits, or a payment screen holds its exits), or
    /// one ended less than `resultGracePeriod` ago.
    static var isActiveOrSettling: Bool {
        lock.withLock {
            guard holds.isEmpty else { return true }
            guard let lastHoldEnded else { return false }
            return Date().timeIntervalSince(lastHoldEnded) < resultGracePeriod
        }
    }

    static func beginHold() -> UInt64 {
        lock.withLock {
            nextHoldToken += 1
            holds.insert(nextHoldToken)
            return nextHoldToken
        }
    }

    static func endHold(_ token: UInt64) {
        lock.withLock {
            guard holds.remove(token) != nil, holds.isEmpty else { return }
            lastHoldEnded = Date()
        }
    }

    /// The wallet or network the holds belong to is gone (wipe, network
    /// switch): links must not be refused for its sends. The holds end here,
    /// with no grace period; ending them again is a no-op.
    @objc static func abandonHolds() {
        lock.withLock {
            holds.removeAll()
            lastHoldEnded = nil
        }
    }

    /// What was refused, for the notice's wording.
    enum Refusal {
        case link
        /// A tab change, or a notification tap that would present a screen.
        case navigation
    }

    /// Shows the notice for a refusal (`RefusalNotice`); tests replace it.
    @MainActor
    static var showRefusalNotice: (Refusal) -> Void = { RefusalNotice.show($0) }

    /// For a link whose routing would dismiss or replace what is on screen
    /// (`MainTabbarController.performPay(to:)` and its siblings start with
    /// `dismiss(animated: false)` on the main screen), or a notification tap
    /// that would present a screen: it never destroys or covers what is
    /// shown. While a payment owns the screen — a send waits or a payment
    /// screen holds its exits — or for the grace after
    /// (`isActiveOrSettling`), or while anything is presented in the chain
    /// that dismissal would tear down — a sheet, an alert, a send's success
    /// screen — it is refused and a short notice says so; it is not kept for
    /// later.
    ///
    /// - Parameter root: the window's root, which contains the main screen.
    /// - Returns: whether it was refused.
    @MainActor
    static func refuses(_ refusal: Refusal, over root: UIViewController) -> Bool {
        guard isActiveOrSettling || isAnythingPresented(over: root) else { return false }
        showRefusalNotice(refusal)
        return true
    }

    /// `refuses(.link, over:)`, for the root's URL and deep-link routing.
    @MainActor
    @objc(refusesLinkOverRoot:)
    static func refusesLink(over root: UIViewController) -> Bool {
        refuses(.link, over: root)
    }

    /// Something is presented that the router's `dismiss(animated: false)`
    /// would tear down: a presentation by `root` or by one of its direct
    /// children (the main screen), which is where every presentation lands
    /// that does not stay inside a screen's own presentation context.
    /// Presentations kept inside a context (a search field's controller in a
    /// tab, a screen that defines its own context) are not dismissed by the
    /// router and do not count.
    @MainActor
    static func isAnythingPresented(over root: UIViewController) -> Bool {
        root.presentedViewController != nil
            || root.children.contains { $0.presentedViewController != nil }
    }

    /// For the tab bar: while a payment owns the screen, or for the grace
    /// after (`isActiveOrSettling`) — a result can reach the screen a beat
    /// after its send's hold ends — switching tabs would hide the send or its
    /// result; it is refused with a short notice.
    ///
    /// - Returns: whether the tab change was refused.
    @MainActor
    static func refusesTabChange() -> Bool {
        guard isActiveOrSettling else { return false }
        showRefusalNotice(.navigation)
        return true
    }

}

/// The notice for a refused link, notification tap or tab change
/// (`PaymentInFlight`): the app's
/// toast (`showToast`) in a window of its own above the app's, so it shows
/// over an alert or a success screen — also one presented after it. The
/// window is a strip just below the status bar, where an open keyboard does
/// not hide it; it never becomes key and takes no touches, so it leaves the
/// status bar, the key window and the screens under it alone.
@MainActor
private enum RefusalNotice {
    static func text(for refusal: PaymentInFlight.Refusal) -> String {
        switch refusal {
        case .link:
            return NSLocalizedString(
                "Finish or close the current screen first, then open the link again.",
                comment: "Notice: a link was opened while a send was in progress or another screen was open; the link was ignored")
        case .navigation:
            return NSLocalizedString(
                "Finish or close the current screen first.",
                comment: "Notice: the user tried to switch tabs or open a notification while a payment or its result was on screen; nothing changed")
        }
    }
    private static let duration: TimeInterval = 3
    private static var window: NoticeWindow?
    private static var hideWork: DispatchWorkItem?

    private final class NoticeWindow: UIWindow {
        override var canBecomeKey: Bool { false }
    }

    static func show(_ refusal: PaymentInFlight.Refusal) {
        let text = text(for: refusal)
        // After the app has become active: VoiceOver drops an announcement
        // made while the screen changes under it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            UIAccessibility.post(notification: .announcement, argument: text)
        }
        let appWindow = PinPromptPresenter.appWindows().first
        let screenBounds = appWindow?.bounds ?? UIScreen.main.bounds

        // Reused while it is in the app window's scene; a reconnected scene
        // gets a new one.
        let window = Self.window.flatMap { $0.windowScene === appWindow?.windowScene ? $0 : nil }
            ?? OverlayWindow.make(NoticeWindow.self)
        window.isUserInteractionEnabled = false
        let root = window.rootViewController ?? UIViewController()
        root.view.backgroundColor = .clear
        root.view.subviews.forEach { $0.removeFromSuperview() }
        window.rootViewController = root
        Self.window = window

        // Starts below the status bar, so it has no say over it; the toast
        // sits on the strip's bottom edge, and the strip is as tall as the
        // toast is at the current text size.
        let width = screenBounds.width
        let top = appWindow?.safeAreaInsets.top ?? 0
        window.frame = CGRect(x: 0, y: top, width: width, height: screenBounds.height - top)
        window.isHidden = false
        let toast = root.showToast(text: text, duration: duration)
        root.view.layoutIfNeeded()
        let inset = UIViewController.toastEdgeInset
        window.frame = CGRect(x: 0, y: top, width: width, height: max(toast.bounds.height, 44) + 2 * inset)

        // The toast's own fade-out ends a second after `duration`.
        hideWork?.cancel()
        let hide = DispatchWorkItem {
            Self.window?.isHidden = true
        }
        hideWork = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 1.5, execute: hide)
    }
}

/// One owner's share of `PaymentInFlight`: a send waiting on the network, or a
/// payment screen's exit hold (`ExitHold`). It ends
/// exactly once — by `end()`, when a teardown abandons it
/// (`PaymentInFlight.abandonHolds`), or when the hold itself is freed,
/// so an owner that drops it cannot leave links refused for good. Thread-safe.
@objc(DWPaymentInFlightHold)
final class PaymentInFlightHold: NSObject {
    private let token = PaymentInFlight.beginHold()

    /// Idempotent.
    @objc func end() {
        PaymentInFlight.endHold(token)
    }

    deinit {
        PaymentInFlight.endHold(token)
    }
}

/// One hold on the ways out of a screen: its navigation stack's edge swipe and
/// its presented root's swipe-down. Holds are counted per stack and per root,
/// so independent owners (`lockingExit`, `PaymentController`) can overlap: the
/// first hold saves the original value, the last release restores it.
///
/// A screen whose exits are held owns the app's routing too (`ownsRouting`):
/// while any such hold is live, an incoming link that would replace the
/// screen, a notification tap and a tab change are refused
/// (`PaymentInFlight`). `lockingExit` uses it for a payment screen during its
/// send and while it shows an unacknowledged result inline — a SwiftUI
/// dialog, which is not a presentation the router can see — and a pushed
/// result screen while it is visible. `PaymentController`'s hold during a
/// broadcast does not own routing: the payment processor holds it.
@MainActor
final class ExitHold {
    private final class Count {
        var holds = 0
        var original = false
    }

    private static let navigationCounts = NSMapTable<UINavigationController, Count>.weakToStrongObjects()
    private static let presentationCounts = NSMapTable<UIViewController, Count>.weakToStrongObjects()

    private weak var navigation: UINavigationController?
    private weak var presentedRoot: UIViewController?
    /// This hold's share of `PaymentInFlight`, if it owns routing; freed with
    /// the hold, it ends.
    private let routing: PaymentInFlightHold?

    /// - Parameter ownsRouting: whether the held screen also owns the app's
    ///   routing and tab bar. Owners take the hold only while their screen is
    ///   visible (`lockingExit`, a result screen's appearance); an owner whose
    ///   wait is already held for routing passes false.
    init(on controller: UIViewController, ownsRouting: Bool = true) {
        routing = ownsRouting ? PaymentInFlightHold() : nil
        if let navigationController = controller.navigationController {
            let count = Self.count(for: navigationController, in: Self.navigationCounts)
            if count.holds == 0 {
                count.original = navigationController.interactivePopGestureRecognizer?.isEnabled ?? true
                navigationController.interactivePopGestureRecognizer?.isEnabled = false
            }
            count.holds += 1
            navigation = navigationController
        }
        var root = controller
        while let parent = root.parent { root = parent }
        if root.presentingViewController != nil {
            let count = Self.count(for: root, in: Self.presentationCounts)
            if count.holds == 0 {
                count.original = root.isModalInPresentation
                root.isModalInPresentation = true
            }
            count.holds += 1
            presentedRoot = root
        }
    }

    /// Idempotent.
    func release() {
        if let navigationController = navigation,
           let count = Self.navigationCounts.object(forKey: navigationController) {
            count.holds -= 1
            if count.holds == 0 {
                navigationController.interactivePopGestureRecognizer?.isEnabled = count.original
                Self.navigationCounts.removeObject(forKey: navigationController)
            }
        }
        if let root = presentedRoot, let count = Self.presentationCounts.object(forKey: root) {
            count.holds -= 1
            if count.holds == 0 {
                root.isModalInPresentation = count.original
                Self.presentationCounts.removeObject(forKey: root)
            }
        }
        navigation = nil
        presentedRoot = nil
        routing?.end()
    }

    private static func count<Key: AnyObject>(for key: Key, in table: NSMapTable<Key, Count>) -> Count {
        if let count = table.object(forKey: key) { return count }
        let count = Count()
        table.setObject(count, forKey: key)
        return count
    }
}

private struct ExitLockView: UIViewControllerRepresentable {
    let locked: Bool

    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.locked = locked
    }

    final class Controller: UIViewController {
        var locked = false {
            didSet { if locked != oldValue { apply() } }
        }

        private var hold: ExitHold?
        /// Between `viewWillAppear` and `viewWillDisappear`: a hold is only
        /// taken for a screen the user can see, or a screen hidden behind a
        /// push, another tab or a full-screen cover could refuse routing with
        /// nothing of it on screen. A sheet or an alert over the screen does
        /// not end its appearance, so the hold stays.
        private var isVisible = false

        override func loadView() {
            // Behind the screen's content; it must not take its taps.
            view = UIView()
            view.isUserInteractionEnabled = false
        }

        deinit {
            // Torn down while still locked, without a viewWillDisappear.
            let hold = hold
            Task { @MainActor in hold?.release() }
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            apply()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            isVisible = true
            // Back from another tab or a cover while still locked.
            apply()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            isVisible = false
            // The stack's gesture is shared; never hold it for a screen that
            // is no longer showing.
            hold?.release()
            hold = nil
        }

        private func apply() {
            if locked, hold == nil, parent != nil, isVisible {
                hold = ExitHold(on: self)
            } else if !locked {
                hold?.release()
                hold = nil
            }
        }
    }
}

extension Font {
    var pointSize: CGFloat {
        return self.uiFont.pointSize
    }
    
    var uiFont: UIFont {
        switch self {
        case .largeTitle:
            return UIFont.preferredFont(forTextStyle: .largeTitle)
        case .title:
            return UIFont.preferredFont(forTextStyle: .title1)
        case .title2:
            return UIFont.preferredFont(forTextStyle: .title2)
        case .title3:
            return UIFont.preferredFont(forTextStyle: .title3)
        case .headline:
            return UIFont.preferredFont(forTextStyle: .headline)
        case .subheadline:
            return UIFont.preferredFont(forTextStyle: .subheadline)
        case .body:
            return UIFont.preferredFont(forTextStyle: .body)
        case .callout:
            return UIFont.preferredFont(forTextStyle: .callout)
        case .footnote:
            return UIFont.preferredFont(forTextStyle: .footnote)
        case .caption:
            return UIFont.preferredFont(forTextStyle: .caption1)
        case .caption2:
            return UIFont.preferredFont(forTextStyle: .caption2)
        default:
            return UIFont.systemFont(ofSize: UIFont.systemFontSize)
        }
    }
}
