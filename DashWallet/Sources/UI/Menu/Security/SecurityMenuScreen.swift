//
//  Created by Andrei Ashikhmin
//  Copyright © 2025 Dash Core Group. All rights reserved.
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

struct SecurityMenuScreen: View {
    private let vc: UINavigationController
    private let delegateInternal: DelegateInternal
    
    @StateObject private var viewModel = SecurityMenuViewModel()
    @State private var showBiometricsAlert = false
    
    init(vc: UINavigationController) {
        self.vc = vc
        self.delegateInternal = DelegateInternal(onHide: {
            vc.popViewController(animated: true)
        })
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Back button
            HStack {
                Button(action: {
                    vc.popViewController(animated: true)
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 36, height: 36)
                        .overlay(
                            Circle().stroke(Color.gray300.opacity(0.3), lineWidth: 1)
                        )
                }
                Spacer()
            }
            .padding(.horizontal, 5)
            .padding(.top, 10)
            
            // Header
            HStack {
                Text(NSLocalizedString("Security", comment: ""))
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.primaryText)
                Spacer()
            }
            .padding(.top, 30)
            .padding(.bottom, 20)
            
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
        .background(Color.primaryBackground)
        .navigationBarHidden(true)
        .onReceive(viewModel.$navigationDestination) { destination in
            handleNavigation(destination)
        }
        .onReceive(viewModel.$showBiometricsAlert) { show in
            showBiometricsAlert = show
        }
        .alert(NSLocalizedString("Biometrics Access Required", comment: ""), isPresented: $showBiometricsAlert) {
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) { }
            Button(NSLocalizedString("Settings", comment: "")) {
                openAppSettings()
            }
        } message: {
            Text(biometricsAlertMessage)
        }
    }
    
    private func handleNavigation(_ destination: SecurityMenuNavigationDestination?) {
        switch destination {
        case .viewRecoveryPhrase:
            viewModel.authenticate { authenticated in
                if authenticated {
                    let model = DWPreviewSeedPhraseModel()
                    model.getOrCreateNewWallet()
                    let controller = DWPreviewSeedPhraseViewController(model: model)
                    controller.delegate = delegateInternal
                    controller.hidesBottomBarWhenPushed = true
                    self.vc.pushViewController(controller, animated: true)
                }
            }
        case .changePin:
            viewModel.authenticate { authenticated in
                if authenticated {
                    let controller = DWSetPinViewController(intent: .changePin)
                    controller.delegate = delegateInternal
                    controller.hidesBottomBarWhenPushed = true
                    self.vc.pushViewController(controller, animated: true)
                }
            }
        case .advancedSecurity:
            viewModel.authenticate { authenticated in
                if authenticated {
                    #if SNAPSHOT
                    let controller = DWDemoAdvancedSecurityViewController()
                    #else
                    let controller = DWAdvancedSecurityViewController()
                    #endif
                    self.vc.pushViewController(controller, animated: true)
                }
            }
        case .resetWallet:
            let controller = DWResetWalletInfoViewController.make()
            controller.delegate = delegateInternal
            self.vc.pushViewController(controller, animated: true)
        case .none:
            break
        }
        
        // Reset navigation destination after handling
        if destination != nil {
            viewModel.resetNavigation()
        }
    }
    
    private var biometricsAlertMessage: String {
        let displayName = Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ?? ""
        if viewModel.hasTouchID {
            return String(format: NSLocalizedString("%@ is not allowed to access Touch ID. Allow Touch ID access in Settings", comment: ""), displayName)
        } else if viewModel.hasFaceID {
            return String(format: NSLocalizedString("%@ is not allowed to access Face ID. Allow Face ID access in Settings", comment: ""), displayName)
        } else {
            return "Biometrics access required"
        }
    }
    
    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
}

extension SecurityMenuScreen {
    class DelegateInternal: NSObject, DWSecureWalletDelegate, DWSetPinViewControllerDelegate, DWWipeDelegate {
        let onHide: () -> ()
        
        init(onHide: @escaping () -> ()) {
            self.onHide = onHide
        }
        
        func secureWalletRoutineDidVerify(_ controller: UIViewController) { }
        func secureWalletRoutineDidFinish(_ controller: VerifiedSuccessfullyViewController) { }
        func secureWalletRoutineDidCancel(_ controller: UIViewController) { onHide() }
        func setPinViewControllerDidSetPin(_ controller: DWSetPinViewController) { onHide() }
        func setPinViewControllerDidCancel(_ controller: DWSetPinViewController) { onHide() }
        func didWipeWallet() { onHide() }
    }
}
