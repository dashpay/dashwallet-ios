//
//  Created by Pavel Tikhonenko
//  Copyright © 2022 Dash Core Group. All rights reserved.
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
import SafariServices
import SwiftUI
import UIKit

// MARK: - TXDetailViewController

/// Hosts `TxDetailScreen`. A plain view controller rather than a
/// `UIHostingController` subclass so Objective-C keeps seeing it and
/// `SuccessTxDetailViewController`; it only embeds the screen, opens web pages
/// and closes.
@objc(DWTxDetailViewController)
class TXDetailViewController: UIViewController, NavigationBarDisplayable {
    var isNavigationBarHidden: Bool { true }

    @objc private(set) var model: TxDetailModel
    let viewModel: TxDetailViewModel

    /// Handles VoiceOver's escape gesture when set. Escape travels up the UIKit
    /// responder chain, so a SwiftUI host cannot answer it with
    /// `.accessibilityAction(.escape)`. An escape that rises from a controller
    /// this one presented is left to the default handling, so it closes that
    /// controller and not this screen. Returns whether it acted; when it did
    /// not, the default handling runs.
    var onAccessibilityEscape: (() -> Bool)?

    /// The contact whose profile a host already sits on, and how to go back to
    /// it: that contact's row goes back instead of stacking a second profile
    /// on top.
    struct ContactReturn {
        let identityId: Data
        let goBack: () -> Void
    }

    var contactReturn: ContactReturn? {
        didSet { host?.rootView = makeScreen() }
    }

    private var host: UIHostingController<TxDetailScreen>?

    @objc
    init(model: TxDetailModel) {
        self.model = model
        viewModel = TxDetailViewModel(model: model)
        super.init(nibName: nil, bundle: nil)
    }

    /// For tests: a screen whose rows follow `recoveryInputs`.
    init(viewModel: TxDetailViewModel) {
        model = viewModel.model
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The close circle, when this screen opens as the root of a modal
    /// navigation stack. Embedded (a SwiftUI sheet, a snapshot) it has none.
    internal var chrome: TxDetailScreen.Chrome {
        navigationController?.viewControllers.first === self ? .closeButton : .none
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .dw_secondaryBackground()

        viewModel.onClose = { [weak self] message in
            guard let self else { return }
            // Shown where the user lands: this screen's own toast would leave
            // with it.
            let presenter = self.presentingViewController
            self.closeAction()
            if let message, let presenter {
                presenter.presentDashUIKitToast(style: message.style, message: message.message)
            }
        }

        let host = UIHostingController(rootView: makeScreen())
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
        self.host = host
    }

    override func accessibilityPerformEscape() -> Bool {
        guard let onAccessibilityEscape, presentedViewController == nil, onAccessibilityEscape() else {
            return super.accessibilityPerformEscape()
        }
        return true
    }

    @objc
    func closeAction() {
        dismiss(animated: true)
    }

    private func makeScreen() -> TxDetailScreen {
        TxDetailScreen(
            viewModel: viewModel,
            chrome: chrome,
            onClose: { [weak self] in self?.closeAction() },
            contactReturn: contactReturn,
            openURL: { [weak self] url in self?.openInBrowser(url) })
    }

    private func openInBrowser(_ url: URL) {
        let controller = SFSafariViewController.dw_controller(with: url)
        controller.modalPresentationStyle = .overFullScreen
        controller.modalPresentationCapturesStatusBarAppearance = true
        present(controller, animated: true)
    }
}

// MARK: - SuccessTxDetailViewControllerDelegate

@objc
protocol SuccessTxDetailViewControllerDelegate: AnyObject {
    func txDetailViewControllerDidFinish(controller: SuccessTxDetailViewController)
}

// MARK: - SuccessTxDetailViewController

/// The details shown after a payment, closed with a button at the bottom.
@objc
class SuccessTxDetailViewController: TXDetailViewController {
    @objc weak var delegate: SuccessTxDetailViewControllerDelegate?

    override var chrome: TxDetailScreen.Chrome { .bottomCloseButton }

    override func closeAction() {
        dismiss(animated: true) { [weak self] in
            if let self {
                self.delegate?.txDetailViewControllerDidFinish(controller: self)
            }
        }
    }
}

// MARK: - SwiftUI wrapper
struct TXDetailVCWrapper: UIViewControllerRepresentable {
    @Environment(\.presentationMode) private var presentationMode
    
    private let makeModel: () -> TxDetailModel
    @Binding var navigateBack: Bool
    var onDismissed: (() -> Void)? = nil
    /// VoiceOver's escape gesture on the detail, returning whether it acted; `nil` or
    /// `false` leaves the gesture to the default handling.
    var onAccessibilityEscape: (() -> Bool)? = nil
    
    /// See `TXDetailViewController.contactReturn`.
    var contactReturn: TXDetailViewController.ContactReturn? = nil

    init(tx: Transaction,
         navigateBack: Binding<Bool>,
         onDismissed: (() -> Void)? = nil,
         contactReturn: TXDetailViewController.ContactReturn? = nil,
         onAccessibilityEscape: (() -> Bool)? = nil) {
        self.init(makeModel: { .init(transaction: tx) }, navigateBack: navigateBack,
                  onDismissed: onDismissed, contactReturn: contactReturn,
                  onAccessibilityEscape: onAccessibilityEscape)
    }

    init(model: TxDetailModel,
         navigateBack: Binding<Bool>,
         onDismissed: (() -> Void)? = nil,
         contactReturn: TXDetailViewController.ContactReturn? = nil) {
        self.init(makeModel: { model }, navigateBack: navigateBack,
                  onDismissed: onDismissed, contactReturn: contactReturn, onAccessibilityEscape: nil)
    }

    init(swapOrder: BuySwapOrderItem, navigateBack: Binding<Bool>) {
        self.init(makeModel: { .init(swapOrder: swapOrder) }, navigateBack: navigateBack,
                  onDismissed: nil, contactReturn: nil, onAccessibilityEscape: nil)
    }

    private init(makeModel: @escaping () -> TxDetailModel,
                 navigateBack: Binding<Bool>,
                 onDismissed: (() -> Void)?,
                 contactReturn: TXDetailViewController.ContactReturn?,
                 onAccessibilityEscape: (() -> Bool)?) {
        self.makeModel = makeModel
        self._navigateBack = navigateBack
        self.onDismissed = onDismissed
        self.contactReturn = contactReturn
        self.onAccessibilityEscape = onAccessibilityEscape
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> TXDetailViewController {
        let vc = TXDetailViewController(model: makeModel())
        vc.contactReturn = contactReturn
        vc.onAccessibilityEscape = onAccessibilityEscape
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) {
        uiViewController.contactReturn = contactReturn
        uiViewController.onAccessibilityEscape = onAccessibilityEscape
        if navigateBack {
            context.coordinator.dismissView()
            navigateBack = false
            onDismissed?()
        }
    }
    
    class Coordinator: NSObject {
        var parent: TXDetailVCWrapper
        
        init(_ parent: TXDetailVCWrapper) {
            self.parent = parent
        }
        
        func dismissView() {
            DispatchQueue.main.async {
                self.parent.presentationMode.wrappedValue.dismiss()
            }
        }
    }
}
