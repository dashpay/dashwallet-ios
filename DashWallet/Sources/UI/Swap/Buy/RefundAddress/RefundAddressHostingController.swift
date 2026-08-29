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

    var onOrderCreated: ((SwapCryptoCurrency, BuyOrder) -> Void)?

    private let coin: SwapCryptoCurrency
    private let viewModel: RefundAddressViewModel
    private lazy var keyboardDismissTapRecognizer: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        recognizer.cancelsTouchesInView = false
        return recognizer
    }()

    init(coin: SwapCryptoCurrency, sellAmount: String, swapProvider: SwapProvider) {
        self.coin = coin
        self.viewModel = RefundAddressViewModel(coin: coin, sellAmount: sellAmount, swapProvider: swapProvider)
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
            onOrderCreated: { [weak self] order in
                guard let self else { return }
                self.onOrderCreated?(self.coin, order)
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
        // The refund address is on the sold coin's chain, not Dash.
        let scanner = QRScannerController.addressScanner(expectsDashAddress: false) { [weak self] address in
            self?.viewModel.setAddress(address)
        }
        present(scanner, animated: true)
    }

    @objc
    private func dismissKeyboard() {
        view.endEditing(true)
    }
}
