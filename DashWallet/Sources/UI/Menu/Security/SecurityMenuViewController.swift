//
//  Created by Andrei Ashikhmin
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

import UIKit
import SwiftUI
import Combine

class SecurityMenuViewController: UIViewController {
    @objc weak var delegate: DWWipeDelegate?
    private lazy var viewModel = SecurityMenuViewModel()
    private var cancellables = Set<AnyCancellable>()
    
    @objc init() {
        super.init(nibName: nil, bundle: nil)
        title = NSLocalizedString("Security", comment: "")
        hidesBottomBarWhenPushed = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = UIColor.dw_secondaryBackground()
        
        let content = SecurityMenuContent(viewModel: self.viewModel)
        let swiftUIController = UIHostingController(rootView: content)
        swiftUIController.view.backgroundColor = UIColor.dw_secondaryBackground()
        dw_embedChild(swiftUIController)
        
        setupNavigationObserver()
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    private func setupNavigationObserver() {
        viewModel.$navigationDestination
            .receive(on: DispatchQueue.main)
            .sink { [weak self] destination in
                switch destination {
                case .viewRecoveryPhrase:
                    self?.showSeedPhraseAction()
                case .changePin:
                    self?.changePinAction()
                case .advancedSecurity:
                    self?.showAdvancedSecurity()
                case .resetWallet:
                    self?.resetWalletAction()
                case .none:
                    break
                }
            }
            .store(in: &cancellables)
        
        viewModel.$showBiometricsAlert
            .filter { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.showBiometricsAccessAlertRequest()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Actions
    
    private func showSeedPhraseAction() {
        DSAuthenticationManager.sharedInstance()
            .authenticate(
                withPrompt: nil,
                usingBiometricAuthentication: false,
                alertIfLockout: true
            ) { [weak self] authenticated, usedBiometrics, cancelled in
                guard authenticated else { return }
                
                let model = DWPreviewSeedPhraseModel()
                model.getOrCreateNewWallet()
                
                let controller = DWPreviewSeedPhraseViewController(model: model)
                controller.hidesBottomBarWhenPushed = true
                controller.delegate = self
                self?.navigationController?.pushViewController(controller, animated: true)
            }
    }
    
    private func changePinAction() {
        viewModel.model.changePinContinue { [weak self] allowed in
            guard allowed else { return }
            
            let controller = DWSetPinViewController(intent: .changePin)
            controller.delegate = self
            let navigationController = BaseNavigationController(rootViewController: controller)
            navigationController.modalPresentationStyle = .fullScreen
            self?.present(navigationController, animated: true)
        }
    }
    
    private func showAdvancedSecurity() {
        #if SNAPSHOT
        let controller = DWDemoAdvancedSecurityViewController()
        navigationController?.pushViewController(controller, animated: true)
        #else
        DSAuthenticationManager.sharedInstance()
            .authenticate(
                withPrompt: nil,
                usingBiometricAuthentication: false,
                alertIfLockout: true
            ) { [weak self] authenticated, usedBiometrics, cancelled in
                guard authenticated else { return }
                
                let controller = DWAdvancedSecurityViewController()
                self?.navigationController?.pushViewController(controller, animated: true)
            }
        #endif
    }
    
    private func resetWalletAction() {
        let controller = DWResetWalletInfoViewController.make()
        controller.delegate = delegate
        navigationController?.pushViewController(controller, animated: true)
    }
    
    private func showBiometricsAccessAlertRequest() {
        let displayName = Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ?? ""
        let titleString: String
        let messageString: String
        
        if viewModel.model.hasTouchID {
            titleString = String(format: NSLocalizedString("%@ is not allowed to access Touch ID", comment: ""), displayName)
            messageString = NSLocalizedString("Allow Touch ID access in Settings", comment: "")
        } else if viewModel.model.hasFaceID {
            titleString = String(format: NSLocalizedString("%@ is not allowed to access Face ID", comment: ""), displayName)
            messageString = NSLocalizedString("Allow Face ID access in Settings", comment: "")
        } else {
            assertionFailure("Inconsistent state")
            return
        }
        
        let alert = UIAlertController(title: titleString, message: messageString, preferredStyle: .alert)
        
        let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel)
        alert.addAction(cancelAction)
        
        let settingsAction = UIAlertAction(title: NSLocalizedString("Settings", comment: ""), style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString),
               UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            }
        }
        alert.addAction(settingsAction)
        alert.preferredAction = settingsAction
        
        present(alert, animated: true)
    }
}

// MARK: - DWSetPinViewControllerDelegate

extension SecurityMenuViewController: DWSetPinViewControllerDelegate {
    func setPinViewControllerDidSetPin(_ controller: DWSetPinViewController) {
        controller.navigationController?.dismiss(animated: true)
    }
    
    func setPinViewControllerDidCancel(_ controller: DWSetPinViewController) {
        controller.navigationController?.dismiss(animated: true)
    }
}

// MARK: - DWSecureWalletDelegate

extension SecurityMenuViewController: DWSecureWalletDelegate {
    func secureWalletRoutineDidFinish(_ controller: VerifiedSuccessfullyViewController) {
        assertionFailure("This delegate method shouldn't be called from a preview seed phrase VC")
    }
    
    func secureWalletRoutineDidCancel(_ controller: UIViewController) {
        navigationController?.popViewController(animated: true)
    }
    
    func secureWalletRoutineDidVerify(_ controller: UIViewController) {
        // Verification handled
    }
}

// MARK: - SecurityMenuContent

struct SecurityMenuContent: View {
    @StateObject var viewModel: SecurityMenuViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                ForEach(viewModel.items) { item in
                    MenuItem(
                        title: item.title,
                        subtitle: item.subtitle,
                        details: item.details,
                        icon: item.icon,
                        showInfo: item.showInfo,
                        showChevron: false,
                        showToggle: item.showToggle,
                        isToggled: item.isToggled,
                        action: item.action
                    )
                    .frame(minHeight: 60)
                }
            }
            .padding(.vertical, 5)
            .background(Color.secondaryBackground)
            .cornerRadius(12)
            .shadow(color: Color.shadow, radius: 20, x: 0, y: 5)
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }
}
