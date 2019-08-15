//
//  Created by Andrew Podkovyrin
//  Copyright © 2019 Dash Core Group. All rights reserved.
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

#import "DWHomeViewController+DWJailbreakCheck.h"

#import <DashSync/DashSync.h>

#import "DWHomeModel.h"
#import "DWNavigationController.h"
#import "DWRecoverViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWHomeViewController (DWJailbreakCheck_Internal) <DWRecoverViewControllerDelegate>

@end

@implementation DWHomeViewController (DWJailbreakCheck)

- (void)performJailbreakCheck {
    if (!self.model.isJailbroken) {
        return;
    }

    NSString *title = NSLocalizedString(@"WARNING", nil);
    NSString *message = nil;
    UIAlertAction *mainAction = nil;

    if (!self.model.isWalletEmpty) {
        message = NSLocalizedString(@"DEVICE SECURITY COMPROMISED\n"
                                     "Any 'jailbreak' app can access any other app's keychain data "
                                     "(and steal your dash). "
                                     "Wipe this wallet immediately and restore on a secure device.",
                                    nil);
        mainAction = [UIAlertAction
            actionWithTitle:NSLocalizedString(@"Wipe", nil)
                      style:UIAlertActionStyleDestructive
                    handler:^(UIAlertAction *action) {
                        [self wipeWallet];
                    }];
    }
    else {
        message = NSLocalizedString(@"DEVICE SECURITY COMPROMISED\n"
                                     "Any 'jailbreak' app can access any other app's keychain data "
                                     "(and steal your dash).",
                                    nil);
        mainAction = [UIAlertAction
            actionWithTitle:NSLocalizedString(@"Close App", nil)
                      style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction *action) {
                        [[NSNotificationCenter defaultCenter] postNotificationName:DSApplicationTerminationRequestNotification object:nil];
                    }];
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *ignoreAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Ignore", nil)
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];
    [alert addAction:ignoreAction];

    [alert addAction:mainAction];

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)wipeWallet {
    DWRecoverViewController *controller = [[DWRecoverViewController alloc] init];
    controller.action = DWRecoverAction_Wipe;
    controller.delegate = self;
    UIBarButtonItem *cancelButton =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                      target:self
                                                      action:@selector(recoverCancelButtonAction:)];
    controller.navigationItem.leftBarButtonItem = cancelButton;

    DWNavigationController *navigationController =
        [[DWNavigationController alloc] initWithRootViewController:controller];
    [self presentViewController:navigationController animated:YES completion:nil];
}

#pragma mark - DWRecoverViewControllerDelegate

- (void)recoverViewControllerDidRecoverWallet:(DWRecoverViewController *)controller {
    NSAssert(NO, @"Inconsistent state");
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)recoverViewControllerDidWipe:(DWRecoverViewController *)controller {
    [self dismissViewControllerAnimated:YES
                             completion:^{
                                 [self.delegate homeViewControllerDidWipeWallet:self];
                             }];
}

- (void)recoverCancelButtonAction:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

NS_ASSUME_NONNULL_END
