//
//  SendToContactViewController.swift
//  DashWallet
//
//  UIKit hosts for the two "Send to username" steps. Both are pushed onto the
//  payments navigation stack and draw their own DashUIKit header, so both hide
//  the UIKit bar.
//

#if DASHPAY

import SwiftUI
import UIKit

// MARK: - Step 1: contact picker

/// The established-contact picker. A plain hosting controller: picking a
/// contact spends nothing, so it needs none of `DWBasePayViewController`'s
/// payment machinery — the amount step, which does spend, is the one that
/// subclasses it.
final class SendToContactPickerViewController: UIViewController, NavigationBarDisplayable {
    var isBackButtonHidden: Bool { true }
    var isNavigationBarHidden: Bool { true }

    private let viewModel = SendToContactPickerViewModel()

    private lazy var hostingController: UIHostingController<SendToContactPickerScreen> = {
        let screen = SendToContactPickerScreen(
            viewModel: viewModel,
            onBack: { [weak self] in self?.navigationController?.popViewController(animated: true) },
            onSelect: { [weak self] contact in self?.pushAmountStep(for: contact) })
        return UIHostingController(rootView: screen)
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .dw_background()
        embedFullScreen(hostingController)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // The contacts tab owns the periodic DashPay sync; this stack never
        // runs it, so rebuild the snapshot from SwiftData on the way in —
        // otherwise the picker shows whatever the last visit to that tab left.
        viewModel.refresh()
    }

    private func pushAmountStep(for contact: ContactItem) {
        let controller = SendToContactAmountViewController(contact: contact)
        controller.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(controller, animated: true)
    }
}

// MARK: - Step 2: amount

/// The amount step. A `DWBasePayViewController` for the send-success screen:
/// the base class owns `presentSendSuccessWithTxidWire:` and the Close
/// handling behind it (pop to root, then Home), so a contact payment lands
/// exactly where an address payment does.
final class SendToContactAmountViewController: DWBasePayViewController, NavigationBarDisplayable {
    var isBackButtonHidden: Bool { true }
    var isNavigationBarHidden: Bool { true }

    private let viewModel: SendToContactAmountViewModel

    private lazy var hostingController: UIHostingController<SendToContactAmountScreen> = {
        let screen = SendToContactAmountScreen(
            viewModel: viewModel,
            onBack: { [weak self] in self?.navigationController?.popViewController(animated: true) },
            onSend: { [weak self] in self?.send() })
        return UIHostingController(rootView: screen)
    }()

    init(contact: ContactItem) {
        viewModel = SendToContactAmountViewModel(contact: contact)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        // `DWBasePayViewController.viewDidLoad` asserts on a nil pay model;
        // this step never uses it, but the base class builds its payment
        // controller around one.
        if payModel == nil {
            payModel = DWPayModel()
        }
        super.viewDidLoad()
        view.backgroundColor = .dw_background()
        embedFullScreen(hostingController)
    }

    /// Run the spend, then hand the broadcast txid to the shared success
    /// screen. A failure (or a cancelled PIN prompt) leaves the user on this
    /// step — the view model carries the message the screen shows inline.
    private func send() {
        Task { [weak self] in
            guard let self else { return }
            guard let txidWire = await self.viewModel.send() else { return }
            self.presentSendSuccess(withTxidWire: txidWire)
        }
    }
}

// MARK: - Embedding

extension UIViewController {
    /// Pin a child controller's view to this controller's bounds. Shared by
    /// the two steps above, which are both a hosting controller in a plain
    /// container.
    fileprivate func embedFullScreen(_ child: UIViewController) {
        addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        child.view.backgroundColor = .clear
        view.addSubview(child.view)
        NSLayoutConstraint.activate([
            child.view.topAnchor.constraint(equalTo: view.topAnchor),
            child.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            child.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            child.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        child.didMove(toParent: self)
    }
}

#endif
