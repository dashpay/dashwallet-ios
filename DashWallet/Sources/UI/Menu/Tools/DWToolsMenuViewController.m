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

#import "DWToolsMenuViewController.h"

#import "DWEnvironment.h"
#import "DWExtendedPublicKeysViewController.h"
#import "DWFormTableViewController.h"
#import "DWImportWalletInfoViewController.h"
#import "DWKeysOverviewViewController.h"
#import "DWToolsMenuModel.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWToolsMenuViewController () <DWImportWalletInfoViewControllerDelegate>

@property (null_resettable, nonatomic, strong) DWToolsMenuModel *model;
@property (nonatomic, strong) DWFormTableViewController *formController;

@end

@implementation DWToolsMenuViewController

- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        self.title = NSLocalizedString(@"Tools", nil);
        self.hidesBottomBarWhenPushed = YES;
    }

    return self;
}

- (DWToolsMenuModel *)model {
    if (!_model) {
        _model = [[DWToolsMenuModel alloc] init];
    }

    return _model;
}

- (NSArray<DWBaseFormCellModel *> *)items {
    __weak typeof(self) weakSelf = self;

    NSMutableArray<DWBaseFormCellModel *> *items = [NSMutableArray array];

    {
        DWSelectorFormCellModel *cellModel = [[DWSelectorFormCellModel alloc] initWithTitle:NSLocalizedString(@"Import Private Key", nil)];
        cellModel.accessoryType = DWSelectorFormAccessoryType_DisclosureIndicator;
        cellModel.didSelectBlock = ^(DWSelectorFormCellModel *_Nonnull cellModel, NSIndexPath *_Nonnull indexPath) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            [strongSelf showImportPrivateKey];
        };
        [items addObject:cellModel];
    }

    {
        DWSelectorFormCellModel *cellModel = [[DWSelectorFormCellModel alloc] initWithTitle:NSLocalizedString(@"Extended Public Keys", nil)];
        cellModel.accessoryType = DWSelectorFormAccessoryType_DisclosureIndicator;
        cellModel.didSelectBlock = ^(DWSelectorFormCellModel *_Nonnull cellModel, NSIndexPath *_Nonnull indexPath) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            [strongSelf showExtendedPublicKeys];
        };
        [items addObject:cellModel];
    }

    {
        DWSelectorFormCellModel *cellModel = [[DWSelectorFormCellModel alloc] initWithTitle:NSLocalizedString(@"Show Masternode Keys", nil)];
        cellModel.accessoryType = DWSelectorFormAccessoryType_DisclosureIndicator;
        cellModel.didSelectBlock = ^(DWSelectorFormCellModel *_Nonnull cellModel, NSIndexPath *_Nonnull indexPath) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            [strongSelf showMasternodeKeys];
        };
        [items addObject:cellModel];
    }

    {
        DWSelectorFormCellModel *cellModel = [[DWSelectorFormCellModel alloc] initWithTitle:NSLocalizedString(@"CSV Export", nil)];
        cellModel.accessoryType = DWSelectorFormAccessoryType_DisclosureIndicator;
        cellModel.didSelectBlock = ^(DWSelectorFormCellModel *_Nonnull cellModel, NSIndexPath *_Nonnull indexPath) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            [strongSelf exportTransactionsInCSV];
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

#pragma mark - DWImportWalletInfoViewControllerDelegate

- (void)importWalletInfoViewControllerScanPrivateKeyAction:(DWImportWalletInfoViewController *)controller {
    [self.delegate toolsMenuViewControllerImportPrivateKey:self];
}

#pragma mark - Private

- (void)showImportPrivateKey {
    DWImportWalletInfoViewController *controller = [DWImportWalletInfoViewController controller];
    controller.delegate = self;
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)showMasternodeKeys {
    DWKeysOverviewViewController *keysViewController = [[DWKeysOverviewViewController alloc] init];
    [self.navigationController pushViewController:keysViewController animated:YES];
}

- (void)showExtendedPublicKeys {
    DWExtendedPublicKeysViewController *controller = [[DWExtendedPublicKeysViewController alloc] init];
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)exportTransactionsInCSV {
    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;

    NSString *sortKey = DW_KEYPATH(DSTransaction.new, timestamp);

    // Timestamps are set to 0 if the transaction hasn't yet been confirmed, they should be at the top of the list if this is the case
    NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:sortKey
                                                                     ascending:NO
                                                                    comparator:^NSComparisonResult(id _Nonnull obj1, id _Nonnull obj2) {
                                                                        if ([obj1 unsignedIntValue] == 0) {
                                                                            if ([obj2 unsignedIntValue] == 0) {
                                                                                return NSOrderedSame;
                                                                            }
                                                                            else {
                                                                                return NSOrderedDescending;
                                                                            }
                                                                        }
                                                                        else if ([obj2 unsignedIntValue] == 0) {
                                                                            return NSOrderedAscending;
                                                                        }
                                                                        else {
                                                                            return [(NSNumber *)obj1 compare:obj2];
                                                                        }
                                                                    }];
    NSArray<DSTransaction *> *transactions = [wallet.allTransactions sortedArrayUsingDescriptors:@[ sortDescriptor ]];

    NSString *headers = @"Date and time,Transaction Type,Sent Quantity,Sent Currency,Sending Source,Received Quantity,Received Currency,Receiving Destination,Fee,Fee Currency,Exchange Transaction ID,Blockchain Transaction Hash";


    NSString *transactionType = @"Income"; // @"Expense"

    for (DSTransaction *tx in transactions) {
        NSString *row = [NSString stringWithFormat:@"%@,%@,%@,%@,%@,%@,%@,%@,%@,%@,%@,%@", @"2021-01-06T00:00:00Z", transactionType, @"", @"DASH", @"DASH Wallet for outgoing transactions / Blank for incoming transactions", @"The amount of Dash received / Blank for outgoing transactions", @"DASH/Blank", @"DASH Wallet/Blank", @"", @"", @"", tx.txHash];
    }
}


@end

NS_ASSUME_NONNULL_END
