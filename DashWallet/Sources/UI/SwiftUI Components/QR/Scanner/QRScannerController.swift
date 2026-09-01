//
//  QRScannerController.swift
//  DashWallet
//
//  UIKit face of the unified QR scanner. Payment call sites (all of them
//  ObjC-reachable: DWBasePayViewController and friends) use the
//  block-based payment API; SwiftUI call sites embed QRScannerView
//  directly and only need this wrapper for modal UIKit presentation.
//

import SwiftUI
import UIKit

@objc(DWQRScannerController)
final class QRScannerController: UIViewController {

    /// Payment-mode completion. The block owns dismissal (mirrors the
    /// legacy `qrScanModel:didScanPaymentInput:` contract).
    @objc var onPaymentInput: ((DWPaymentInput) -> Void)?
    @objc var onCancel: (() -> Void)?
    /// Full-fidelity completion for Swift call sites. When set, it
    /// receives every result and cross-context routing is the caller's
    /// job; when nil, non-payment results are routed automatically.
    var onResult: ((QRScanResult) -> Void)?

    private let mode: QRScannerMode

    init(mode: QRScannerMode) {
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc static func paymentScanner(allowsCrossContextRouting: Bool) -> QRScannerController {
        QRScannerController(mode: .payment(allowsCrossContextRouting: allowsCrossContextRouting))
    }

    /// Form-field scanner: dismisses itself, hands the captured string to
    /// `onAddress`, and routes accepted redirect offers to their flows.
    static func addressScanner(expectsDashAddress: Bool,
                               onAddress: @escaping (String) -> Void) -> QRScannerController {
        let controller = QRScannerController(mode: .addressInput(expectsDashAddress: expectsDashAddress))
        controller.onResult = { [weak controller] result in
            let presenter = controller?.presentingViewController
            presenter?.dismiss(animated: true) {
                if case .text(let value) = result {
                    onAddress(value)
                } else {
                    QRScanResultRouter.route(result, from: presenter)
                }
            }
        }
        return controller
    }

    override var prefersStatusBarHidden: Bool { true }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()

        let scannerView = QRScannerView(
            mode: mode,
            onResult: { [weak self] result in
                self?.handleResult(result)
            },
            onCancel: { [weak self] in
                self?.handleCancel()
            })

        let hosting = UIHostingController(rootView: scannerView)
        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)

        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func handleResult(_ result: QRScanResult) {
        if let onResult {
            onResult(result)
            return
        }

        if case .payment(let input) = result, let onPaymentInput {
            onPaymentInput(input)
            return
        }

        // Cross-context payload accepted in payment mode: dismiss the
        // scanner, then take the user to the flow that owns it.
        let presenter = presentingViewController
        presenter?.dismiss(animated: true) {
            QRScanResultRouter.route(result, from: presenter)
        }
    }

    private func handleCancel() {
        if let onCancel {
            onCancel()
        } else {
            presentingViewController?.dismiss(animated: true)
        }
    }
}

extension UIViewController {
    /// Presents the payment QR scanner. The completion owns dismissal;
    /// cross-context payloads (contact / invitation QR) are routed by the
    /// scanner itself. (ObjC call sites go through
    /// `DWBasePayViewController performScanQRCodeAction` instead.)
    func presentPaymentScanner(onPaymentInput: @escaping (DWPaymentInput) -> Void) {
        if presentedViewController is QRScannerController {
            return
        }

        let controller = QRScannerController.paymentScanner(allowsCrossContextRouting: true)
        controller.onPaymentInput = onPaymentInput
        controller.onCancel = { [weak self] in
            self?.dismiss(animated: true)
        }
        present(controller, animated: true, completion: nil)
    }
}
