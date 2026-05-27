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

import AuthenticationServices
import SwiftUI
import UIKit

class EnterAddressHostingController: UIViewController {

    var onAddressConfirmed: ((MayaCryptoCurrency, String) -> Void)?

    private let coin: MayaCryptoCurrency
    private let viewModel: EnterAddressViewModel
    private var authSession: ASWebAuthenticationSession?

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
                self.validateAndContinue(address: address)
            },
            onLoginUphold: { [weak self] in
                self?.presentUpholdLogin()
            },
            onLoginCoinbase: { [weak self] in
                self?.presentCoinbaseLogin()
            }
        )

        let hostingController = UIHostingController(rootView: enterAddressView)
        // Match SwiftUI's Color.primaryBackground to prevent flash during system paste banner dismissal
        hostingController.view.backgroundColor = UIColor(named: "SecondaryBackgroundColor")

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

    // MARK: - Address Validation (Maya API)

    private func validateAndContinue(address: String) {
        viewModel.errorMessage = nil

        Task {
            let error = await MayaAPIService.shared.validateAddress(
                destination: address,
                toAsset: coin.mayaAsset
            )

            if let error = error {
                viewModel.errorMessage = error
            } else {
                // Temp success dialog — will be replaced in later stories
                let alert = UIAlertController(
                    title: "SUCCESS",
                    message: "Address validation passed for \(coin.code):\n\(address)",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
                    guard let self else { return }
                    self.onAddressConfirmed?(self.coin, address)
                })
                present(alert, animated: true)
            }
        }
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

    // MARK: - Uphold Login

    private func presentUpholdLogin() {
        let url = DWUpholdClient.sharedInstance().startAuthRoutineByURL()
        let callbackURLScheme = "dashwallet"

        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackURLScheme) { [weak self] callbackURL, error in
            guard let self, let callbackURL else { return }

            guard callbackURL.absoluteString.contains("uphold") else { return }

            DWUpholdClient.sharedInstance().completeAuthRoutine(with: callbackURL) { [weak self] success in
                guard success else { return }
                DispatchQueue.main.async {
                    self?.viewModel.onUpholdLoginCompleted()
                }
            }
        }

        session.presentationContextProvider = self
        session.start()
        self.authSession = session
    }

    // MARK: - Coinbase Login

    private func presentCoinbaseLogin() {
        Task {
            do {
                try await Coinbase.shared.signIn(with: self)
                viewModel.onCoinbaseLoginCompleted()
            } catch {
                DSLogger.log("Maya: Coinbase login failed: \(error)")
            }
        }
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension EnterAddressHostingController: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        view.window ?? ASPresentationAnchor()
    }
}
