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
import DashUIKit
import UIKit

struct SecurityMenuScreen: View {
    private let vc: UINavigationController
    private let delegateInternal: DelegateInternal
    
    @StateObject private var viewModel = SecurityMenuViewModel()
    @StateObject private var recoveryPhraseFlow = RecoveryPhraseFlowViewModel()
    @State private var showBiometricsAlert = false
    @State private var showResetWalletDebugAlert = false
    
    init(vc: UINavigationController, wipeDelegate: DWWipeDelegate? = nil) {
        self.vc = vc
        self.delegateInternal = DelegateInternal(onHide: {
            vc.popViewController(animated: true)
        }, wipeDelegate: wipeDelegate)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavBarBack {
                vc.popViewController(animated: true)
            }

            TopIntro(title: NSLocalizedString("Security", comment: ""))
                .padding(.leading, 20)
                .padding(.trailing, 60)
                .padding(.top, 10)
                .padding(.bottom, 20)

            // Menu list
            VStack(spacing: 2) {
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
                    .frame(minHeight: 56)
                }
            }
            .padding(6)
            .background(Color.dash.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color.dash.shadow, radius: 20, x: 0, y: 5)
            .padding(.horizontal, 20)

            Spacer()
        }
        .background(Color.dash.primaryBackground)
        .navigationBarHidden(true)
        .onReceive(viewModel.$navigationDestination) { destination in
            handleNavigation(destination)
        }
        .onReceive(viewModel.$showBiometricsAlert) { show in
            showBiometricsAlert = show
        }
        .onReceive(recoveryPhraseFlow.$navigationEvent.compactMap { $0 }) { event in
            handleRecoveryPhraseNavigation(event)
        }
        .alert(NSLocalizedString("Biometrics Access Required", comment: ""), isPresented: $showBiometricsAlert) {
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) { }
            Button(NSLocalizedString("Settings", comment: "")) {
                openAppSettings()
            }
        } message: {
            Text(biometricsAlertMessage)
        }
        .alert("Reset All Wallets (Debug)", isPresented: $showResetWalletDebugAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete All", role: .destructive) {
                delegateInternal.beginDebugWipeWallet()
            }
        } message: {
            Text("Deletes all SDK wallets without asking for their recovery phrases. Legacy DashSync seed fixtures are preserved.")
        }
        .alert(
            recoveryPhraseFlow.alertState?.title ?? "",
            isPresented: Binding(
                get: { recoveryPhraseFlow.alertState != nil },
                set: { if !$0 { recoveryPhraseFlow.dismissAlert() } })
        ) {
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {
                recoveryPhraseFlow.dismissAlert()
            }
            Button(NSLocalizedString("Retry", comment: "")) {
                recoveryPhraseFlow.retry()
            }
        } message: {
            Text(recoveryPhraseFlow.alertState?.message ?? "")
        }
    }
    
    private func handleNavigation(_ destination: SecurityMenuNavigationDestination?) {
        switch destination {
        case .viewRecoveryPhrase:
            recoveryPhraseFlow.beginGlobal()
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
            vc.pushViewController(controller, animated: true)
        case .resetWalletDebug:
            showResetWalletDebugAlert = true
        case .none:
            break
        }
        
        // Reset navigation destination after handling
        if destination != nil {
            viewModel.resetNavigation()
        }
    }

    private func handleRecoveryPhraseNavigation(_ event: RecoveryPhraseFlowViewModel.NavigationEvent) {
        switch event.destination {
        case .picker(let options):
            let controller = RecoveryPhraseNavigation.pickerController(
                options: options,
                flowModel: recoveryPhraseFlow,
                onCancel: { [weak vc] in
                    vc?.popViewController(animated: true)
                })
            vc.pushViewController(controller, animated: true)
        case .phrase(let presentation):
            RecoveryPhraseNavigation.showPhrase(
                presentation,
                in: vc,
                delegate: delegateInternal)
        }

        DispatchQueue.main.async {
            recoveryPhraseFlow.consumeNavigationEvent(id: event.id)
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
        weak var wipeDelegate: DWWipeDelegate?

        init(onHide: @escaping () -> (), wipeDelegate: DWWipeDelegate? = nil) {
            self.onHide = onHide
            self.wipeDelegate = wipeDelegate
        }

        func secureWalletRoutineDidVerify(_ controller: UIViewController) { }
        func secureWalletRoutineDidFinish(_ controller: VerifiedSuccessfullyViewController) { }
        func secureWalletRoutineDidCancel(_ controller: UIViewController) { onHide() }
        func setPinViewControllerDidSetPin(_ controller: DWSetPinViewController) { onHide() }
        func setPinViewControllerDidCancel(_ controller: DWSetPinViewController) { onHide() }

        /// A wipe invalidates the entire main UI, not just this screen: route
        /// to the app-level DWWipeDelegate chain (MainTabbar → root VC), which
        /// transitions to onboarding and drops the whole main stack. Popping
        /// one screen is only the fallback when no chain was provided.
        func didWipeWallet() {
            if let wipeDelegate {
                wipeDelegate.didWipeWallet()
            } else {
                onHide()
            }
        }

        /// Debug Reset must not expose a live onboarding screen while the SDK
        /// wipe is still queued. The root coordinator presents a blocking wipe
        /// gate first, then starts deletion after its HUD is visible.
        func beginDebugWipeWallet() {
            if let wipeDelegate,
               wipeDelegate.responds(to: #selector(DWWipeDelegate.beginDebugWipeWallet)) {
                wipeDelegate.beginDebugWipeWallet?()
            } else {
                // This screen can be embedded without the app-root delegate in
                // previews. Preserve the local delete-all behavior in that case.
                SwiftDashSDKWalletWiper.wipeWallet(authorization: .debugReset)
                onHide()
            }
        }
    }
}
