//
//  Created by Andrew Podkovyrin
//  Copyright © 2021 Dash Core Group. All rights reserved.
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

#import "DWSendInviteFlowController.h"

#import "DPAlertViewController+DWInvite.h"
#import "DWConfirmInvitationViewController.h"
#import "DWFullScreenModalControllerViewController.h"
#import "DWNavigationController.h"
#import "DWSendInviteFirstStepViewController.h"
#import "DWSuccessInvitationViewController.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWSendInviteFlowController () <
    DWSendInviteFirstStepViewControllerDelegate,
    DWConfirmInvitationViewControllerDelegate,
    DWFullScreenModalControllerViewControllerDelegate,
    DWSuccessInvitationViewControllerDelegate>

@end

NS_ASSUME_NONNULL_END

@implementation DWSendInviteFlowController

- (void)viewDidLoad {
    [super viewDidLoad];

    DWSendInviteFirstStepViewController *controller = [[DWSendInviteFirstStepViewController alloc] init];
    controller.delegate = self;
    controller.navigationItem.leftBarButtonItem = [self cancelBarButton];
    DWNavigationController *navigation = [[DWNavigationController alloc] initWithRootViewController:controller];
    [self dw_embedChild:navigation];
}

- (UIBarButtonItem *)cancelBarButton {
    return [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancelButtonAction)];
}

- (void)cancelButtonAction {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)showSuccessInvitation:(DSBlockchainInvitation *)invitation fullLink:(NSString *)fullLink {
    DWSuccessInvitationViewController *invitationController =
        [[DWSuccessInvitationViewController alloc] initWithInvitation:invitation
                                                             fullLink:fullLink];
    invitationController.delegate = self;
    DWFullScreenModalControllerViewController *modal =
        [[DWFullScreenModalControllerViewController alloc] initWithController:invitationController];
    modal.delegate = self;
    modal.title = NSLocalizedString(@"Invitation", nil);
    modal.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:modal animated:YES completion:nil];
}

#pragma mark - DWSendInviteFirstStepViewControllerDelegate

- (void)sendInviteFirstStepViewControllerNewInviteAction:(DWSendInviteFirstStepViewController *)controller {
    DWConfirmInvitationViewController *confirmationController = [[DWConfirmInvitationViewController alloc] init];
    confirmationController.delegate = self;
    [self presentViewController:confirmationController animated:YES completion:nil];
}

#pragma mark - DWConfirmInvitationViewControllerDelegate

- (void)confirmInvitationViewController:(DWConfirmInvitationViewController *)controller
               didConfirmWithInvitation:(DSBlockchainInvitation *)invitation
                                   link:(NSString *)link {
    [controller dismissViewControllerAnimated:YES
                                   completion:^{
                                       [self showSuccessInvitation:invitation fullLink:link];
                                   }];
}

#pragma mark - DWFullScreenModalControllerViewControllerDelegate

- (void)fullScreenModalControllerViewControllerDidCancel:(DWFullScreenModalControllerViewController *)controller {
    [controller dismissViewControllerAnimated:YES
                                   completion:^{
                                       [self dismissViewControllerAnimated:YES
                                                                completion:^{
                                                                    // TOOD: show history?
                                                                }];
                                   }];
}

#pragma mark - DWSuccessInvitationViewControllerDelegate

- (void)successInvitationViewControllerDidSelectLater:(DWSuccessInvitationViewController *)controller {
    [controller dismissViewControllerAnimated:YES
                                   completion:^{
                                       [self dismissViewControllerAnimated:YES
                                                                completion:^{
                                                                    // TOOD: show history?
                                                                }];
                                   }];
}

@end
