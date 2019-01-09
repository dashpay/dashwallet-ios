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

#import "DWSettingsViewController.h"

#import "DSCurrencyPriceObject.h"
#import "DWAboutViewController.h"
#import "DWFormTableViewController.h"
#import "DWLocalCurrecnySelectorViewController.h"
#import "DWSeedViewController.h"
#import "DWSelectorViewController.h"
#import "DWSettingsControllerModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWSettingsViewController ()

@property (strong, nonatomic) DWSettingsControllerModel *model;
@property (strong, nonatomic) DWSelectorFormCellModel *localCurrencyCellModel;
@property (strong, nonatomic) DWSelectorFormCellModel *biometricAuthCellModel;
@property (strong, nonatomic) DWSelectorFormCellModel *switchNetworkCellModel;

@property (strong, nonatomic) DWFormTableViewController *formController;

@end

@implementation DWSettingsViewController

+ (instancetype)controller {
    return [[self alloc] init];
}

- (DWSettingsControllerModel *)model {
    if (!_model) {
        _model = [[DWSettingsControllerModel alloc] init];
    }
    return _model;
}

- (NSArray<DWBaseFormCellModel *> *)generalItems {
    __weak typeof(self) weakSelf = self;

    NSMutableArray<DWBaseFormCellModel *> *items = [NSMutableArray array];

    {
        DWSelectorFormCellModel *cellModel = [[DWSelectorFormCellModel alloc] initWithTitle:NSLocalizedString(@"About", nil)];
        cellModel.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cellModel.didSelectBlock = ^(DWSelectorFormCellModel *_Nonnull cellModel, NSIndexPath *_Nonnull indexPath) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            [strongSelf showAboutController];
        };
        [items addObject:cellModel];
    }

    {
        DWSelectorFormCellModel *cellModel = [[DWSelectorFormCellModel alloc] initWithTitle:NSLocalizedString(@"Recovery phrase", nil)];
        cellModel.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cellModel.didSelectBlock = ^(DWSelectorFormCellModel *_Nonnull cellModel, NSIndexPath *_Nonnull indexPath) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            [strongSelf showRecoveryPhraseController];
        };
        [items addObject:cellModel];
    }

    {
        DWSelectorFormCellModel *cellModel = [[DWSelectorFormCellModel alloc] initWithTitle:NSLocalizedString(@"Local currency", nil)];
        self.localCurrencyCellModel = cellModel;
        [self updateLocalCurrencyCellModel];
        cellModel.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cellModel.didSelectBlock = ^(DWSelectorFormCellModel *_Nonnull cellModel, NSIndexPath *_Nonnull indexPath) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            [strongSelf setLocalCurrency];
        };
        [items addObject:cellModel];
    }

    if (self.model.hasTouchID || self.model.hasFaceID) {
        NSString *title = self.model.hasTouchID ? NSLocalizedString(@"Touch ID limit", nil) : NSLocalizedString(@"Face ID limit", nil);
        DWSelectorFormCellModel *cellModel = [[DWSelectorFormCellModel alloc] initWithTitle:title];
        self.biometricAuthCellModel = cellModel;
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

    {
        DWSwitcherFormCellModel *cellModel = [[DWSwitcherFormCellModel alloc] initWithTitle:NSLocalizedString(@"Enable receive notifications", nil)];
        cellModel.on = self.model.enableNotifications;
        cellModel.didChangeValueBlock = ^(DWSwitcherFormCellModel *_Nonnull cellModel) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            strongSelf.model.enableNotifications = cellModel.on;
        };
        [items addObject:cellModel];
    }

    return items;
}

- (NSArray<DWBaseFormCellModel *> *)criticalItems {
    __weak typeof(self) weakSelf = self;

    NSMutableArray<DWBaseFormCellModel *> *items = [NSMutableArray array];

    {
        DWSelectorFormCellModel *cellModel = [[DWSelectorFormCellModel alloc] initWithTitle:NSLocalizedString(@"Change passcode", nil)];
        cellModel.style = DWSelectorFormCellModelStyleBlue;
        cellModel.didSelectBlock = ^(DWSelectorFormCellModel *_Nonnull cellModel, NSIndexPath *_Nonnull indexPath) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            [strongSelf changePasscodeAction];
        };
        [items addObject:cellModel];
    }

    {
        DWSelectorFormCellModel *cellModel = [[DWSelectorFormCellModel alloc] initWithTitle:NSLocalizedString(@"Start / Recover another wallet", nil)];
        cellModel.style = DWSelectorFormCellModelStyleRed;
        cellModel.didSelectBlock = ^(DWSelectorFormCellModel *_Nonnull cellModel, NSIndexPath *_Nonnull indexPath) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            [strongSelf showStartRecoverWalletController];
        };
        [items addObject:cellModel];
    }

    {
        DWSelectorFormCellModel *cellModel = [[DWSelectorFormCellModel alloc] initWithTitle:NSLocalizedString(@"Rescan blockchain", nil)];
        cellModel.style = DWSelectorFormCellModelStyleBlue;
        cellModel.didSelectBlock = ^(DWSelectorFormCellModel *_Nonnull cellModel, NSIndexPath *_Nonnull indexPath) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            [strongSelf rescanBlockchainAction];
        };
        [items addObject:cellModel];
    }

    return items;
}

- (NSArray<DWBaseFormCellModel *> *)advancedItems {
    __weak typeof(self) weakSelf = self;

    NSMutableArray<DWBaseFormCellModel *> *items = [NSMutableArray array];

    DWSelectorFormCellModel *cellModel = [[DWSelectorFormCellModel alloc] initWithTitle:nil];
    self.switchNetworkCellModel = cellModel;
    [self updateSwitchNetworkCellModel];
    cellModel.didSelectBlock = ^(DWSelectorFormCellModel *_Nonnull cellModel, NSIndexPath *_Nonnull indexPath) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        if (strongSelf.model.advancedFeaturesEnabled) {
            UITableView *tableView = self.formController.tableView;
            UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
            [strongSelf showChangeNetworkFromSourceView:tableView sourceRect:cell.frame];
        }
        else {
            [strongSelf showEnableAdvancedFeatures];
        }
    };
    [items addObject:cellModel];

    return items;
}

- (NSArray<DWFormSectionModel *> *)sections {
    NSMutableArray<DWFormSectionModel *> *sections = [NSMutableArray array];

    {
        DWFormSectionModel *section = [[DWFormSectionModel alloc] init];
        section.headerTitle = NSLocalizedString(@"GENERAL", nil);
        section.items = [self generalItems];
        [sections addObject:section];
    }

    {
        DWFormSectionModel *section = [[DWFormSectionModel alloc] init];
        section.headerTitle = NSLocalizedString(@"CRITICAL", nil);
        section.items = [self criticalItems];
        [sections addObject:section];
    }

    {
        DWFormSectionModel *section = [[DWFormSectionModel alloc] init];
        section.headerTitle = NSLocalizedString(@"ADVANCED", nil);
        section.items = [self advancedItems];
        [sections addObject:section];
    }

    return sections;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.navigationItem.title = NSLocalizedString(@"Settings", nil);
    self.navigationItem.backBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@""
                                                                             style:UIBarButtonItemStylePlain
                                                                            target:nil
                                                                            action:nil];

    DWFormTableViewController *formController = [[DWFormTableViewController alloc] initWithStyle:UITableViewStyleGrouped];
    [formController setSections:[self sections] placeholderText:nil];

    [self addChildViewController:formController];
    formController.view.frame = self.view.bounds;
    formController.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:formController.view];
    [formController didMoveToParentViewController:self];
    self.formController = formController;
}

#pragma mark - Actions

- (void)showAboutController {
    [DSEventManager saveEvent:@"settings:show_about"];
    DWAboutViewController *aboutViewController = [DWAboutViewController controller];
    [self.navigationController pushViewController:aboutViewController animated:YES];
}

- (void)showRecoveryPhraseController {
    [DSEventManager saveEvent:@"settings:show_recovery_phrase"];

    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;

    NSCharacterSet *newlinesCharacterSet = [NSCharacterSet newlineCharacterSet];
    NSString *message = [NSString stringWithFormat:@"\n%@\n\n%@\n\n%@\n",
                                                   [NSLocalizedString(@"DO NOT let anyone see your recovery phrase or they can spend your dash.", nil)
                                                       stringByTrimmingCharactersInSet:newlinesCharacterSet],
                                                   [NSLocalizedString(@"NEVER type your recovery phrase into password managers or elsewhere. Other devices may be infected.", nil)
                                                       stringByTrimmingCharactersInSet:newlinesCharacterSet],
                                                   [NSLocalizedString(@"DO NOT take a screenshot. Screenshots are visible to other apps and devices.", nil)
                                                       stringByTrimmingCharactersInSet:newlinesCharacterSet]];

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:NSLocalizedString(@"WARNING", nil)
                         message:message
                  preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *cancelButton = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"cancel", nil)
                  style:UIAlertActionStyleCancel
                handler:nil];
    UIAlertAction *showButton = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"show", nil)
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *action) {
                    [wallet seedPhraseAfterAuthentication:^(NSString *_Nullable seedPhrase) {
                        if (seedPhrase.length > 0) {
                            UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
                            DWSeedViewController *seedController = [storyboard instantiateViewControllerWithIdentifier:@"SeedViewController"];
                            seedController.seedPhrase = seedPhrase;
                            [self.navigationController pushViewController:seedController animated:YES];
                        }
                    }];
                }];
    [alert addAction:showButton];
    [alert addAction:cancelButton];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)setBiometricAuthSpendingLimit {
    [DSEventManager saveEvent:@"settings:touch_id_limit"];
    __weak typeof(self) weakSelf = self;
    [self.model requestBiometricAuthSpendingLimitOptions:^(BOOL authenticated, NSArray<NSString *> *_Nullable options, NSUInteger selectedIndex) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        if (!authenticated) {
            return;
        }

        DWSelectorViewController *controller = [DWSelectorViewController controller];
        controller.title = strongSelf.model.hasTouchID ? NSLocalizedString(@"Touch ID spending limit", nil) : NSLocalizedString(@"Face ID spending limit", nil);
        [controller setItems:options selectedIndex:selectedIndex placeholderText:nil];
        controller.didSelectItemBlock = ^(NSString *_Nonnull item, NSUInteger index) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            [strongSelf.model setBiometricAuthSpendingLimitForOptionIndex:index];
            [strongSelf updateBiometricAuthCellModel];
        };
        [strongSelf.navigationController pushViewController:controller animated:YES];
    }];
}

- (void)setLocalCurrency {
    [DSEventManager saveEvent:@"settings:show_currency_selector"];
    __weak typeof(self) weakSelf = self;
    [self.model requestLocalCurrencyOptions:^(NSArray<NSString *> *_Nullable options, NSUInteger selectedIndex) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        DWLocalCurrecnySelectorViewController *controller = [DWLocalCurrecnySelectorViewController controller];
        [controller setItems:options
               selectedIndex:selectedIndex
             placeholderText:NSLocalizedString(@"no exchange rate data", nil)];
        controller.didSelectItemBlock = ^(NSString *_Nonnull item, NSUInteger index) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            [strongSelf.model setLocalCurrencyForOptionIndex:index];
            [strongSelf updateLocalCurrencyCellModel];
        };
        [strongSelf.navigationController pushViewController:controller animated:YES];
    }];
}

- (void)changePasscodeAction {
    [DSEventManager saveEvent:@"settings:change_pin"];
    [self.model changePasscode];
}

- (void)showStartRecoverWalletController {
    [DSEventManager saveEvent:@"settings:recover"];

    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
    UIViewController *controller = [storyboard instantiateViewControllerWithIdentifier:@"StartRecoverWalletNavigationController"];
    [self presentViewController:controller animated:YES completion:nil];
}

- (void)rescanBlockchainAction {
    [DSEventManager saveEvent:@"settings:rescan"];
    [self.model rescanBlockchain];

    [DSEventManager saveEvent:@"settings:dismiss"];
    [self.navigationController.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

- (void)showEnableAdvancedFeatures {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:NSLocalizedString(@"Enable advanced features?", nil)
                         message:NSLocalizedString(@"Only enable advanced features if you are knowledgeable in blockchain technology. \nIf enabled only use advanced features that you understand.", nil)
                  preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *cancelButton = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"cancel", nil)
                  style:UIAlertActionStyleCancel
                handler:nil];
    UIAlertAction *yesButton = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"yes", nil)
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *action) {
                    [self.model enableAdvancedFeatures];
                    [self updateSwitchNetworkCellModel];
                }];
    [alert addAction:yesButton];
    [alert addAction:cancelButton];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showChangeNetworkFromSourceView:(UIView *)sourceView sourceRect:(CGRect)sourceRect {
    [DSEventManager saveEvent:@"settings:show_change_network"];
    UIAlertController *actionSheet = [UIAlertController
        alertControllerWithTitle:NSLocalizedString(@"Network", nil)
                         message:nil
                  preferredStyle:UIAlertControllerStyleActionSheet];
    UIAlertAction *mainnet = [UIAlertAction
        actionWithTitle:DSLocalizedString(@"Mainnet", nil)
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *action) {
                    [self.model switchToMainnetWithCompletion:^(BOOL success) {
                        if (success) {
                            [self updateSwitchNetworkCellModel];
                        }
                    }];
                }];
    UIAlertAction *testnet = [UIAlertAction
        actionWithTitle:DSLocalizedString(@"Testnet", nil)
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *action) {
                    [self.model switchToTestnetWithCompletion:^(BOOL success) {
                        if (success) {
                            [self updateSwitchNetworkCellModel];
                        }
                    }];
                }];

    UIAlertAction *cancel = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"cancel", nil)
                  style:UIAlertActionStyleCancel
                handler:nil];
    [actionSheet addAction:mainnet];
    [actionSheet addAction:testnet];
    [actionSheet addAction:cancel];
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        actionSheet.popoverPresentationController.sourceView = sourceView;
        actionSheet.popoverPresentationController.sourceRect = sourceRect;
    }
    [self presentViewController:actionSheet animated:YES completion:nil];
}

#pragma mark - Private

- (void)updateLocalCurrencyCellModel {
    self.localCurrencyCellModel.subTitle = self.model.localCurrencyCode;
}

- (void)updateBiometricAuthCellModel {
    self.biometricAuthCellModel.subTitle = self.model.biometricAuthSpendingLimit;
}

- (void)updateSwitchNetworkCellModel {
    NSString *title = nil;
    NSString *subTitle = nil;
    if (self.model.advancedFeaturesEnabled) {
        title = NSLocalizedString(@"Network", nil);
        subTitle = self.model.networkName;
    }
    else {
        title = NSLocalizedString(@"Enable advanced features", nil);
    }
    self.switchNetworkCellModel.title = title;
    self.switchNetworkCellModel.subTitle = subTitle;
}

@end

NS_ASSUME_NONNULL_END
