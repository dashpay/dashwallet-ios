//
//  Created by Andrew Podkovyrin
//  Copyright © 2020 Dash Core Group. All rights reserved.
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

#import "DWConfirmInvitationViewController.h"

#import "DWConfirmInvitationContentView.h"
#import "DWDashPayConstants.h"
#import "DWEnvironment.h"
#import "UIViewController+DWDisplayError.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWConfirmInvitationViewController ()

@property (nonatomic, strong) DWConfirmInvitationContentView *confirmView;

@end

NS_ASSUME_NONNULL_END

@implementation DWConfirmInvitationViewController

+ (BOOL)isActionButtonInNavigationBar {
    return NO;
}

- (NSString *)actionButtonTitle {
    return NSLocalizedString(@"Confirm", nil);
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setModalTitle:NSLocalizedString(@"Confirm", nil)];

    self.actionButton.enabled = NO;

    self.confirmView = [[DWConfirmInvitationContentView alloc] initWithFrame:CGRectZero];
    [self.confirmView.confirmationCheckbox addTarget:self
                                              action:@selector(confirmationCheckboxAction:)
                                    forControlEvents:UIControlEventValueChanged];

    [self setupModalContentView:self.confirmView];
}

- (void)actionButtonAction:(id)sender {
    self.actionButton.enabled = NO;

    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSAccount *account = [DWEnvironment sharedInstance].currentAccount;
    DSBlockchainInvitation *invitation = [wallet createBlockchainInvitation];

    DSBlockchainIdentityRegistrationStep steps = DSBlockchainIdentityRegistrationStep_L1Steps;
    [invitation generateBlockchainInvitationsExtendedPublicKeysWithPrompt:NSLocalizedString(@"Create invitation", nil)
                                                               completion:^(BOOL registered) {
                                                                   [invitation.identity createFundingPrivateKeyForInvitationWithPrompt:NSLocalizedString(@"Create invitation", nil)
                                                                                                                            completion:^(BOOL success, BOOL cancelled) {
                                                                                                                                if (success && !cancelled) {
                                                                                                                                    [invitation.identity
                                                                                                                                        registerOnNetwork:steps
                                                                                                                                        withFundingAccount:account
                                                                                                                                        forTopupAmount:DWDP_MIN_BALANCE_TO_CREATE_INVITE
                                                                                                                                        stepCompletion:^(DSBlockchainIdentityRegistrationStep stepCompleted) {
                                                                                                                                        }
                                                                                                                                        completion:^(DSBlockchainIdentityRegistrationStep stepsCompleted, NSError *_Nonnull error) {
                                                                                                                                            if (error) {
                                                                                                                                                [self dw_displayErrorModally:error];
                                                                                                                                            }
                                                                                                                                            else {
                                                                                                                                                [self generateLinkForInvitationAndFinish:invitation];
                                                                                                                                            }
                                                                                                                                        }];
                                                                                                                                }
                                                                                                                            }];
                                                               }];
}

- (void)generateLinkForInvitationAndFinish:(DSBlockchainInvitation *)invitation {
    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSBlockchainIdentity *myBlockchainIdentity = wallet.defaultBlockchainIdentity;

    __weak typeof(self) weakSelf = self;
    [invitation
        createInvitationFullLinkFromIdentity:myBlockchainIdentity
                                  completion:^(BOOL cancelled, NSString *_Nonnull invitationFullLink) {
                                      __strong typeof(weakSelf) strongSelf = weakSelf;
                                      if (!strongSelf) {
                                          return;
                                      }

                                      // skip?
                                      if (cancelled == NO && invitationFullLink == nil) {
                                          return;
                                      }

                                      dispatch_async(dispatch_get_main_queue(), ^{
                                          strongSelf.actionButton.enabled = cancelled;

                                          if (!cancelled) {
                                              [strongSelf.delegate confirmInvitationViewController:strongSelf didConfirmWithInvitation:invitation link:invitationFullLink];
                                          }
                                      });
                                  }];
}

- (void)confirmationCheckboxAction:(DWCheckbox *)sender {
    self.actionButton.enabled = sender.isOn;
}

@end
