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

#import "DWSettingsMenuModel.h"

#import "DWEnvironment.h"
#import "DWGlobalOptions.h"

NS_ASSUME_NONNULL_BEGIN

@implementation DWSettingsMenuModel

- (NSString *)networkName {
    return [DWEnvironment sharedInstance].currentChain.name;
}

- (NSString *)localCurrencyCode {
    return [DSPriceManager sharedInstance].localCurrencyCode;
}

- (NSInteger)accountIndex {
    return [DWGlobalOptions sharedInstance].currentAccountIndex;
}

- (void)setAccountIndex:(NSInteger)accountIndex {
    BOOL hasChanged = [DWGlobalOptions sharedInstance].currentAccountIndex != accountIndex;
    [DWGlobalOptions sharedInstance].currentAccountIndex = accountIndex;
    if (hasChanged) {
        [[NSNotificationCenter defaultCenter] postNotificationName:DWCurrentNetworkDidChangeNotification
                                                            object:nil];
    }
}

- (BOOL)notificationsEnabled {
    return [DWGlobalOptions sharedInstance].localNotificationsEnabled;
}

- (void)setNotificationsEnabled:(BOOL)notificationsEnabled {
    [DWGlobalOptions sharedInstance].localNotificationsEnabled = notificationsEnabled;
}

+ (void)switchToMainnetWithCompletion:(void (^)(BOOL success))completion {
    [[DWEnvironment sharedInstance] switchToMainnetWithCompletion:completion];
}

+ (void)switchToTestnetWithCompletion:(void (^)(BOOL success))completion {
    [[DWEnvironment sharedInstance] switchToTestnetWithCompletion:completion];
}

+ (void)switchToEvonetWithCompletion:(void (^)(BOOL success))completion {
    [[DWEnvironment sharedInstance] switchToEvonetWithCompletion:completion];
}

+ (void)rescanBlockchainActionFromController:(UIViewController *)controller
                                  sourceView:(UIView *)sourceView
                                  sourceRect:(CGRect)sourceRect
                                  completion:(void (^_Nullable)(BOOL confirmed))completion {
    UIAlertController *actionSheet = [UIAlertController
        alertControllerWithTitle:NSLocalizedString(@"Rescan Blockchain", nil)
                         message:nil
                  preferredStyle:UIAlertControllerStyleActionSheet];
    UIAlertAction *rescanAction = [UIAlertAction
        actionWithTitle:DSLocalizedString(@"Rescan Transactions (Suggested)", nil)
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *action) {
                    [DWGlobalOptions sharedInstance].resyncingWallet = YES;

                    DSChainManager *chainManager = [DWEnvironment sharedInstance].currentChainManager;
                    [chainManager syncBlocksRescan];

                    if (completion) {
                        completion(YES);
                    }
                }];

    UIAlertAction *rescanMNLAndBlocksAction = [UIAlertAction
        actionWithTitle:DSLocalizedString(@"Full Resync", nil)
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *action) {
                    [DWGlobalOptions sharedInstance].resyncingWallet = YES;

                    DSChainManager *chainManager = [DWEnvironment sharedInstance].currentChainManager;
                    [chainManager masternodeListAndBlocksRescan];

                    if (completion) {
                        completion(YES);
                    }
                }];

#if DEBUG

    UIAlertAction *rescanMNLAction = [UIAlertAction
        actionWithTitle:DSLocalizedString(@"Resync Masternode List", nil)
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *action) {
                    [DWGlobalOptions sharedInstance].resyncingWallet = YES;

                    DSChainManager *chainManager = [DWEnvironment sharedInstance].currentChainManager;
                    [chainManager masternodeListRescan];

                    if (completion) {
                        completion(YES);
                    }
                }];

#endif

    UIAlertAction *cancelAction = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"Cancel", nil)
                  style:UIAlertActionStyleCancel
                handler:^(UIAlertAction *_Nonnull action) {
                    if (completion) {
                        completion(NO);
                    }
                }];
    [actionSheet addAction:rescanAction];
    [actionSheet addAction:rescanMNLAndBlocksAction];

#if DEBUG

    [actionSheet addAction:rescanMNLAction];

#endif
    [actionSheet addAction:cancelAction];
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        actionSheet.popoverPresentationController.sourceView = sourceView;
        actionSheet.popoverPresentationController.sourceRect = sourceRect;
    }
    [controller presentViewController:actionSheet animated:YES completion:nil];
}

@end

NS_ASSUME_NONNULL_END
