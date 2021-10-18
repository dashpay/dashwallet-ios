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

#import "DWSecurityMenuViewController.h"

#import <DashSync/DashSync.h>

#import "DWAdvancedSecurityViewController.h"
#import "DWFormTableViewController.h"
#import "DWNavigationController.h"
#import "DWPreviewSeedPhraseModel.h"
#import "DWPreviewSeedPhraseViewController.h"
#import "DWResetWalletInfoViewController.h"
#import "DWSecurityMenuModel.h"
#import "DWSetPinViewController.h"
#import "DWUIKit.h"

#if SNAPSHOT
#import "DWDemoAdvancedSecurityViewController.h"
#endif /* SNAPSHOT */

NS_ASSUME_NONNULL_BEGIN

@interface DWSecurityMenuViewController () <DWSetPinViewControllerDelegate, DWSecureWalletDelegate>

@property (readonly, nonatomic, strong) id<DWBalanceDisplayOptionsProtocol> balanceDisplayOptions;
@property (null_resettable, nonatomic, strong) DWSecurityMenuModel *model;
@property (nonatomic, strong) DWFormTableViewController *formController;

@end

@implementation DWSecurityMenuViewController

- (instancetype)initWithBalanceDisplayOptions:(id<DWBalanceDisplayOptionsProtocol>)balanceDisplayOptions {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _balanceDisplayOptions = balanceDisplayOptions;

        self.title = NSLocalizedString(@"Security", nil);
        self.hidesBottomBarWhenPushed = YES;
    }
    return self;
}

- (DWSecurityMenuModel *)model {
    if (!_model) {
        _model = [[DWSecurityMenuModel alloc] initWithBalanceDisplayOptions:self.balanceDisplayOptions];
    }

    return _model;
}

- (NSArray<DWBaseFormCellModel *> *)items {
    __weak typeof(self) weakSelf = self;

    NSMutableArray<DWBaseFormCellModel *> *items = [NSMutableArray array];

    {
        DWSelectorFormCellModel *cellModel = [[DWSelectorFormCellModel alloc] initWithTitle:NSLocalizedString(@"View Recovery Phrase", nil)];
        cellModel.accessoryType = DWSelectorFormAccessoryType_DisclosureIndicator;
        cellModel.didSelectBlock = ^(DWSelectorFormCellModel *_Nonnull cellModel, NSIndexPath *_Nonnull indexPath) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            [strongSelf showSeedPharseAction];
        };
        [items addObject:cellModel];
    }

    {
        DWSelectorFormCellModel *cellModel = [[DWSelectorFormCellModel alloc] initWithTitle:NSLocalizedString(@"Change PIN", nil)];
        cellModel.accessoryType = DWSelectorFormAccessoryType_DisclosureIndicator;
        cellModel.didSelectBlock = ^(DWSelectorFormCellModel *_Nonnull cellModel, NSIndexPath *_Nonnull indexPath) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            [strongSelf changePinAction];
        };
        [items addObject:cellModel];
    }

    if (self.model.hasTouchID || self.model.hasFaceID) {
        NSString *title = self.model.hasTouchID ? NSLocalizedString(@"Enable Touch ID", nil) : NSLocalizedString(@"Enable Face ID", nil);
        DWSwitcherFormCellModel *cellModel = [[DWSwitcherFormCellModel alloc] initWithTitle:title];
        cellModel.on = self.model.biometricsEnabled;
        cellModel.didChangeValueBlock = ^(DWSwitcherFormCellModel *_Nonnull cellModel) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            [strongSelf biometricSwitchAction:cellModel];
        };
        [items addObject:cellModel];
    }

    {
        DWSwitcherFormCellModel *cellModel = [[DWSwitcherFormCellModel alloc] initWithTitle:NSLocalizedString(@"Autohide Balance", nil)];
        cellModel.on = self.model.balanceHidden;
        cellModel.didChangeValueBlock = ^(DWSwitcherFormCellModel *_Nonnull cellModel) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            strongSelf.model.balanceHidden = cellModel.on;
        };
        [items addObject:cellModel];
    }

    {
        DWSelectorFormCellModel *cellModel = [[DWSelectorFormCellModel alloc] initWithTitle:NSLocalizedString(@"Advanced Security", nil)];
        cellModel.accessoryType = DWSelectorFormAccessoryType_DisclosureIndicator;
        cellModel.didSelectBlock = ^(DWSelectorFormCellModel *_Nonnull cellModel, NSIndexPath *_Nonnull indexPath) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            [strongSelf showAdvancedSecurity];
        };
#if SNAPSHOT
        cellModel.accessibilityIdentifier = @"menu_security_advanced_item";
#endif /* SNAPSHOT */
        [items addObject:cellModel];
    }

    {
        DWSelectorFormCellModel *cellModel = [[DWSelectorFormCellModel alloc] initWithTitle:NSLocalizedString(@"Reset Wallet", nil)];
        cellModel.accessoryType = DWSelectorFormAccessoryType_DisclosureIndicator;
        cellModel.didSelectBlock = ^(DWSelectorFormCellModel *_Nonnull cellModel, NSIndexPath *_Nonnull indexPath) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            [strongSelf resetWalletAction];
        };
        [items addObject:cellModel];
    }

    return [items copy];
}

- (NSArray<DWFormSectionModel *> *)sections {
    NSMutableArray<DWFormSectionModel *> *sections = [NSMutableArray array];

    for (DWBaseFormCellModel *item in [self items]) {
        DWFormSectionModel *section = [[DWFormSectionModel alloc] init];
        section.items = @[ item ];
        [sections addObject:section];
    }

    return [sections copy];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor dw_secondaryBackgroundColor];

    DWFormTableViewController *formController = [[DWFormTableViewController alloc] initWithStyle:UITableViewStylePlain];
    [formController setSections:[self sections] placeholderText:nil];

    [self dw_embedChild:formController];
    self.formController = formController;
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

#pragma mark - DWSetPinViewControllerDelegate

- (void)setPinViewControllerDidSetPin:(DWSetPinViewController *)controller {
    [controller.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (void)setPinViewControllerDidCancel:(DWSetPinViewController *)controller {
    [controller.navigationController dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - DWSecureWalletDelegate

- (void)secureWalletRoutineDidCanceled:(UIViewController *)controller {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)secureWalletRoutineDidVerify:(DWVerifiedSuccessfullyViewController *)controller {
    NSAssert(NO, @"This delegate method shouldn't be called from a preview seed phrase VC");
}

#pragma mark - Private

- (void)showSeedPharseAction {
    DSAuthenticationManager *authenticationManager = [DSAuthenticationManager sharedInstance];
    [authenticationManager
              authenticateWithPrompt:nil
        usingBiometricAuthentication:NO
                      alertIfLockout:YES
                          completion:^(BOOL authenticated, BOOL usedBiometrics, BOOL cancelled) {
                              if (!authenticated) {
                                  return;
                              }

                              DWPreviewSeedPhraseModel *model = [[DWPreviewSeedPhraseModel alloc] init];
                              [model getOrCreateNewWallet];

                              DWPreviewSeedPhraseViewController *controller =
                                  [[DWPreviewSeedPhraseViewController alloc] initWithModel:model];
                              controller.hidesBottomBarWhenPushed = YES;
                              controller.delegate = self;
                              [self.navigationController pushViewController:controller animated:YES];
                          }];
}

- (void)changePinAction {
    [self.model changePinContinueBlock:^(BOOL allowed) {
        if (!allowed) {
            return;
        }

        DWSetPinViewController *controller = [DWSetPinViewController controllerWithIntent:DWSetPinIntent_ChangePin];
        controller.delegate = self;
        DWNavigationController *navigationController = [[DWNavigationController alloc] initWithRootViewController:controller];
        navigationController.modalPresentationStyle = UIModalPresentationFullScreen;
        [self presentViewController:navigationController animated:YES completion:nil];
    }];
}

- (void)showAdvancedSecurity {
#if SNAPSHOT
    DWDemoAdvancedSecurityViewController *controller = [[DWDemoAdvancedSecurityViewController alloc] init];
    [self.navigationController pushViewController:controller animated:YES];
#else
    DSAuthenticationManager *authenticationManager = [DSAuthenticationManager sharedInstance];
    [authenticationManager
              authenticateWithPrompt:nil
        usingBiometricAuthentication:NO
                      alertIfLockout:YES
                          completion:^(BOOL authenticated, BOOL usedBiometrics, BOOL cancelled) {
                              if (!authenticated) {
                                  return;
                              }

                              DWAdvancedSecurityViewController *controller = [[DWAdvancedSecurityViewController alloc] init];
                              [self.navigationController pushViewController:controller animated:YES];
                          }];
#endif /* SNAPSHOT */
}

- (void)biometricSwitchAction:(DWSwitcherFormCellModel *)cellModel {
    __weak typeof(self) weakSelf = self;
    [self.model setBiometricsEnabled:cellModel.on
                          completion:^(BOOL success) {
                              __strong typeof(weakSelf) strongSelf = weakSelf;
                              if (!strongSelf) {
                                  return;
                              }

                              if (!success) {
                                  const BOOL wasEnabled = cellModel.on;
                                  cellModel.on = !cellModel.on;

                                  // Face / Touch ID access was disabled but the user wants to enabled it
                                  if (wasEnabled) {
                                      [strongSelf showBiometricsAccessAlertRequest];
                                  }
                              }

                              [strongSelf.formController setSections:[strongSelf sections]
                                                     placeholderText:nil];
                          }];
}

- (void)resetWalletAction {
    DWResetWalletInfoViewController *controller = [DWResetWalletInfoViewController controller];
    controller.delegate = self.delegate;
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)showBiometricsAccessAlertRequest {
    NSString *displayName = [NSBundle mainBundle].infoDictionary[@"CFBundleDisplayName"];
    NSString *titleString = nil;
    NSString *messageString = nil;
    if (self.model.hasTouchID) {
        titleString = [NSString stringWithFormat:NSLocalizedString(@"%@ is not allowed to access Touch ID", nil),
                                                 displayName];
        messageString = NSLocalizedString(@"Allow Touch ID access in Settings", nil);
    }
    else if (self.model.hasFaceID) {
        titleString = [NSString stringWithFormat:NSLocalizedString(@"%@ is not allowed to access Face ID", nil),
                                                 displayName];
        messageString = NSLocalizedString(@"Allow Face ID access in Settings", nil);
    }
    else {
        NSAssert(NO, @"Inconsistent state");
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:titleString
                                                                   message:messageString
                                                            preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"Cancel", nil)
                  style:UIAlertActionStyleCancel
                handler:nil];
    [alert addAction:okAction];

    UIAlertAction *settingsAction = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"Settings", nil)
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *_Nonnull action) {
                    NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
                    if (url && [[UIApplication sharedApplication] canOpenURL:url]) {
                        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
                    }
                }];
    [alert addAction:settingsAction];

    alert.preferredAction = settingsAction;

    [self presentViewController:alert animated:YES completion:nil];
}

@end

NS_ASSUME_NONNULL_END
