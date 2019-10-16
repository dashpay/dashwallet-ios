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

#import "DWKeysOverviewViewController.h"

#import "DWDerivationPathKeysViewController.h"
#import "DWFormTableViewController.h"
#import "DWUIKit.h"
#import "DWWalletKeysOverviewModel.h"
#import <DashSync/DSAuthenticationKeysDerivationPath.h>
#import <DashSync/DSDerivationPathFactory.h>
#import <DashSync/DashSync.h>

NS_ASSUME_NONNULL_BEGIN

@interface DWKeysOverviewViewController ()

@property (null_resettable, nonatomic, strong) DWWalletKeysOverviewModel *model;
@property (nonatomic, strong) DWFormTableViewController *formController;

@end

@implementation DWKeysOverviewViewController


- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil {
    if (self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]) {
        self.title = NSLocalizedString(@"Wallet Keys", nil);
        self.hidesBottomBarWhenPushed = YES;
    }

    return self;
}

- (DWWalletKeysOverviewModel *)model {
    if (_model == nil) {
        _model = [[DWWalletKeysOverviewModel alloc] init];
    }

    return _model;
}


- (NSArray<DWBaseFormCellModel *> *)items {
    __weak typeof(self) weakSelf = self;

    NSMutableArray<DWBaseFormCellModel *> *items = [NSMutableArray array];

    {
        DWSelectorFormCellModel *cellModel = [[DWSelectorFormCellModel alloc] initWithTitle:NSLocalizedString(@"Owner Keys", nil)];
        cellModel.accessoryType = DWSelectorFormAccessoryType_DisclosureIndicator;
        cellModel.didSelectBlock = ^(DWSelectorFormCellModel *_Nonnull cellModel, NSIndexPath *_Nonnull indexPath) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            [strongSelf showOwnerKeys];
        };
        [items addObject:cellModel];
    }

    {
        DWSelectorFormCellModel *cellModel = [[DWSelectorFormCellModel alloc] initWithTitle:NSLocalizedString(@"Voting Keys", nil)];
        cellModel.subTitle = [NSString stringWithFormat:NSLocalizedString(@"%ld used", nil),
                                                        self.model.votingDerivationPath.usedAddresses.count];
        cellModel.accessoryType = DWSelectorFormAccessoryType_DisclosureIndicator;
        cellModel.didSelectBlock = ^(DWSelectorFormCellModel *_Nonnull cellModel, NSIndexPath *_Nonnull indexPath) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            [strongSelf showVotingKeys];
        };
        [items addObject:cellModel];
    }

    {
        DWSelectorFormCellModel *cellModel = [[DWSelectorFormCellModel alloc] initWithTitle:NSLocalizedString(@"Operator Keys", nil)];
        cellModel.subTitle = [NSString stringWithFormat:NSLocalizedString(@"%ld used", nil),
                                                        self.model.operatorDerivationPath.usedAddresses.count];
        cellModel.accessoryType = DWSelectorFormAccessoryType_DisclosureIndicator;
        cellModel.didSelectBlock = ^(DWSelectorFormCellModel *_Nonnull cellModel, NSIndexPath *_Nonnull indexPath) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            [strongSelf showOperatorKeys];
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

- (void)showOwnerKeys {
    [self showDerivationPathKeysViewControllerWithDerivationPath:self.model.ownerDerivationPath
                                                           title:NSLocalizedString(@"Owner Keys", nil)];
}

- (void)showVotingKeys {
    [self showDerivationPathKeysViewControllerWithDerivationPath:self.model.votingDerivationPath
                                                           title:NSLocalizedString(@"Voting Keys", nil)];
}

- (void)showOperatorKeys {
    [self showDerivationPathKeysViewControllerWithDerivationPath:self.model.operatorDerivationPath
                                                           title:NSLocalizedString(@"Operator Keys", nil)];
}

- (void)showDerivationPathKeysViewControllerWithDerivationPath:(DSAuthenticationKeysDerivationPath *)derivationPath title:(NSString *)title {
    DWDerivationPathKeysViewController *controller = [[DWDerivationPathKeysViewController alloc] initWithDerivationPath:derivationPath];
    controller.title = title;
    [self.navigationController pushViewController:controller animated:YES];
}

@end

NS_ASSUME_NONNULL_END
