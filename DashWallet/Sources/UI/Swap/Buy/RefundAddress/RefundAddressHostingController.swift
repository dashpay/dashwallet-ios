//
//  RefundAddressHostingController.swift
//  DashWallet
//
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

import SwiftUI
import UIKit

final class RefundAddressHostingController: UIViewController, NavigationBarDisplayable {
    var isNavigationBarHidden: Bool { true }

    var onRefundAddressConfirmed: ((SwapCryptoCurrency, String) -> Void)?

    private let coin: SwapCryptoCurrency
    private let viewModel: RefundAddressViewModel
    private lazy var keyboardDismissTapRecognizer: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        recognizer.cancelsTouchesInView = false
        return recognizer
    }()

    init(coin: SwapCryptoCurrency) {
        self.coin = coin
        self.viewModel = RefundAddressViewModel(coin: coin)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.dw_secondaryBackground()

        let swiftUIView = RefundAddressView(
            viewModel: viewModel,
            onBack: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            },
            onScanQR: { [weak self] in
                self?.presentQRScanner()
            },
            onContinue: { [weak self] refundAddress in
                guard let self else { return }
                self.onRefundAddressConfirmed?(self.coin, refundAddress)
            }
        )

        let hostingController = UIHostingController(rootView: swiftUIView)
        hostingController.view.backgroundColor = .clear

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)

        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        hostingController.view.addGestureRecognizer(keyboardDismissTapRecognizer)
    }

    private func presentQRScanner() {
        let scanner = GenericQRScannerController()
        scanner.modalPresentationStyle = .fullScreen

        scanner.onQRCodeScanned = { [weak self, weak scanner] scannedValue in
            scanner?.dismiss(animated: true) {
                self?.viewModel.setAddress(scannedValue)
            }
        }

        scanner.onCancel = { [weak scanner] in
            scanner?.dismiss(animated: true)
        }

        present(scanner, animated: true)
    }

    @objc
    private func dismissKeyboard() {
        view.endEditing(true)
    }
}
