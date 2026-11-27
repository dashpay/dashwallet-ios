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
    /// Weak: this page sits in `vc`'s own stack.
    private weak var vc: UINavigationController?
    private let delegateInternal: DelegateInternal
    
    @StateObject private var viewModel = SecurityMenuViewModel()
    @StateObject private var recoveryPhraseFlow = RecoveryPhraseFlowViewModel()
    @State private var showBiometricsAlert = false
    @State private var showMultipleWalletsResetAlert = false
    @State private var showNoWalletResetAlert = false
    @State private var showResetWalletInventoryError = false
    @State private var showResetWalletDebugAlert = false
    
    init(vc: UINavigationController?, wipeDelegate: DWWipeDelegate? = nil) {
        self.vc = vc
        // `[weak vc]`: `vc` here is the init parameter, not the weak property.
        self.delegateInternal = DelegateInternal(onHide: { [weak vc] in
            vc?.popViewController(animated: true)
        }, wipeDelegate: wipeDelegate)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DashUIKit.NavigationBar(leading: {
                DashUIKit.NavigationBarElement.back.button {
                    vc?.popViewController(animated: true)
                }
            })

            TopIntro(title: String(localized: "Security", comment: ""))
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
        .onReceive(viewModel.$resetWalletDestination.compactMap { $0 }) { destination in
            handleResetWalletDestination(destination)
        }
        .onReceive(recoveryPhraseFlow.$navigationEvent.compactMap { $0 }) { event in
            handleRecoveryPhraseNavigation(event)
        }
        .alert(String(localized: "Biometrics Access Required", comment: ""), isPresented: $showBiometricsAlert) {
            Button(String(localized: "Cancel", comment: ""), role: .cancel) { }
            Button(String(localized: "Settings", comment: "")) {
                openAppSettings()
            }
        } message: {
            Text(biometricsAlertMessage)
        }
        .alert(
            String(localized: "Multiple Wallets Found", comment: "Security — reset wallet"),
            isPresented: $showMultipleWalletsResetAlert
        ) {
            Button(String(localized: "Cancel", comment: ""), role: .cancel) { }
            Button(String(localized: "Open Wallets", comment: "Security — reset wallet")) {
                openWallets()
            }
        } message: {
            Text(String(
                localized: "Reset Wallet is unavailable while multiple wallets are stored. Open Wallets and remove each wallet individually using its recovery phrase.",
                comment: "Security — reset wallet"))
        }
        .alert(
            String(localized: "No Wallet Found", comment: "Security — reset wallet"),
            isPresented: $showNoWalletResetAlert
        ) {
            Button(String(localized: "OK", comment: ""), role: .cancel) { }
        } message: {
            Text(String(
                localized: "There are no wallets stored on this device to reset.",
                comment: "Security — reset wallet"))
        }
        .alert(
            String(localized: "Could Not Read Wallets", comment: "Security — reset wallet"),
            isPresented: $showResetWalletInventoryError
        ) {
            Button(String(localized: "Cancel", comment: ""), role: .cancel) { }
            Button(String(localized: "Retry", comment: "")) {
                viewModel.beginResetWallet()
            }
        } message: {
            Text(String(
                localized: "The wallets stored on this device could not be verified. Nothing was deleted. Please try again.",
                comment: "Security — reset wallet"))
        }
        .alert("Reset All Wallets (Debug)" as String, isPresented: $showResetWalletDebugAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete All", role: .destructive) {
                delegateInternal.beginDebugWipeWallet()
            }
        } message: {
            Text(verbatim: "Deletes all SDK wallets without asking for their recovery phrases. Legacy DashSync seed fixtures are preserved.")
        }
        .recoveryPhraseFlowAlert(recoveryPhraseFlow)
    }
    
    private func handleNavigation(_ destination: SecurityMenuNavigationDestination?) {
        switch destination {
        case .viewRecoveryPhrase:
            recoveryPhraseFlow.beginGlobal()
        case .changePin:
            viewModel.authenticate { authenticated in
                if authenticated {
                    let controller = SetPinViewController(intent: .changePin)
                    controller.delegate = delegateInternal
                    self.vc?.pushViewController(controller, animated: true)
                }
            }
        case .advancedSecurity:
            viewModel.authenticate { authenticated in
                if authenticated {
                    #if SNAPSHOT
                    let controller = AdvancedSecurityHostingController.demo()
                    #else
                    let controller = AdvancedSecurityHostingController.live()
                    #endif
                    self.vc?.pushViewController(controller, animated: true)
                }
            }
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
            vc?.pushViewController(controller, animated: true)
        case .phrase(let presentation):
            guard let vc else { break }
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
            return String(localized: "\(displayName) is not allowed to access Touch ID. Allow Touch ID access in Settings", comment: "")
        } else if viewModel.hasFaceID {
            return String(localized: "\(displayName) is not allowed to access Face ID. Allow Face ID access in Settings", comment: "")
        } else {
            return String(localized: "Biometrics Access Required", comment: "")
        }
    }
    
    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }

    private func handleResetWalletDestination(_ destination: SecurityMenuResetWalletDestination) {
        switch destination {
        case .reset:
            let controller = ResetWalletInfoHostingController(wipeDelegate: delegateInternal)
            vc?.pushViewController(controller, animated: true)
        case .multipleWallets:
            showMultipleWalletsResetAlert = true
        case .noWallet:
            showNoWalletResetAlert = true
        case .readError:
            showResetWalletInventoryError = true
        }

        viewModel.resetWalletDestinationHandled()
    }

    private func openWallets() {
        let controller = UIHostingController(
            rootView: WalletsScreen(
                vc: vc,
                wipeDelegate: delegateInternal.wipeDelegate))
        vc?.pushViewController(controller, animated: true)
    }
}

extension SecurityMenuScreen {
    class DelegateInternal: NSObject, DWSecureWalletDelegate, SetPinViewControllerDelegate, DWWipeDelegate {
        let onHide: () -> ()
        weak var wipeDelegate: DWWipeDelegate?

        init(onHide: @escaping () -> (), wipeDelegate: DWWipeDelegate? = nil) {
            self.onHide = onHide
            self.wipeDelegate = wipeDelegate
        }

        func secureWalletRoutineDidVerify(_ controller: UIViewController) { }
        func secureWalletRoutineDidFinish(_ controller: VerifiedSuccessfullyViewController) { }
        func secureWalletRoutineDidCancel(_ controller: UIViewController) { onHide() }
        func setPinViewControllerDidSetPin(_ controller: SetPinViewController) { onHide() }
        func setPinViewControllerDidCancel(_ controller: SetPinViewController) { onHide() }

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
