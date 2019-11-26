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

#import "DWFormTableViewController.h"
#import "DWNavigationController.h"
#import "DWPreviewSeedPhraseModel.h"
#import "DWPreviewSeedPhraseViewController.h"
#import "DWResetWalletInfoViewController.h"
#import "DWSecurityMenuModel.h"
#import "DWSelectorViewController.h"
#import "DWSetPinViewController.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWSecurityMenuViewController () <DWSetPinViewControllerDelegate, DWSecureWalletDelegate>

@property (readonly, nonatomic, strong) DWBalanceDisplayOptions *balanceDisplayOptions;
@property (null_resettable, nonatomic, strong) DWSecurityMenuModel *model;
@property (nonatomic, strong) DWFormTableViewController *formController;
@property (nonatomic, strong) DWSelectorFormCellModel *biometricLimitAuthCellModel;

@end

@implementation DWSecurityMenuViewController

- (instancetype)initWithBalanceDisplayOptions:(DWBalanceDisplayOptions *)balanceDisplayOptions {
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

    if (self.model.hasTouchID || self.model.hasFaceID) {

        {
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

        if (self.model.biometricsEnabled) {
            NSString *title = self.model.hasTouchID ? NSLocalizedString(@"Touch ID limit", nil) : NSLocalizedString(@"Face ID limit", nil);
            DWSelectorFormCellModel *cellModel = [[DWSelectorFormCellModel alloc] initWithTitle:title];
            cellModel.accessoryType = DWSelectorFormAccessoryType_DisclosureIndicator;
            self.biometricLimitAuthCellModel = cellModel;
            [self updateBiometricAuthCellModel];
            cellModel.didSelectBlock = ^(DWSelectorFormCellModel *_Nonnull cellModel, NSIndexPath *_Nonnull indexPath) {
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) {
                    return;
                }

                [strongSelf setBiometricAuthSpendingLimit];
            };
            [items addObject:cellModel];
        }
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

    return items;
}

- (NSArray<DWFormSectionModel *> *)sections {
    DWFormSectionModel *section = [[DWFormSectionModel alloc] init];
    section.items = [self items];

    return @[ section ];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor dw_secondaryBackgroundColor];

    DWFormTableViewController *formController = [[DWFormTableViewController alloc] initWithStyle:UITableViewStylePlain];
    [formController setSections:[self sections] placeholderText:nil];

    [self addChildViewController:formController];
    formController.view.frame = self.view.bounds;
    formController.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:formController.view];
    [formController didMoveToParentViewController:self];
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

- (void)updateBiometricAuthCellModel {
    self.biometricLimitAuthCellModel.subTitle = self.model.biometricAuthSpendingLimit;
}

- (void)showSeedPharseAction {
    DSAuthenticationManager *authenticationManager = [DSAuthenticationManager sharedInstance];
    [authenticationManager
        authenticateWithPrompt:nil
                    andTouchId:NO
                alertIfLockout:YES
                    completion:^(BOOL authenticated, BOOL cancelled) {
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

- (void)biometricSwitchAction:(DWSwitcherFormCellModel *)cellModel {
    __weak typeof(self) weakSelf = self;
    [self.model setBiometricsEnabled:cellModel.on
                          completion:^(BOOL success) {
                              __strong typeof(weakSelf) strongSelf = weakSelf;
                              if (!strongSelf) {
                                  return;
                              }

                              if (!success) {
                                  cellModel.on = !cellModel.on;
                              }

                              [strongSelf.formController setSections:[strongSelf sections] placeholderText:nil];
                          }];
}

- (void)setBiometricAuthSpendingLimit {
    __weak typeof(self) weakSelf = self;
    [self.model requestBiometricsSpendingLimitOptions:^(BOOL authenticated, NSArray<id<DWSelectorFormItem>> *_Nullable options, NSUInteger selectedIndex) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        if (!authenticated) {
            return;
        }

        DWSelectorViewController *controller = [DWSelectorViewController controller];
        controller.title = strongSelf.model.hasTouchID ? NSLocalizedString(@"Touch ID limit", nil) : NSLocalizedString(@"Face ID limit", nil);
        [controller setItems:options selectedIndex:selectedIndex placeholderText:nil];
        controller.didSelectItemBlock = ^(id<DWSelectorFormItem> item, NSUInteger index) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            [strongSelf.model setBiometricsSpendingLimitForOption:item];
            [strongSelf updateBiometricAuthCellModel];

            [strongSelf.navigationController popViewControllerAnimated:YES];
        };
        [strongSelf.navigationController pushViewController:controller animated:YES];
    }];
}

- (void)resetWalletAction {
    DWResetWalletInfoViewController *controller = [DWResetWalletInfoViewController controller];
    controller.delegate = self.delegate;
    [self.navigationController pushViewController:controller animated:YES];
}

@end

NS_ASSUME_NONNULL_END
