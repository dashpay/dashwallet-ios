//
//  Created by Andrei Ashikhmin
//  Copyright © 2022 Dash Core Group. All rights reserved.
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

import Combine

// MARK: - GettingStartedViewController

final class GettingStartedViewController: UIViewController {
    private let viewModel = CrowdNodeModel.shared
    private var cancellableBag = Set<AnyCancellable>()

    @IBOutlet var logoWrapper: UIView!
    @IBOutlet var newAccountButton: UIControl!
    @IBOutlet var newAccountTitle: UILabel!
    @IBOutlet var newAccountIcon: UIImageView!
    @IBOutlet var balanceHint: UIView!
    @IBOutlet var passphraseHint: UIView!
    @IBOutlet var linkAccountButton: UIControl!
    @IBOutlet var minimumBalanceLable: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        configureHierarchy()
        configureObservers()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        cancellableBag.removeAll()
    }

    @IBAction func newAccountAction() {
        if viewModel.canSignUp {
            navigationController?.pushViewController(NewAccountViewController.controller(online: false), animated: true)
        }
    }

    @IBAction func linkAccountAction() {
        navigationController?.pushViewController(NewAccountViewController.controller(online: true), animated: true)
    }

    @IBAction func backupPassphraseAction() {
        let alert =
            UIAlertController(title: NSLocalizedString("Backup your passphrase to create a CrowdNode account", comment: ""),
                              message: NSLocalizedString("If you lose your passphrase for this wallet and lose this device or uninstall Dash Wallet, you will lose access to your funds on CrowdNode and the funds within this wallet.",
                                                         comment: ""),
                              preferredStyle: UIAlertController.Style.alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Backup Passphrase", comment: ""),
                                      style: UIAlertAction.Style.default, handler: { [weak self] _ in
                                          self?.backupPassphrase()
                                      }))
        alert
            .addAction(UIAlertAction(title: NSLocalizedString("Close", comment: ""), style: UIAlertAction.Style.cancel,
                                     handler: nil))
        navigationController?.present(alert, animated: true, completion: nil)
    }

    @IBAction func buyDashAction() {
        let minimumDash = DSPriceManager.sharedInstance().string(forDashAmount: Int64(CrowdNode.minimumRequiredDash))!
        let alert = UIAlertController(title: NSLocalizedString("You have insufficient funds to proceed", comment: ""),
                                      message: String.localizedStringWithFormat(NSLocalizedString("You should have at least %@ to proceed with the CrowdNode verification.",
                                                                                                  comment: ""), minimumDash),
                                      preferredStyle: UIAlertController.Style.alert)
        alert
            .addAction(UIAlertAction(title: NSLocalizedString("Buy Dash", comment: ""), style: UIAlertAction.Style.default,
                                     handler: { [weak self] _ in
                                         self?.buyDash()
                                     }))
        alert
            .addAction(UIAlertAction(title: NSLocalizedString("Close", comment: ""), style: UIAlertAction.Style.cancel,
                                     handler: nil))
        navigationController?.present(alert, animated: true, completion: nil)
    }

    @objc static func controller() -> GettingStartedViewController {
        vc(GettingStartedViewController.self, from: sb("CrowdNode"))
    }
}

extension GettingStartedViewController {
    private func configureHierarchy() {
        view.backgroundColor = UIColor.dw_secondaryBackground()
        
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance
        
        logoWrapper.layer.dw_applyShadow(with: .dw_shadow(), alpha: 0.05, x: 0, y: 0, blur: 10)
        newAccountButton.layer.dw_applyShadow(with: .dw_shadow(), alpha: 0.1, x: 0, y: 0, blur: 10)
        linkAccountButton.layer.dw_applyShadow(with: .dw_shadow(), alpha: 0.1, x: 0, y: 0, blur: 10)

        let minimumDash = DSPriceManager.sharedInstance().string(forDashAmount: Int64(CrowdNode.minimumRequiredDash))!
        minimumBalanceLable.text = String.localizedStringWithFormat(NSLocalizedString("You need at least %@ on your Dash Wallet", comment: "CrowdNode"), minimumDash)

        refreshCreateAccountButton()
    }

    private func configureObservers() {
        viewModel.$hasEnoughWalletBalance
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: { [weak self] _ in
                guard let wSelf = self else { return }
                wSelf.refreshCreateAccountButton()
            })
            .store(in: &cancellableBag)
    }

    private func refreshCreateAccountButton() {
        newAccountTitle.alpha = viewModel.canSignUp ? 1.0 : 0.2
        newAccountIcon.alpha = viewModel.canSignUp ? 1.0 : 0.2

        passphraseHint.isHidden = !viewModel.needsBackup
        let passhraseHintHeight = CGFloat(viewModel.needsBackup ? 45 : 0)
        passphraseHint.heightAnchor.constraint(equalToConstant: passhraseHintHeight).isActive = true

        balanceHint.isHidden = viewModel.hasEnoughWalletBalance
        let balanceHintHeight = CGFloat(viewModel.hasEnoughWalletBalance ? 0 : 45)
        balanceHint.heightAnchor.constraint(equalToConstant: balanceHintHeight).isActive = true
    }
}

// MARK: DWSecureWalletDelegate

extension GettingStartedViewController: DWSecureWalletDelegate {
    private func backupPassphrase() {
        Task {
            if await viewModel.authenticate(allowBiometric: false) {
                backupPassphraseAuthenticated()
            }
        }
    }

    private func backupPassphraseAuthenticated() {
        let model = DWPreviewSeedPhraseModel()
        model.getOrCreateNewWallet()
        let controller = DWBackupInfoViewController(model: model)
        controller.delegate = self
        let navigationController = BaseNavigationController(rootViewController: controller)
        let cancelButton = UIBarButtonItem(barButtonSystemItem: UIBarButtonItem.SystemItem.cancel, target: self,
                                           action: #selector(dismissModalControllerBarButtonAction))
        controller.navigationItem.leftBarButtonItem = cancelButton
        self.navigationController?.present(navigationController, animated: true)
    }

    @objc private func dismissModalControllerBarButtonAction() {
        dismiss(animated: true)
    }

    internal func secureWalletRoutineDidCanceled(_ controller: UIViewController) { }

    internal func secureWalletRoutineDidVerify(_ controller: UIViewController) {
        refreshCreateAccountButton()
    }

    internal func secureWalletRoutineDidFinish(_ controller: VerifiedSuccessfullyViewController) {
        dismissModalControllerBarButtonAction()
    }
}

extension GettingStartedViewController {
    private func buyDash() {
        Task {
            if await viewModel.authenticate() {
                buyDashAuthenticated()
            }
        }
    }

    private func buyDashAuthenticated() {
        let controller = DWUpholdViewController()
        let navigationController = BaseNavigationController(rootViewController: controller)
        self.navigationController?.present(navigationController, animated: true)
    }
}
