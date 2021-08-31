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

#import "DWSettingsMenuViewController.h"

#import <DashSync/DashSync.h>

#import "DWAboutViewController.h"
#import "DWEnvironment.h"
#import "DWFormTableViewController.h"
#import "DWLocalCurrencyViewController.h"
#import "DWSettingsMenuModel.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWSettingsMenuViewController () <DWLocalCurrencyViewControllerDelegate>

@property (null_resettable, nonatomic, strong) DWSettingsMenuModel *model;
@property (nonatomic, strong) DWFormTableViewController *formController;
@property (strong, nonatomic) DWSelectorFormCellModel *localCurrencyCellModel;
@property (strong, nonatomic) DWSelectorFormCellModel *switchNetworkCellModel;
@property (strong, nonatomic) DWSelectorFormCellModel *switchAccountCellModel;

@end

@implementation DWSettingsMenuViewController

- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        self.title = NSLocalizedString(@"Settings", nil);
        self.hidesBottomBarWhenPushed = YES;
    }
    return self;
}

- (DWSettingsMenuModel *)model {
    if (!_model) {
        _model = [[DWSettingsMenuModel alloc] init];
    }

    return _model;
}

- (NSArray<DWBaseFormCellModel *> *)items {
    __weak typeof(self) weakSelf = self;

    NSMutableArray<DWBaseFormCellModel *> *items = [NSMutableArray array];

    {
        DWSelectorFormCellModel *cellModel = [[DWSelectorFormCellModel alloc] initWithTitle:NSLocalizedString(@"Local Currency", nil)];
        self.localCurrencyCellModel = cellModel;
        [self updateLocalCurrencyCellModel];
        cellModel.accessoryType = DWSelectorFormAccessoryType_DisclosureIndicator;
        cellModel.didSelectBlock = ^(DWSelectorFormCellModel *_Nonnull cellModel, NSIndexPath *_Nonnull indexPath) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            [strongSelf showCurrencySelector];
        };
        [items addObject:cellModel];
    }

    {
        DWSwitcherFormCellModel *cellModel = [[DWSwitcherFormCellModel alloc] initWithTitle:NSLocalizedString(@"Enable Receive Notifications", nil)];
        cellModel.on = self.model.notificationsEnabled;
        cellModel.didChangeValueBlock = ^(DWSwitcherFormCellModel *_Nonnull cellModel) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            strongSelf.model.notificationsEnabled = cellModel.on;
        };
        [items addObject:cellModel];
    }

    {
        DWSelectorFormCellModel *cellModel = [[DWSelectorFormCellModel alloc] initWithTitle:NSLocalizedString(@"Account Index", nil)];
        self.switchAccountCellModel = cellModel;
        [self updateSwitchAccountCellModel];
        cellModel.accessoryType = DWSelectorFormAccessoryType_DisclosureIndicator;
        cellModel.didSelectBlock = ^(DWSelectorFormCellModel *_Nonnull cellModel, NSIndexPath *_Nonnull indexPath) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            UITableView *tableView = self.formController.tableView;
            UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
            [strongSelf showChangeAccountFromSourceView:tableView sourceRect:cell.frame];
        };
        [items addObject:cellModel];
    }

    {
        DWSelectorFormCellModel *cellModel = [[DWSelectorFormCellModel alloc] initWithTitle:NSLocalizedString(@"Network", nil)];
        self.switchNetworkCellModel = cellModel;
        [self updateSwitchNetworkCellModel];
        cellModel.accessoryType = DWSelectorFormAccessoryType_DisclosureIndicator;
        cellModel.didSelectBlock = ^(DWSelectorFormCellModel *_Nonnull cellModel, NSIndexPath *_Nonnull indexPath) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            UITableView *tableView = self.formController.tableView;
            UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
            [strongSelf showChangeNetworkFromSourceView:tableView sourceRect:cell.frame];
        };
        [items addObject:cellModel];
    }

    {
        DWSelectorFormCellModel *cellModel = [[DWSelectorFormCellModel alloc] initWithTitle:NSLocalizedString(@"Rescan Blockchain", nil)];
        cellModel.didSelectBlock = ^(DWSelectorFormCellModel *_Nonnull cellModel, NSIndexPath *_Nonnull indexPath) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            UITableView *tableView = self.formController.tableView;
            UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
            [strongSelf rescanBlockchainActionFromSourceView:tableView sourceRect:cell.frame];
        };
        [items addObject:cellModel];
    }

    {
        DWSelectorFormCellModel *cellModel = [[DWSelectorFormCellModel alloc] initWithTitle:NSLocalizedString(@"About", nil)];
        cellModel.accessoryType = DWSelectorFormAccessoryType_DisclosureIndicator;
        cellModel.didSelectBlock = ^(DWSelectorFormCellModel *_Nonnull cellModel, NSIndexPath *_Nonnull indexPath) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            [strongSelf showAboutController];
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

#pragma mark - DWLocalCurrencyViewControllerDelegate

- (void)localCurrencyViewControllerDidSelectCurrency:(DWLocalCurrencyViewController *)controller {
    [self updateLocalCurrencyCellModel];
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - Private

- (void)updateLocalCurrencyCellModel {
    self.localCurrencyCellModel.subTitle = self.model.localCurrencyCode;
}

- (void)updateSwitchNetworkCellModel {
    self.switchNetworkCellModel.subTitle = self.model.networkName;
}

- (void)updateSwitchAccountCellModel {
    self.switchAccountCellModel.subTitle = [NSString stringWithFormat:@"%ld", self.model.accountIndex];
}

- (void)rescanBlockchainActionFromSourceView:(UIView *)sourceView sourceRect:(CGRect)sourceRect {
    [DWSettingsMenuModel rescanBlockchainActionFromController:self
                                                   sourceView:sourceView
                                                   sourceRect:sourceRect
                                                   completion:^(BOOL confirmed) {
                                                       if (confirmed) {
                                                           [self.delegate settingsMenuViewControllerDidRescanBlockchain:self];
                                                       }
                                                   }];
}

- (void)showCurrencySelector {
    DWLocalCurrencyViewController *controller = [[DWLocalCurrencyViewController alloc] init];
    controller.delegate = self;
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)showAboutController {
    DWAboutViewController *aboutViewController = [DWAboutViewController controller];
    [self.navigationController pushViewController:aboutViewController animated:YES];
}

- (void)showChangeAccountFromSourceView:(UIView *)sourceView sourceRect:(CGRect)sourceRect {
    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    uint32_t lastAccount = wallet.lastAccountNumber;

    UIAlertController *actionSheet = [UIAlertController
        alertControllerWithTitle:NSLocalizedString(@"Select Account", nil)
                         message:nil
                  preferredStyle:UIAlertControllerStyleActionSheet];

    for (uint32_t i = 0; i <= lastAccount; i++) {
        NSString *title = [NSString stringWithFormat:NSLocalizedString(@"Account # %u", nil), i];
        UIAlertAction *selectAccount = [UIAlertAction
            actionWithTitle:title
                      style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction *_Nonnull action) {
                        self.model.accountIndex = i;
                        [self updateSwitchAccountCellModel];
                    }];
        [actionSheet addAction:selectAccount];
    }

    UIAlertAction *addAccount = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"Add New Account", nil)
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *action) {
                    [self addNewAccount];
                }];
    [addAccount setValue:[UIColor dw_greenColor]
                  forKey:[@"title" stringByAppendingString:@"TextColor"]];
    [actionSheet addAction:addAccount];

    UIAlertAction *cancel = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"Cancel", nil)
                  style:UIAlertActionStyleCancel
                handler:nil];
    [actionSheet addAction:cancel];

    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        actionSheet.popoverPresentationController.sourceView = sourceView;
        actionSheet.popoverPresentationController.sourceRect = sourceRect;
    }
    [self presentViewController:actionSheet animated:YES completion:nil];
}

- (void)showChangeNetworkFromSourceView:(UIView *)sourceView sourceRect:(CGRect)sourceRect {
    UIAlertController *actionSheet = [UIAlertController
        alertControllerWithTitle:NSLocalizedString(@"Network", nil)
                         message:nil
                  preferredStyle:UIAlertControllerStyleActionSheet];
    UIAlertAction *mainnet = [UIAlertAction
        actionWithTitle:DSLocalizedString(@"Mainnet", nil)
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *action) {
                    [DWSettingsMenuModel switchToMainnetWithCompletion:^(BOOL success) {
                        if (success) {
                            self.model.accountIndex = 0;
                            [self updateSwitchNetworkCellModel];
                        }
                    }];
                }];
    UIAlertAction *testnet = [UIAlertAction
        actionWithTitle:DSLocalizedString(@"Testnet", nil)
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *action) {
                    [DWSettingsMenuModel switchToTestnetWithCompletion:^(BOOL success) {
                        if (success) {
                            self.model.accountIndex = 0;
                            [self updateSwitchNetworkCellModel];
                        }
                    }];
                }];

    //    UIAlertAction *evonet = [UIAlertAction
    //        actionWithTitle:DSLocalizedString(@"Evonet", nil)
    //                  style:UIAlertActionStyleDefault
    //                handler:^(UIAlertAction *action) {
    //                    [DWSettingsMenuModel switchToEvonetWithCompletion:^(BOOL success) {
    //                        if (success) {
    //                            [self updateSwitchNetworkCellModel];
    //                        }
    //                    }];
    //                }];

    UIAlertAction *cancel = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"Cancel", nil)
                  style:UIAlertActionStyleCancel
                handler:nil];
    [actionSheet addAction:mainnet];
    [actionSheet addAction:testnet];
    //    [actionSheet addAction:evonet];
    [actionSheet addAction:cancel];
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        actionSheet.popoverPresentationController.sourceView = sourceView;
        actionSheet.popoverPresentationController.sourceRect = sourceRect;
    }
    [self presentViewController:actionSheet animated:YES completion:nil];
}

- (void)addNewAccount {
    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSChain *chain = wallet.chain;
    uint32_t addAccountNumber = wallet.lastAccountNumber + 1;
    NSArray *derivationPaths = [wallet.chain standardDerivationPathsForAccountNumber:addAccountNumber];
    DSAccount *addAccount = [DSAccount accountWithAccountNumber:addAccountNumber
                                            withDerivationPaths:derivationPaths
                                                      inContext:wallet.chain.chainManagedObjectContext];
    [wallet seedPhraseAfterAuthenticationWithPrompt:NSLocalizedString(@"Confirm adding new account", nil)
                                         completion:^(NSString *_Nullable seedPhrase) {
                                             if (seedPhrase == nil) {
                                                 return;
                                             }

                                             NSData *derivedKeyData = [[DSBIP39Mnemonic sharedInstance] deriveKeyFromPhrase:seedPhrase withPassphrase:nil];
                                             for (DSDerivationPath *derivationPath in addAccount.fundDerivationPaths) {
                                                 [derivationPath generateExtendedPublicKeyFromSeed:derivedKeyData
                                                                          storeUnderWalletUniqueId:wallet.uniqueIDString];
                                             }
                                             if ([chain isEvolutionEnabled]) {
                                                 [addAccount.masterContactsDerivationPath generateExtendedPublicKeyFromSeed:derivedKeyData
                                                                                                   storeUnderWalletUniqueId:wallet.uniqueIDString];
                                             }

                                             [wallet addAccount:addAccount];
                                             [addAccount loadDerivationPaths];

                                             self.model.accountIndex = addAccountNumber;
                                             [self updateSwitchAccountCellModel];
                                         }];
}

@end

NS_ASSUME_NONNULL_END
