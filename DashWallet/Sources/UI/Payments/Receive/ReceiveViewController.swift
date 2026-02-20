//
//  Created by PT
//  Copyright © 2023 Dash Core Group. All rights reserved.
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

import Foundation
import SwiftUI


// MARK: - ReceiveViewControllerDelegate

@objc(DWReceiveViewControllerDelegate)
protocol ReceiveViewControllerDelegate: AnyObject {
    func importPrivateKeyButtonAction(_ controller: ReceiveViewController)
}

// MARK: - ReceiveViewController

@objc(DWReceiveViewController)
class ReceiveViewController: BaseViewController {
    var model: DWReceiveModelProtocol!

    @objc
    weak var delegate: ReceiveViewControllerDelegate?

    @objc
    var allowedToImportPrivateKey = true

    @objc
    init(model: DWReceiveModelProtocol) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    @objc
    func importPrivateKeyButtonAction() {
        let sheetView = ImportPrivateKeySheet { [weak self] in
            // When scan button is tapped, trigger the delegate method
            self?.delegate?.importPrivateKeyButtonAction(self!)
        }

        let hostingController = UIHostingController(rootView: sheetView)

        if #available(iOS 16.4, *) {
            hostingController.sheetPresentationController?.detents = [.custom(resolver: { context in
                return 460
            })]
            hostingController.sheetPresentationController?.preferredCornerRadius = 32
        } else if #available(iOS 16.0, *) {
            hostingController.sheetPresentationController?.detents = [.custom(resolver: { context in
                return 460
            })]
        } else if #available(iOS 15.0, *) {
            hostingController.sheetPresentationController?.detents = [.medium()]
        }

        present(hostingController, animated: true)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configureHierarchy()
    }
}

extension ReceiveViewController {
    private func configureHierarchy() {
        let mainStackView = UIStackView()
        mainStackView.translatesAutoresizingMaskIntoConstraints = false
        mainStackView.axis = .vertical
        mainStackView.spacing = stackSpacing
        view.addSubview(mainStackView)

        let receiveContentView = ReceiveContentView.view(with: model)
        receiveContentView.specifyAmountHandler = { [weak self] in
            guard let self else { return }

            let vc = SpecifyAmountViewController.controller()
            vc.delegate = self
            self.navigationController?.pushViewController(vc, animated: true)
        }
        receiveContentView.shareHandler = { [weak self] sender in
            guard let self else { return }
            self.dw_shareReceiveInfo(self.model, sender: sender)
        }

        receiveContentView.backgroundColor = .dw_background()
        receiveContentView.layer.cornerRadius = radius
        mainStackView.addArrangedSubview(receiveContentView)

        // Import Private Key menu item (SwiftUI)
        let importMenuItem = UIHostingController(rootView:
            VStack(spacing: 0) {
                MenuItem(
                    title: NSLocalizedString("Import Private Key", comment: "Import Private Key"),
                    subtitle: nil as String?,
                    details: nil,
                    topText: nil,
                    icon: .custom("image.import.private.key", maxHeight: 22),
                    secondaryIcon: nil,
                    showInfo: false,
                    showChevron: false,
                    badgeText: nil,
                    dashAmount: nil,
                    overrideFiatAmount: nil,
                    showToggle: false,
                    isToggled: false,
                    action: { [weak self] in
                        self?.importPrivateKeyButtonAction()
                    }
                )
                .frame(minHeight: 60)
            }
            .padding(.vertical, 5)
            .background(Color(uiColor: .dw_background()))
            .cornerRadius(CGFloat(radius))
        )
        importMenuItem.view.translatesAutoresizingMaskIntoConstraints = false
        importMenuItem.view.backgroundColor = UIColor.clear
        importMenuItem.view.isHidden = !allowedToImportPrivateKey

        addChild(importMenuItem)
        mainStackView.addArrangedSubview(importMenuItem.view)
        importMenuItem.didMove(toParent: self)

        mainStackView.addArrangedSubview(EmptyUIView())

        NSLayoutConstraint.activate([
            mainStackView.topAnchor.constraint(equalTo: view.topAnchor),
            mainStackView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            mainStackView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            mainStackView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor)
        ])
    }
}

// MARK: SpecifyAmountViewControllerDelegate

extension ReceiveViewController: SpecifyAmountViewControllerDelegate {
    func specifyAmountViewController(_ vc: SpecifyAmountViewController, didInput amount: UInt64) {
        let model = DWReceiveModel(amount: amount)

        let requestController = DWRequestAmountViewController(model: model)
        requestController.delegate = self
        present(requestController, animated: true)
    }
}

// MARK: DWRequestAmountViewControllerDelegate

extension ReceiveViewController: DWRequestAmountViewControllerDelegate {
    func requestAmountViewController(_ controller: DWRequestAmountViewController, didReceiveAmountWithInfo info: String) {
        controller.dismiss(animated: true) {
            self.navigationController?.popViewController(animated: true)

            let popAnimationDuration = 300
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + .milliseconds(popAnimationDuration)) {
                self.navigationController?.view.dw_showInfoHUD(withText: info)
            }
        }
    }
}

