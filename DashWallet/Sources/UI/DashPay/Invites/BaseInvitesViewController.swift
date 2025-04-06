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

class BaseInvitesViewController: UIViewController {
    var shouldShowMixDashDialog: Bool {
        get { CoinJoinService.shared.mode == .none || !UsernamePrefs.shared.mixDashShown }
        set(value) { UsernamePrefs.shared.mixDashShown = !value }
    }
    
    func runInvitationFlow(completion: ((String, DSInvitation) -> Void)? = nil) {
        if shouldShowMixDashDialog {
            showMixDashDialog() { [weak self] in
                self?.showInvitationFeeDialog() { [weak self] in
                    self?.createInvite(completion: completion)
                }
            }
        } else {
            self.showInvitationFeeDialog() { [weak self] in
                self?.createInvite(completion: completion)
            }
        }
    }
    
    private func showMixDashDialog(onSkip: @escaping () -> Void) {
        let swiftUIView = MixDashDialog(
            purposeText: NSLocalizedString("an invitation", comment: "Invites"),
            positiveAction: {
                let controller = CoinJoinLevelsViewController.controller(isFullScreen: false)
                controller.hidesBottomBarWhenPushed = true
                self.navigationController?.pushViewController(controller, animated: true)
            }, negativeAction: onSkip
        )
        let hostingController = UIHostingController(rootView: swiftUIView)
        hostingController.setDetent(260)
        
        self.present(hostingController, animated: true, completion: nil)
    }
    
    private func showInvitationFeeDialog(onAction: @escaping () -> Void) {
        let swiftUIView = InvitationFeeDialog(action: onAction)
        let hostingController = UIHostingController(rootView: swiftUIView)
        hostingController.setDetent(520)
        self.present(hostingController, animated: true, completion: nil)
    }
    
    private func createInvite(completion: ((String, DSInvitation) -> Void)? = nil) {
        let wallet = DWEnvironment.sharedInstance().currentWallet
        let account = DWEnvironment.sharedInstance().currentAccount
        let invitation = wallet.createInvitation()
        invitation.name = String(format: NSLocalizedString("Invitation %ld", comment: "Invitation #3"), wallet.invitations.count + 1)
        
        let steps = DSIdentityRegistrationStep.l1Steps
        invitation.generateInvitationsExtendedPublicKeys(
            withPrompt: NSLocalizedString("Create invitation", comment: "Invites"),
            completion: { registered in
                invitation.identity.createFundingPrivateKeyForInvitation(
                    withPrompt: NSLocalizedString("Create invitation", comment: "Invites"),
                    completion: { success, cancelled in
                        if success && !cancelled {
                            invitation.identity.register(
                                onNetwork: steps,
                                withFundingAccount: account,
                                forTopupAmount: DWDP_MIN_BALANCE_TO_CREATE_INVITE,
                                pinPrompt: NSLocalizedString("Would you like to create this invitation?", comment: "Invites"),
                                stepCompletion: { stepCompleted in
                                    // Step completion handler
                                },
                                completion: { stepsCompleted, errors in
                                    if let error = errors.last {
                                        self.dw_displayErrorModally(error)
                                    } else {
                                        self.generateLinkForInvitationAndFinish(invitation, completion: completion)
                                    }
                                }
                            )
                        }
                    }
                )
            }
        )
    }
    
    private func generateLinkForInvitationAndFinish(_ invitation: DSInvitation, completion: ((String, DSInvitation) -> Void)? = nil) {
        let wallet = DWEnvironment.sharedInstance().currentWallet
        var identity = wallet.defaultIdentity
        
        if identity == nil && MOCK_DASHPAY.boolValue {
            if let username = DWGlobalOptions.sharedInstance().dashpayUsername {
                identity = DWEnvironment.sharedInstance().currentWallet.createIdentity(forUsername: username)
            }
        }
        
        guard let myIdentity = identity else { return }
        
        //weak var weakSelf = self
        invitation.createInvitationFullLink(
            from: myIdentity,
            completion: { cancelled, invitationFullLink in
                //guard let strongSelf = weakSelf else { return }
                
                // skip?
                if !cancelled && invitationFullLink == nil {
                    return
                }
                
                DispatchQueue.main.async {
                    if !cancelled, let link = invitationFullLink {
                        completion?(link, invitation)
                    }
                }
            }
        )
    }
}
