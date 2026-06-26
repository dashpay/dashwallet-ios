//
//  SelectCoinHostingController.swift
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

class SelectCoinHostingController: UIViewController, NavigationBarDisplayable {
    var isNavigationBarHidden: Bool { true }
    var onCoinSelected: ((MayaCryptoCurrency) -> Void)?

    private let swapProvider: SwapProvider
    private let direction: SwapDirection

    init(swapProvider: SwapProvider = MayaSwapProvider(), direction: SwapDirection = .sell) {
        self.swapProvider = swapProvider
        self.direction = direction
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor.dw_secondaryBackground()

        let selectCoinView = SelectCoinView(
            swapProvider: swapProvider,
            direction: direction,
            onBack: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            },
            onCoinSelected: { [weak self] coin in
                self?.onCoinSelected?(coin)
            }
        )

        let hostingController = UIHostingController(rootView: selectCoinView)
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
}
