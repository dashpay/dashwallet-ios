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

#import "DWAdvancedSecurityViewController.h"

#import "DWAdvancedSecurityModel.h"
#import "DWFormTableViewController.h"
#import "DWSecurityStatusView.h"
#import "DWSegmentSliderFormTableViewCell.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWAdvancedSecurityViewController ()

@property (null_resettable, nonatomic, strong) DWAdvancedSecurityModel *model;
@property (nonatomic, strong) DWFormTableViewController *formController;
@property (nonatomic, strong) DWSecurityStatusView *securityStatusView;

@end

@implementation DWAdvancedSecurityViewController

- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        self.title = NSLocalizedString(@"Advanced Security", nil);
        self.hidesBottomBarWhenPushed = YES;
    }

    return self;
}

- (DWAdvancedSecurityModel *)model {
    if (!_model) {
        _model = [[DWAdvancedSecurityModel alloc] init];
    }

    return _model;
}

- (NSArray<DWBaseFormCellModel *> *)firstSectionItems {
    __weak typeof(self) weakSelf = self;

    DWAdvancedSecurityModel *model = self.model;

    NSMutableArray<DWBaseFormCellModel *> *items = [NSMutableArray array];

    {
        DWSegmentSliderFormCellModel *cellModel =
            [[DWSegmentSliderFormCellModel alloc] initWithTitle:NSLocalizedString(@"Keep me logged in", nil)];
        cellModel.sliderLeftText = [model stringForLockTimerTimeInterval:model.lockTimerTimeIntervals.firstObject];
        cellModel.sliderRightText = [model stringForLockTimerTimeInterval:model.lockTimerTimeIntervals.lastObject];
        cellModel.sliderValues = model.lockTimerTimeIntervals;
        cellModel.selectedItemIndex = [model.lockTimerTimeIntervals indexOfObject:model.lockTimerTimeInterval];
        cellModel.detailBuilder = ^NSAttributedString *_Nonnull(UIFont *_Nonnull font, UIColor *_Nonnull color) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return [[NSAttributedString alloc] init];
            }

            return [strongSelf.model attributedStringForCurrentLockTimerTimeIntervalWithFont:font];
        };
        cellModel.didChangeValueBlock = ^(DWSegmentSliderFormCellModel *_Nonnull cellModel) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            DWAdvancedSecurityModel *model = strongSelf.model;
            model.lockTimerTimeInterval = model.lockTimerTimeIntervals[cellModel.selectedItemIndex];
        };
        [items addObject:cellModel];
    }

    return [items copy];
}

- (NSArray<DWBaseFormCellModel *> *)secondSectionItems {
    __weak typeof(self) weakSelf = self;

    NSMutableArray<DWBaseFormCellModel *> *items = [NSMutableArray array];

    {
        DWSwitcherFormCellModel *cellModel =
            [[DWSwitcherFormCellModel alloc] initWithTitle:NSLocalizedString(@"Payment Authentication", nil)];
        cellModel.on = self.model.paymentAuthentication;
        cellModel.didChangeValueBlock = ^(DWSwitcherFormCellModel *_Nonnull cellModel) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            strongSelf.model.paymentAuthentication = cellModel.on;
            [strongSelf showOrHidePaymentAuthOptions:cellModel];
        };
        [items addObject:cellModel];
    }

    if (self.model.paymentAuthentication) {
        DWSegmentSliderFormCellModel *cellModel = [[DWSegmentSliderFormCellModel alloc] initWithTitle:NSLocalizedString(@"Touch ID limit", nil)];
        cellModel.sliderLeftText = @"0";
        cellModel.sliderRightText = NSLocalizedString(@"Unlimited", nil);
        cellModel.sliderValues = @[ @0, @1, @5, @60, @(60 * 4) ];
        cellModel.didChangeValueBlock = ^(DWSegmentSliderFormCellModel *_Nonnull cellModel) {
            NSLog(@">>>>>> %@", @(cellModel.selectedItemIndex));
        };
        [items addObject:cellModel];
    }

    return [items copy];
}

- (NSArray<DWFormSectionModel *> *)sections {
    NSMutableArray<DWFormSectionModel *> *sections = [NSMutableArray array];

    {
        DWFormSectionModel *section = [[DWFormSectionModel alloc] init];
        section.items = [self firstSectionItems];
        [sections addObject:section];
    }

    {
        DWFormSectionModel *section = [[DWFormSectionModel alloc] init];
        section.items = [self secondSectionItems];
        [sections addObject:section];
    }

    return [sections copy];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor dw_secondaryBackgroundColor];

    DWFormTableViewController *formController = [[DWFormTableViewController alloc] initWithStyle:UITableViewStylePlain];
    [formController registerCustomCellModelClass:DWSegmentSliderFormCellModel.class
                                    forCellClass:DWSegmentSliderFormTableViewCell.class];

    DWSecurityStatusView *securityStatusView = [[DWSecurityStatusView alloc] initWithFrame:CGRectZero];
    formController.tableView.tableHeaderView = securityStatusView;
    self.securityStatusView = securityStatusView;

    [self addChildViewController:formController];
    formController.view.frame = self.view.bounds;
    formController.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:formController.view];
    [formController didMoveToParentViewController:self];
    self.formController = formController;

    [formController setSections:[self sections] placeholderText:nil];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    UITableView *tableView = self.formController.tableView;
    UIView *headerView = tableView.tableHeaderView;
    if (headerView != nil) {
        CGSize size = [headerView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
        if (headerView.frame.size.height != size.height) {
            CGRect frame = headerView.frame;
            frame.size.height = size.height;
            headerView.frame = frame;

            tableView.tableHeaderView = headerView;
        }
    }
}

#pragma mark - Private

- (void)showOrHidePaymentAuthOptions:(DWSwitcherFormCellModel *)cellModel {
    DWFormTableViewController *formController = self.formController;
    [formController setSections:[self sections] placeholderText:nil shouldReloadData:NO];

    UITableView *tableView = formController.tableView;
    [tableView
        performBatchUpdates:^{
            NSIndexPath *firstIndexPath = [NSIndexPath indexPathForRow:0 inSection:1];
            [tableView reloadRowsAtIndexPaths:@[ firstIndexPath ]
                             withRowAnimation:UITableViewRowAnimationNone];

            NSIndexPath *secondIndexPath = [NSIndexPath indexPathForRow:1 inSection:1];
            if (cellModel.on) {
                [tableView insertRowsAtIndexPaths:@[ secondIndexPath ]
                                 withRowAnimation:UITableViewRowAnimationTop];
            }
            else {
                [tableView deleteRowsAtIndexPaths:@[ secondIndexPath ]
                                 withRowAnimation:UITableViewRowAnimationTop];
            }
        }
                 completion:nil];
}

@end

NS_ASSUME_NONNULL_END
