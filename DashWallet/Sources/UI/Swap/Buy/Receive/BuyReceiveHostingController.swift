//
//  BuyReceiveHostingController.swift
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

final class BuyReceiveHostingController: UIViewController, NavigationBarDisplayable {
    var isNavigationBarHidden: Bool { true }

    private let viewModel: BuyReceiveViewModel

    init(coin: SwapCryptoCurrency, refundAddress: String, sellAmount: String, swapProvider: SwapProvider) {
        self.viewModel = BuyReceiveViewModel(
            coin: coin,
            refundAddress: refundAddress,
            sellAmount: sellAmount,
            swapProvider: swapProvider
        )
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.dw_secondaryBackground()

        let swiftUIView = BuyReceiveView(
            viewModel: viewModel,
            onBack: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            },
            onBackHome: { [weak self] in
                guard let self else { return }
                if self.navigationController?.presentingViewController != nil {
                    self.navigationController?.dismiss(animated: true)
                } else {
                    let tab = self.tabBarController
                        ?? self.view.window?.rootViewController?.dw_firstTabBarController()
                    self.navigationController?.popToRootViewController(animated: false)
                    tab?.selectedIndex = 0
                }
            },
            onCopy: { [weak self] text in
                guard let self else { return }
                UIPasteboard.general.string = text
                self.showToast(text: NSLocalizedString("Copied", comment: "Dash DEX"), icon: .system("checkmark.circle.fill"), duration: 1.5)
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
    }
}

private extension UIViewController {
    func dw_firstTabBarController() -> UITabBarController? {
        if let tab = self as? UITabBarController { return tab }
        for child in children {
            if let tab = child.dw_firstTabBarController() { return tab }
        }
        if let presented = presentedViewController {
            return presented.dw_firstTabBarController()
        }
        return nil
    }
}
