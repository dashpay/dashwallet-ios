//
//  EnterAddressHostingController.swift
//  DashWallet
//
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
import UIKit

class EnterAddressHostingController: UIViewController {

    var onAddressConfirmed: ((MayaCryptoCurrency, String) -> Void)?

    private let coin: MayaCryptoCurrency
    private let viewModel: EnterAddressViewModel

    init(coin: MayaCryptoCurrency) {
        self.coin = coin
        self.viewModel = EnterAddressViewModel(coin: coin)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("Enter address", comment: "Maya")
        view.backgroundColor = UIColor.dw_secondaryBackground()
        navigationItem.largeTitleDisplayMode = .never

        let enterAddressView = EnterAddressView(
            viewModel: viewModel,
            onScanQR: { [weak self] in
                self?.presentQRScanner()
            },
            onContinue: { [weak self] address in
                guard let self else { return }
                DSLogger.log("Maya: Address confirmed for \(self.coin.code): \(address)")
                self.onAddressConfirmed?(self.coin, address)
            }
        )

        let hostingController = UIHostingController(rootView: enterAddressView)
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
    }

    // MARK: - QR Scanner

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
}
