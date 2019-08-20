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

#import "DWHomeViewController+DWShortcuts.h"

#import <DashSync/DashSync.h>

#import "DWHomeModel.h"
#import "DWShortcutAction.h"

#import "DWBackupInfoViewController.h"
#import "DWNavigationController.h"
#import "DWPreviewSeedPhraseModel.h"
#import "DWUpholdViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWHomeViewController (DWShortcuts_Internal) <DWSecureWalletDelegate>

@end

@implementation DWHomeViewController (DWShortcuts)

- (void)performActionForShortcut:(DWShortcutAction *)action sender:(UIView *)sender {
    const DWShortcutActionType type = action.type;
    switch (type) {
        case DWShortcutActionType_SecureWallet: {
            [self secureWalletAction];
            break;
        }
        case DWShortcutActionType_ScanToPay: {
            [self debug_wipeWallet];
            break;
        }
        case DWShortcutActionType_PayToAddress: {
            break;
        }
        case DWShortcutActionType_BuySellDash: {
            [self buySellDashAction];
            break;
        }
        case DWShortcutActionType_SyncNow: {
            break;
        }
        case DWShortcutActionType_PayWithNFC: {
            break;
        }
        case DWShortcutActionType_LocalCurrency: {

            break;
        }
        case DWShortcutActionType_ImportPrivateKey: {
            break;
        }
        case DWShortcutActionType_SwitchToTestnet: {
            break;
        }
        case DWShortcutActionType_SwitchToMainnet: {
            break;
        }
        case DWShortcutActionType_ReportAnIssue: {
            break;
        }
        case DWShortcutActionType_AddShortcut: {
            break;
        }
    }
}

#pragma mark - Private

- (void)secureWalletAction {
    [[DSAuthenticationManager sharedInstance]
        authenticateWithPrompt:nil
                    andTouchId:NO
                alertIfLockout:YES
                    completion:^(BOOL authenticated, BOOL cancelled) {
                        if (!authenticated) {
                            return;
                        }

                        [self secureWalletActionAuthenticated];
                    }];
}

- (void)secureWalletActionAuthenticated {
    DWPreviewSeedPhraseModel *model = [[DWPreviewSeedPhraseModel alloc] init];
    [model getOrCreateNewWallet];

    DWBackupInfoViewController *controller =
        [DWBackupInfoViewController controllerWithModel:model];
    controller.delegate = self;
    UIBarButtonItem *cancelButton =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                      target:self
                                                      action:@selector(secureWalletCancelButtonAction:)];
    controller.navigationItem.leftBarButtonItem = cancelButton;

    DWNavigationController *navigationController =
        [[DWNavigationController alloc] initWithRootViewController:controller];
    [self presentViewController:navigationController animated:YES completion:nil];
}

- (void)buySellDashAction {
    [[DSAuthenticationManager sharedInstance]
        authenticateWithPrompt:nil
                    andTouchId:YES
                alertIfLockout:YES
                    completion:^(BOOL authenticated, BOOL cancelled) {
                        if (authenticated) {
                            [self buySellDashActionAuthenticated];
                        }
                    }];
}

- (void)buySellDashActionAuthenticated {
    UIViewController *controller = [DWUpholdViewController controller];
    DWNavigationController *navigationController =
        [[DWNavigationController alloc] initWithRootViewController:controller];
    [self presentViewController:navigationController animated:YES completion:nil];
}

- (void)debug_wipeWallet {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"DEBUG MODE"
                                                                   message:@"YOU ARE ABOUT TO ERASE YOUR WALLET!\n\n☠️☠️☠️\n\nYour seed phrase will be erased forever and wallet quit. Run it again to start from scratch."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *ok = [UIAlertAction
        actionWithTitle:@"OK ☠️"
                  style:UIAlertActionStyleDestructive
                handler:^(UIAlertAction *_Nonnull action) {
                    [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
                    CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication);

                    NSArray *secItemClasses = @[ (__bridge id)kSecClassGenericPassword,
                                                 (__bridge id)kSecClassInternetPassword,
                                                 (__bridge id)kSecClassCertificate,
                                                 (__bridge id)kSecClassKey,
                                                 (__bridge id)kSecClassIdentity ];
                    for (id secItemClass in secItemClasses) {
                        NSDictionary *spec = @{(__bridge id)kSecClass : secItemClass};
                        SecItemDelete((__bridge CFDictionaryRef)spec);
                    }

                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        exit(0);
                    });
                }];
    [alert addAction:ok];

    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"Please, no 😭" style:UIAlertActionStyleCancel handler:nil];
    [alert addAction:cancel];

    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - DWSecureWalletDelegate

- (void)secureWalletRoutineDidCanceled:(DWSecureWalletInfoViewController *)controller {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)secureWalletRoutineDidVerify:(DWVerifiedSuccessfullyViewController *)controller {
    [self.model reloadShortcuts];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)secureWalletCancelButtonAction:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

NS_ASSUME_NONNULL_END
