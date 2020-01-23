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
#import "DWBlueActionButton.h"
#import "DWFormTableViewController.h"
#import "DWSecurityStatusView.h"
#import "DWSegmentSliderFormTableViewCell.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWAdvancedSecurityViewController ()

@property (nonatomic, strong) id<DWAdvancedSecurityModelProtocol> model;
@property (nonatomic, strong) DWFormTableViewController *formController;
@property (nonatomic, strong) DWSecurityStatusView *securityStatusView;

@end

@implementation DWAdvancedSecurityViewController

- (instancetype)init {
    return [self initWithModel:[[DWAdvancedSecurityModel alloc] init]];
}

- (instancetype)initWithModel:(id<DWAdvancedSecurityModelProtocol>)model {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _model = model;

        self.title = NSLocalizedString(@"Advanced Security", nil);
        self.hidesBottomBarWhenPushed = YES;
    }
    return self;
}

- (NSArray<DWBaseFormCellModel *> *)firstSectionItems {
    __weak typeof(self) weakSelf = self;

    id<DWAdvancedSecurityModelProtocol> model = self.model;

    NSMutableArray<DWBaseFormCellModel *> *items = [NSMutableArray array];

    DWSwitcherFormCellModel *cellModel =
        [[DWSwitcherFormCellModel alloc] initWithTitle:NSLocalizedString(@"Auto Logout", nil)];
    cellModel.on = self.model.autoLogout;
    cellModel.didChangeValueBlock = ^(DWSwitcherFormCellModel *_Nonnull cellModel) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        strongSelf.model.autoLogout = cellModel.on;
        [strongSelf showOrHideAdditionalOptions:cellModel forSection:0];
        [strongSelf updateSecurityLevel];
    };
    [items addObject:cellModel];

    if (self.model.autoLogout) {
        DWSegmentSliderFormCellModel *cellModel =
            [[DWSegmentSliderFormCellModel alloc] initWithTitle:[model titleForCurrentLockTimerTimeInterval]];
        cellModel.sliderLeftText = [model stringForLockTimerTimeInterval:model.lockTimerTimeIntervals.firstObject];
        cellModel.sliderRightText = [model stringForLockTimerTimeInterval:model.lockTimerTimeIntervals.lastObject];
        cellModel.sliderValues = model.lockTimerTimeIntervals;
        cellModel.selectedItemIndex = [model.lockTimerTimeIntervals indexOfObject:model.lockTimerTimeInterval];
        cellModel.detailBuilder = ^NSAttributedString *(UIFont *font, UIColor *color) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return [[NSAttributedString alloc] init];
            }

            return [strongSelf.model currentLockTimerTimeIntervalWithFont:font color:color];
        };
        cellModel.didChangeValueBlock = ^(DWSegmentSliderFormCellModel *cellModel, UITableViewCell *cell) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            id<DWAdvancedSecurityModelProtocol> model = strongSelf.model;
            model.lockTimerTimeInterval = model.lockTimerTimeIntervals[cellModel.selectedItemIndex];
            cellModel.title = [model titleForCurrentLockTimerTimeInterval];

            [strongSelf updateSecurityLevel];

            UITableView *tableView = strongSelf.formController.tableView;
            NSIndexPath *indexPath = [tableView indexPathForCell:cell];
            if (indexPath) {
                [tableView reloadRowsAtIndexPaths:@[ indexPath ]
                                 withRowAnimation:UITableViewRowAnimationNone];
            }
        };
        [items addObject:cellModel];
    }

    return [items copy];
}

- (NSArray<DWBaseFormCellModel *> *)secondSectionItems {
    __weak typeof(self) weakSelf = self;

    id<DWAdvancedSecurityModelProtocol> model = self.model;

    NSMutableArray<DWBaseFormCellModel *> *items = [NSMutableArray array];

    DWSwitcherFormCellModel *cellModel =
        [[DWSwitcherFormCellModel alloc] initWithTitle:NSLocalizedString(@"Spending Confirmation", nil)];
    cellModel.on = model.spendingConfirmationEnabled;
    cellModel.didChangeValueBlock = ^(DWSwitcherFormCellModel *cellModel) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        id<DWAdvancedSecurityModelProtocol> model = strongSelf.model;
        model.spendingConfirmationEnabled = cellModel.on;

        if (model.canConfigureSpendingConfirmation) {
            [strongSelf showOrHideAdditionalOptions:cellModel forSection:1];
        }

        [strongSelf updateSecurityLevel];
    };
    [items addObject:cellModel];

    if (model.canConfigureSpendingConfirmation && model.spendingConfirmationEnabled) {
        DWSegmentSliderFormCellModel *cellModel =
            [[DWSegmentSliderFormCellModel alloc] initWithTitle:[model titleForSpendingConfirmationOption]];
        cellModel.sliderValues = model.spendingConfirmationValues;
        cellModel.selectedItemIndex = [model.spendingConfirmationValues indexOfObject:model.spendingConfirmationLimit];
        cellModel.sliderLeftAttributedTextBuilder = ^NSAttributedString *(UIFont *font, UIColor *color) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return [[NSAttributedString alloc] init];
            }

            id<DWAdvancedSecurityModelProtocol> model = strongSelf.model;
            return [model spendingConfirmationString:model.spendingConfirmationValues.firstObject
                                                font:font
                                               color:color];
        };
        cellModel.sliderRightAttributedTextBuilder = ^NSAttributedString *(UIFont *font, UIColor *color) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return [[NSAttributedString alloc] init];
            }

            id<DWAdvancedSecurityModelProtocol> model = strongSelf.model;
            return [model spendingConfirmationString:model.spendingConfirmationValues.lastObject
                                                font:font
                                               color:color];
        };
        cellModel.detailBuilder = ^NSAttributedString *(UIFont *font, UIColor *color) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return [[NSAttributedString alloc] init];
            }

            return [strongSelf.model currentSpendingConfirmationWithFont:font color:color];
        };
        cellModel.descriptionTextBuilder = ^NSAttributedString *(UIFont *font, UIColor *color) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return [[NSAttributedString alloc] init];
            }

            return [strongSelf.model currentSpendingConfirmationDescriptionWithFont:font color:color];
        };
        cellModel.didChangeValueBlock = ^(DWSegmentSliderFormCellModel *cellModel, UITableViewCell *cell) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            id<DWAdvancedSecurityModelProtocol> model = strongSelf.model;
            model.spendingConfirmationLimit = model.spendingConfirmationValues[cellModel.selectedItemIndex];

            [strongSelf updateSecurityLevel];

            UITableView *tableView = strongSelf.formController.tableView;
            NSIndexPath *indexPath = [tableView indexPathForCell:cell];
            if (indexPath) {
                [tableView reloadRowsAtIndexPaths:@[ indexPath ]
                                 withRowAnimation:UITableViewRowAnimationNone];
            }
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

    DWFormSectionModel *section = [[DWFormSectionModel alloc] init];
    section.items = [self secondSectionItems];
    [sections addObject:section];

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

    // button width will be adjusted in viewDidLayoutSubviews
    DWBlueActionButton *resetButton = [[DWBlueActionButton alloc] initWithFrame:CGRectMake(0.0, 0.0, 320.0, 54.0)];
    resetButton.usedOnDarkBackground = NO;
    resetButton.inverted = YES;
    [resetButton setTitle:NSLocalizedString(@"Reset to Default", nil) forState:UIControlStateNormal];
    [resetButton addTarget:self action:@selector(resetButtonAction) forControlEvents:UIControlEventTouchUpInside];
    formController.tableView.tableFooterView = resetButton;

    [self dw_embedChild:formController];
    self.formController = formController;

    [self reloadData];
    [self updateSecurityLevel];

    // Notifications

    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    [notificationCenter addObserver:self
                           selector:@selector(applicationWillResignActiveNotification)
                               name:UIApplicationWillResignActiveNotification
                             object:nil];
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

    UIView *footerView = tableView.tableFooterView;
    if (footerView) {
        CGRect frame = footerView.frame;
        frame.size.width = CGRectGetWidth(tableView.bounds);
        footerView.frame = frame;

        tableView.tableFooterView = footerView;
    }
}

#pragma mark - Notifications

- (void)applicationWillResignActiveNotification {
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - Actions

- (void)resetButtonAction {
    [self.model resetToDefault];
    [self reloadData];
    [self updateSecurityLevel];
}

#pragma mark - Private

- (void)reloadData {
    [self.formController setSections:[self sections] placeholderText:nil];
}

- (void)showOrHideAdditionalOptions:(DWSwitcherFormCellModel *)cellModel forSection:(NSInteger)section {
    DWFormTableViewController *formController = self.formController;
    [formController setSections:[self sections] placeholderText:nil shouldReloadData:NO];

    UITableView *tableView = formController.tableView;
    [tableView
        performBatchUpdates:^{
            NSIndexPath *firstIndexPath = [NSIndexPath indexPathForRow:0 inSection:section];
            [tableView reloadRowsAtIndexPaths:@[ firstIndexPath ]
                             withRowAnimation:UITableViewRowAnimationNone];

            NSIndexPath *secondIndexPath = [NSIndexPath indexPathForRow:1 inSection:section];
            UITableViewCell *animatedCell = [tableView cellForRowAtIndexPath:secondIndexPath];

            if (cellModel.on) {
                animatedCell.contentView.alpha = 0.0;
                [UIView animateWithDuration:[CATransaction animationDuration]
                                 animations:^{
                                     animatedCell.contentView.alpha = 1.0;
                                 }];

                [tableView insertRowsAtIndexPaths:@[ secondIndexPath ]
                                 withRowAnimation:UITableViewRowAnimationTop];
            }
            else {
                [UIView animateWithDuration:[CATransaction animationDuration]
                                 animations:^{
                                     animatedCell.contentView.alpha = 0.0;
                                 }];

                [tableView deleteRowsAtIndexPaths:@[ secondIndexPath ]
                                 withRowAnimation:UITableViewRowAnimationTop];
            }
        }
                 completion:nil];
}

- (void)updateSecurityLevel {
    self.securityStatusView.securityLevel = self.model.securityLevel;
}

@end

NS_ASSUME_NONNULL_END
