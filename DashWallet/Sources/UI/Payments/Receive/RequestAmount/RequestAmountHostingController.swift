//
//  Created by Roman Chornyi
//  Copyright © 2026 Dash Core Group. All rights reserved.
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

import DashUIKit
import SwiftUI
import UIKit

// MARK: - RequestAmountHostingControllerDelegate

protocol RequestAmountHostingControllerDelegate: AnyObject {
    func requestAmountHostingController(
        _ controller: RequestAmountHostingController,
        didReceiveAmountWithInfo info: String)
}

// MARK: - RequestAmountHostingController

/// SwiftUI port of `DWRequestAmountViewController`, kept as a copy beside it —
/// the ObjC pair is still what the payments landing presents.
///
/// The chrome is `DashUIKit.BottomSheet` rather than the ObjC
/// `DWBaseModalViewController`: grabber, title and background all come from the
/// design system, so this holds nothing but the model wiring.
///
/// It still owns the model, because `DWReceiveModelProtocol` pushes updates
/// through a delegate rather than publishing them — `State` below is what turns
/// that into something SwiftUI can observe.
final class RequestAmountHostingController: UIViewController {

    weak var delegate: RequestAmountHostingControllerDelegate?

    private let model: DWReceiveModelProtocol
    private let state: State

    /// Bridges the ObjC delegate callback into `@Published` values.
    @MainActor
    fileprivate final class State: ObservableObject {
        @Published var qrCodeImage: UIImage?
        @Published var paymentAddress: String?
        @Published var username: String?
        /// Raised by a copy, cleared by `transientToast`'s own timer.
        @Published var copiedToastVisible = false
        /// Driven by the presenter's attended receive session, when it has one.
        @Published var isWatchingForReceipt = false
        /// The requested amount in fiat. Published rather than computed in the
        /// view: rates can land after this sheet is on screen, and the view
        /// redraws on this object alone.
        @Published var fiatAmount: String = ""
    }

    /// The content's natural height, as `BottomSheet(fillsHeight: false)`
    /// publishes it. Seeded before presentation and updated on every layout —
    /// the QR arriving, the username row appearing, Dynamic Type changing.
    fileprivate var measuredHeight: CGFloat = 0

    /// Handle for the exchange-rate subscription, released in `deinit`.
    private var exchangerObserver: CurrencyExchangerObserver?

    init(model: DWReceiveModelProtocol) {
        self.model = model
        self.state = State()
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Presentation

    /// Presents the sheet and keeps it sized to its content.
    ///
    /// The measuring lives here because it is the awkward part: SwiftUI's
    /// `.presentationDetents` — and so `BottomSheet.selfSizing` — does not
    /// bridge to a `UIHostingController` shown with `present()`; UIKit falls
    /// back to `.large`. What does cross the bridge is the height
    /// `BottomSheet(fillsHeight: false)` publishes for that modifier to read, so
    /// the same measurement drives a custom UIKit detent here: seeded from
    /// `sizeThatFits` before anything renders, then corrected by every
    /// `BottomSheetHeightPreferenceKey` update. A one-shot `sizeThatFits` is not
    /// enough — the amount's `scaleToFitWidth` reports its height from `State`,
    /// which is still zero on that first pass.
    @discardableResult
    static func present(
        from presenter: UIViewController,
        model: DWReceiveModelProtocol,
        delegate: RequestAmountHostingControllerDelegate?
    ) -> RequestAmountHostingController {
        let controller = RequestAmountHostingController(model: model)
        controller.delegate = delegate
        controller.modalPresentationStyle = .pageSheet

        if let sheet = controller.sheetPresentationController {
            // `BottomSheet` draws its own grabber.
            sheet.prefersGrabberVisible = false
            if #unavailable(iOS 26.0) {
                sheet.preferredCornerRadius = 24
            }
            let width = presenter.view.bounds.width
            controller.measuredHeight = controller.sheetHostingController
                .sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
                .height

            // The resolver reads the controller rather than a captured number,
            // so `invalidateDetents()` re-runs it against the latest
            // measurement instead of the one taken before the first render.
            sheet.detents = [.custom { [weak controller] context in
                guard let controller, controller.measuredHeight > 0 else {
                    return context.maximumDetentValue
                }
                // `fillsHeight: false` measures without the home-indicator
                // inset, so the strip has to be added back here.
                let bottomInset = controller.view.window?.safeAreaInsets.bottom ?? 0
                return min(controller.measuredHeight + bottomInset, context.maximumDetentValue)
            }]
        }

        presenter.present(controller, animated: true)
        return controller
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // The detent paints the bottom safe-area strip itself, so the sheet
        // background has to reach it.
        view.backgroundColor = UIColor(Color.dash.primaryBackground)

        setupContent()
        model.delegate = self
        reloadFromModel()

        // The requested amount arriving is what closes this screen, and the
        // only signal for it is the balance changing.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(checkRequestStatus),
            name: SwiftDashSDKWalletState.balanceDidChangeNotification,
            object: nil)

        // Rates can land after this sheet is up — the exchanger keeps its own
        // observer list rather than posting a notification, so subscribe to it
        // and restate the fiat line when it does.
        exchangerObserver = CurrencyExchanger.shared.addObserver { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.state.fiatAmount = CurrencyExchanger.shared
                    .fiatAmountString(for: self.model.amount.dashAmount)
            }
        }
    }

    deinit {
        if let exchangerObserver {
            CurrencyExchanger.shared.removeObserver(exchangerObserver)
        }
    }

    // MARK: - Content

    /// Built lazily and held, because `present(from:model:delegate:)` measures
    /// it before the view is ever loaded.
    fileprivate lazy var sheetHostingController: UIHostingController<AnyView> = {
        let screen = RequestAmountScreenContainer(
            state: state,
            amountDuffs: model.amount,
            onCopyAddress: { [weak self] in self?.copyAddress() },
            onCopyQRCode: { [weak self] in self?.copyQRCode() },
            onCopyUsername: { [weak self] in self?.copyUsername() },
            onShare: { [weak self] in self?.share() })

        let sheet = DashUIKit.BottomSheet(
            showBackButton: .constant(false),
            fillsHeight: false
        ) {
            screen
        }
        // SwiftUI hands preference updates to a `@Sendable` closure, so the hop
        // back to the main actor is explicit rather than implied by UIKit.
        .onPreferenceChange(DashUIKit.BottomSheetHeightPreferenceKey.self) { height in
            Task { @MainActor [weak self] in
                self?.contentHeightDidChange(height)
            }
        }
        return UIHostingController(rootView: AnyView(sheet))
    }()

    /// Reflect the presenter's attended receive session, so the sheet can say
    /// it is still watching. Left alone by presenters that have no session.
    func setWatchingForReceipt(_ watching: Bool) {
        state.isWatchingForReceipt = watching
    }

    /// Re-resolves the detent against the height that just came out of layout.
    /// Sub-point changes are ignored: the resolver rounds to the same detent
    /// anyway, and re-entering `animateChanges` on every measurement pass makes
    /// the sheet twitch.
    private func contentHeightDidChange(_ height: CGFloat) {
        guard height > 0, abs(height - measuredHeight) > 0.5 else { return }
        measuredHeight = height

        guard let sheet = sheetPresentationController else { return }
        sheet.animateChanges { sheet.invalidateDetents() }
    }

    private func setupContent() {
        let hostingController = sheetHostingController
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.backgroundColor = .clear
        addChild(hostingController)
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        hostingController.didMove(toParent: self)
    }

    private func reloadFromModel() {
        state.qrCodeImage = model.qrCodeImage
        state.paymentAddress = model.paymentAddress
        state.fiatAmount = CurrencyExchanger.shared.fiatAmountString(for: model.amount.dashAmount)
        #if DASHPAY
        state.username = model.username
        #endif
    }

    // MARK: - Actions

    private func copyAddress() {
        model.copyAddressToPasteboard()
        showCopied()
    }

    private func copyQRCode() {
        model.copyQRImageToPasteboard()
        showCopied()
    }

    private func copyUsername() {
        #if DASHPAY
        model.copyUsernameToPasteboard()
        showCopied()
        #endif
    }

    /// Only the haptic. The toast is drawn by the SwiftUI sheet through
    /// `transientToast`, the same `DashUIKit.Toast` the Receive tab raises —
    /// the UIKit `showToast` anchors to this controller's view, which inside a
    /// sheet puts it behind the sheet rather than over it.
    private func showCopied() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        state.copiedToastVisible = true
    }

    /// The helper anchors its iPad popover on a `UIButton`, and the real one
    /// lives inside SwiftUI where UIKit cannot reach it. This zero-sized stand-in
    /// sits at the centre of the content, which is where the popover would point
    /// anyway.
    private lazy var shareAnchor: UIButton = {
        let button = UIButton(frame: .zero)
        button.isUserInteractionEnabled = false
        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        return button
    }()

    private func share() {
        dw_shareReceiveInfo(model, sender: shareAnchor)
    }

    @objc
    private func checkRequestStatus() {
        guard let info = model.requestAmountReceivedInfoIfReceived() else { return }
        delegate?.requestAmountHostingController(self, didReceiveAmountWithInfo: info)
    }
}

// MARK: - DWReceiveModelDelegate

extension RequestAmountHostingController: DWReceiveModelDelegate {
    func receivingInfoDidUpdate() {
        reloadFromModel()
    }
}

// MARK: - Container

/// Observes the state mirror so the screen itself can stay a plain
/// value-in / closures-out view.
private struct RequestAmountScreenContainer: View {
    @ObservedObject var state: RequestAmountHostingController.State

    let amountDuffs: UInt64
    let onCopyAddress: () -> Void
    let onCopyQRCode: () -> Void
    let onCopyUsername: () -> Void
    let onShare: () -> Void

    var body: some View {
        RequestAmountScreen(
            amountDuffs: amountDuffs,
            fiatAmount: state.fiatAmount,
            qrCodeImage: state.qrCodeImage,
            paymentAddress: state.paymentAddress,
            username: state.username,
            isWatchingForReceipt: state.isWatchingForReceipt,
            onCopyAddress: onCopyAddress,
            onCopyQRCode: onCopyQRCode,
            onCopyUsername: onCopyUsername,
            onShare: onShare)
            .transientToast(
                isPresented: $state.copiedToastVisible,
                style: .copied,
                message: NSLocalizedString("Copied", comment: ""))
    }
}
