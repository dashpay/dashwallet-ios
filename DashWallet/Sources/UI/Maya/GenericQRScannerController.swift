//
//  GenericQRScannerController.swift
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

/// Thin UIKit wrapper around GenericQRScannerView for modal presentation.
/// Preserves the same public API so call sites (EnterAddressHostingController) need no changes.
class GenericQRScannerController: UIViewController {

    var onQRCodeScanned: ((String) -> Void)?
    var onCancel: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()

        let scannerView = GenericQRScannerView(
            onQRCodeScanned: { [weak self] value in
                self?.onQRCodeScanned?(value)
            },
            onCancel: { [weak self] in
                self?.onCancel?()
            }
        )

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

    override var prefersStatusBarHidden: Bool { true }
}
