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

#import "BigIntTypes.h"
#import "DWEnvironment.h"
#import "DWExtendedPublicKeysViewController.h"
#import "DWFormTableViewController.h"
#import "DWImportWalletInfoViewController.h"
#import "DWKeysOverviewViewController.h"
#import "DWToolsMenuModel.h"
#import "DWUIKit.h"
#import "UIView+DWHUD.h"
#import "UIViewController+DWDisplayError.h"
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

            [strongSelf askToExportTransactionsInCSV];
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

- (void)askToExportTransactionsInCSV {

    NSString *title = NSLocalizedString(@"CSV Export", nil);
    NSString *message = NSLocalizedString(@"All payments will be considered as an Expense and all incoming transactions will be Income. The owner of this wallet is responsible for making any cost basis adjustments in their chosen tax reporting system.", nil);
    __weak typeof(self) weakSelf = self;

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:title
                         message:message
                  preferredStyle:UIAlertControllerStyleActionSheet];
    {
        UIAlertAction *action = [UIAlertAction
            actionWithTitle:NSLocalizedString(@"Continue", nil)
                      style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction *_Nonnull action) {
                        [weakSelf exportTransactionsInCSV];
                    }];
        [alert addAction:action];
    }

    {
        UIAlertAction *action = [UIAlertAction
            actionWithTitle:NSLocalizedString(@"Cancel", nil)
                      style:UIAlertActionStyleCancel
                    handler:nil];
        [alert addAction:action];
    }

    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self.view;
        alert.popoverPresentationController.sourceRect = self.view.bounds;
    }

    [self presentViewController:alert
                       animated:YES
                     completion:nil];
}

- (void)exportTransactionsInCSV {
    [self.view dw_showProgressHUDWithMessage:NSLocalizedString(@"Generating CSV Report", nil)];
    __weak typeof(self) weakSelf = self;

    [self.model
        generateCSVReportWithCompletionHandler:^(NSString *_Nonnull fileName, NSURL *_Nonnull file) {
            [weakSelf.view dw_hideProgressHUD];

            UIActivityViewController *activityViewController = [[UIActivityViewController alloc] initWithActivityItems:@[ fileName, file ] applicationActivities:nil];

            if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
                activityViewController.popoverPresentationController.sourceView = weakSelf.view;
                activityViewController.popoverPresentationController.sourceRect = weakSelf.view.bounds;
            }

            [weakSelf presentViewController:activityViewController animated:YES completion:nil];
        }
        errorHandler:^(NSError *_Nonnull error) {
            [weakSelf.view dw_hideProgressHUD];
            [weakSelf dw_displayErrorModally:error];
        }];
}
@end

NS_ASSUME_NONNULL_END
