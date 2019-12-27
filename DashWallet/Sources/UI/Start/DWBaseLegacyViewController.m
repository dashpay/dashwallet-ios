//
//  Created by Andrew Podkovyrin
//  Copyright © 2018 Dash Core Group. All rights reserved.
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

#import "DWBaseLegacyViewController.h"

#import "DWEnvironment.h"
#import "DWGlobalOptions.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWBaseLegacyViewController ()

@property (nullable, nonatomic, strong) id protectedObserver;

@end

@implementation DWBaseLegacyViewController

- (void)dealloc {
    if (self.protectedObserver) {
        [[NSNotificationCenter defaultCenter] removeObserver:self.protectedObserver];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    if ([UIApplication sharedApplication].protectedDataAvailable) {
        [self performSelector:@selector(protectedViewDidAppear) withObject:nil afterDelay:0.0];
    }
    else if (!self.protectedObserver) {
        self.protectedObserver = [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationProtectedDataDidBecomeAvailable
                                                                                   object:nil
                                                                                    queue:nil
                                                                               usingBlock:^(NSNotification *note) {
                                                                                   [self performSelector:@selector(protectedViewDidAppear) withObject:nil afterDelay:0.0];
                                                                               }];
    }
}

- (void)protectedViewDidAppear {
    if (self.protectedObserver) {
        [[NSNotificationCenter defaultCenter] removeObserver:self.protectedObserver];
    }
    self.protectedObserver = nil;
}

- (void)wipeAlert {
    UIAlertController *wipeAlert = [UIAlertController
        alertControllerWithTitle:NSLocalizedString(@"Are you sure?", nil)
                         message:NSLocalizedString(@"By wiping this device you will no longer have access to funds on this device. This should only be done if you no longer have access to your passphrase and have also forgotten your PIN code.", nil)
                  preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *cancelButton = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"Cancel", nil)
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *action) {
                    [self protectedViewDidAppear];
                }];
    UIAlertAction *wipeButton = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"Wipe", nil)
                  style:UIAlertActionStyleDestructive
                handler:^(UIAlertAction *action) {
                    [[DSVersionManager sharedInstance] clearKeychainWalletOldData];
                    [[DWEnvironment sharedInstance] clearAllWallets];
                    [[DWGlobalOptions sharedInstance] restoreToDefaults];

                    [self showNewWalletController];
                }];
    [wipeAlert addAction:cancelButton];
    [wipeAlert addAction:wipeButton];
    [self presentViewController:wipeAlert animated:YES completion:nil];
}

- (void)forceUpdateWalletAuthentication:(BOOL)cancelled {
    UIAlertController *alert;
    if (cancelled) {
        alert = [UIAlertController
            alertControllerWithTitle:NSLocalizedString(@"Failed wallet update", nil)
                             message:NSLocalizedString(@"You must enter your PIN in order to enter dashwallet", nil)
                      preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *exitButton = [UIAlertAction
            actionWithTitle:NSLocalizedString(@"Exit", nil)
                      style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction *action) {
                        [[NSNotificationCenter defaultCenter] postNotificationName:DSApplicationTerminationRequestNotification object:nil];
                    }];
        UIAlertAction *enterButton = [UIAlertAction
            actionWithTitle:NSLocalizedString(@"Enter", nil)
                      style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction *action) {
                        [self protectedViewDidAppear];
                    }];
        [alert addAction:exitButton];
        [alert addAction:enterButton]; //ok button should be on the right side as per Apple guidelines, as reset is the less desireable option
    }
    else {
        __block NSUInteger wait = [[DSAuthenticationManager sharedInstance] lockoutWaitTime];
        NSString *waitTime = (wait == NSUIntegerMax) ? nil : [NSString waitTimeFromNow:wait];
        if ([waitTime isEqualToString:@""])
            waitTime = nil;
        alert = [UIAlertController
            alertControllerWithTitle:NSLocalizedString(@"Failed wallet update", nil)
                             message:waitTime ? [NSString stringWithFormat:NSLocalizedString(@"\ntry again in %@", nil), waitTime] : nil
                      preferredStyle:UIAlertControllerStyleAlert];
        NSTimer *timer = nil;
        if (waitTime) {
            timer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                    repeats:YES
                                                      block:^(NSTimer *_Nonnull timer) {
                                                          wait--;
                                                          alert.message = [NSString stringWithFormat:NSLocalizedString(@"\ntry again in %@", nil), [NSString waitTimeFromNow:wait]];
                                                          if (!wait) {
                                                              [timer invalidate];
                                                              [alert dismissViewControllerAnimated:YES
                                                                                        completion:^{
                                                                                            [self protectedViewDidAppear];
                                                                                        }];
                                                          }
                                                      }];
        }
        UIAlertAction *resetButton = [UIAlertAction
            actionWithTitle:NSLocalizedString(@"Reset", nil)
                      style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction *action) {
                        if (timer) {
                            [timer invalidate];
                        }

                        [[DSAuthenticationManager sharedInstance]
                            resetAllWalletsWithWipeHandler:^{
                                [self wipeAlert];
                            }
                            completion:^(BOOL success) {
                                [self protectedViewDidAppear];
                            }];
                    }];
        if (waitTime) {
            UIAlertAction *exitButton = [UIAlertAction
                actionWithTitle:NSLocalizedString(@"Exit", nil)
                          style:UIAlertActionStyleDefault
                        handler:^(UIAlertAction *action) {
                            [[NSNotificationCenter defaultCenter] postNotificationName:DSApplicationTerminationRequestNotification object:nil];
                        }];
            [alert addAction:resetButton];
            [alert addAction:exitButton]; //ok button should be on the right side as per Apple guidelines, as reset is the less desireable option
        }
        else {
            UIAlertAction *wipeButton = [UIAlertAction
                actionWithTitle:NSLocalizedString(@"Wipe", nil)
                          style:UIAlertActionStyleDestructive
                        handler:^(UIAlertAction *action) {
                            [self wipeAlert];
                        }];
            [alert addAction:wipeButton];
            [alert addAction:resetButton];
        }
    }
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showNewWalletController {
    // meant to be overridden
}

@end

NS_ASSUME_NONNULL_END
