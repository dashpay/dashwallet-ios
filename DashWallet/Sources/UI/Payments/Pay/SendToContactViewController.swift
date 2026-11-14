//
//  SendToContactViewController.swift
//  DashWallet
//
//  UIKit host for "Send to username" step one. Step two is the shared
//  `ExternalSendAmountScreen`, pushed by `pushExternalSendAmount` — the same
//  amount step an address send ends on.
//

#if DASHPAY

import SwiftUI
import UIKit

/// The established-contact picker.
///
/// A `DWBasePayViewController` because that is where the send-success
/// presentation and the Close handling behind it live: the amount step this
/// pushes is a plain hosting controller, and the pay-to-contact call it runs
/// reports back here.
final class SendToContactPickerViewController: DWBasePayViewController, NavigationBarDisplayable {
    var isBackButtonHidden: Bool { true }
    var isNavigationBarHidden: Bool { true }

    private let viewModel = SendToContactPickerViewModel()

    private lazy var hostingController: UIHostingController<SendToContactPickerScreen> = {
        let screen = SendToContactPickerScreen(
            viewModel: viewModel,
            onBack: { [weak self] in self?.navigationController?.popViewController(animated: true) },
            onSelect: { [weak self] contact in self?.pushPaymentSteps(for: contact) })
        return UIHostingController(rootView: screen)
    }()

    override func viewDidLoad() {
        // `DWBasePayViewController.viewDidLoad` asserts on a nil pay model; the
        // picker never uses it, but the base class builds its payment
        // controller around one.
        if payModel == nil {
            payModel = DWPayModel()
        }
        super.viewDidLoad()
        view.backgroundColor = .dw_background()

        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.backgroundColor = .clear
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        hostingController.didMove(toParent: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // The contacts tab owns the periodic DashPay sync; this stack never
        // runs it, so rebuild the snapshot from SwiftData on the way in —
        // otherwise the picker shows whatever the last visit to that tab left.
        viewModel.refresh()
    }

    /// The contact IS the destination, so the address step has nothing to ask.
    /// The From step asks only when more than one balance can pay; otherwise
    /// the flow goes straight to the amount. Back from either returns here.
    private func pushPaymentSteps(for contact: ContactItem) {
        let sendViewModel = SendViewModel()
        sendViewModel.setContactRecipient(contact)
        let onSendCompleted: () -> Void = { [weak self] in self?.finishSendFlow() }
        if sendViewModel.contactOffersSourceChoice {
            pushExternalSendSource(viewModel: sendViewModel, onSendCompleted: onSendCompleted)
        } else {
            pushExternalSendAmount(viewModel: sendViewModel, onSendCompleted: onSendCompleted)
        }
    }
}

#endif
