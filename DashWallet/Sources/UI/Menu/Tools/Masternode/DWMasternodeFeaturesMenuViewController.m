//
//  Created by Sam Westrich
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

#import "DWMasternodeFeaturesMenuViewController.h"

#import "DWFormTableViewController.h"
#import "DWImportWalletInfoViewController.h"
#import "DWKeysOverviewViewController.h"
#import "DWLocalMasternodeListViewController.h"
#import "DWMasternodeListViewController.h"
#import "DWRegisterMasternodeViewController.h"
#import "DWToolsMenuModel.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWMasternodeFeaturesMenuViewController ()

@property (nonatomic, strong) DWFormTableViewController *formController;

@end

@implementation DWMasternodeFeaturesMenuViewController

- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil {
    if (self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]) {
        self.title = NSLocalizedString(@"Masternode Features", nil);
        self.hidesBottomBarWhenPushed = YES;
    }

    return self;
}

- (NSArray<DWBaseFormCellModel *> *)items {
    __weak typeof(self) weakSelf = self;

    NSMutableArray<DWBaseFormCellModel *> *items = [NSMutableArray array];

    {
        DWSelectorFormCellModel *cellModel = [[DWSelectorFormCellModel alloc] initWithTitle:NSLocalizedString(@"Masternode List", nil)];
        cellModel.accessoryType = DWSelectorFormAccessoryType_DisclosureIndicator;
        cellModel.didSelectBlock = ^(DWSelectorFormCellModel *_Nonnull cellModel, NSIndexPath *_Nonnull indexPath) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            [strongSelf showMasternodeList];
        };
        [items addObject:cellModel];
    }

    {
        DWSelectorFormCellModel *cellModel = [[DWSelectorFormCellModel alloc] initWithTitle:NSLocalizedString(@"My Masternodes", nil)];
        cellModel.accessoryType = DWSelectorFormAccessoryType_DisclosureIndicator;
        cellModel.didSelectBlock = ^(DWSelectorFormCellModel *_Nonnull cellModel, NSIndexPath *_Nonnull indexPath) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            [strongSelf showMasternodeControl];
        };
        [items addObject:cellModel];
    }

    {
        DWSelectorFormCellModel *cellModel = [[DWSelectorFormCellModel alloc] initWithTitle:NSLocalizedString(@"Register Masternode", nil)];
        cellModel.accessoryType = DWSelectorFormAccessoryType_DisclosureIndicator;
        cellModel.didSelectBlock = ^(DWSelectorFormCellModel *_Nonnull cellModel, NSIndexPath *_Nonnull indexPath) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            [strongSelf showRegisterMasternode];
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

#pragma mark - Private

- (void)showMasternodeKeys {
    DWKeysOverviewViewController *keysViewController = [[DWKeysOverviewViewController alloc] init];
    [self.navigationController pushViewController:keysViewController animated:YES];
}

- (void)showRegisterMasternode {
    DWRegisterMasternodeViewController *registerMasternodeViewController = [[DWRegisterMasternodeViewController alloc] init];
    [self.navigationController pushViewController:registerMasternodeViewController animated:YES];
}

- (void)showMasternodeControl {
    DWLocalMasternodeListViewController *masternodeViewController = [[DWLocalMasternodeListViewController alloc] init];
    [self.navigationController pushViewController:masternodeViewController animated:YES];
}

- (void)showMasternodeList {
    DWMasternodeListViewController *masternodeViewController = [[DWMasternodeListViewController alloc] init];
    [self.navigationController pushViewController:masternodeViewController animated:YES];
}

@end

NS_ASSUME_NONNULL_END
