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

#import "DWHomeView.h"

#import "DWDPRegistrationDoneTableViewCell.h"
#import "DWDPRegistrationErrorTableViewCell.h"
#import "DWDPRegistrationStatus.h"
#import "DWDPRegistrationStatusTableViewCell.h"
#import "DWDashPayProtocol.h"
#import "DWHomeHeaderView.h"
#import "DWSharedUIConstants.h"
#import "DWSyncingHeaderView.h"
#import "DWTransactionListDataSource.h"
#import "DWTxListEmptyTableViewCell.h"
#import "DWTxListTableViewCell.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWHomeView () <DWHomeHeaderViewDelegate,
                          UITableViewDataSource,
                          UITableViewDelegate,
                          DWHomeModelUpdatesObserver,
                          DWSyncingHeaderViewDelegate,
                          DWDPRegistrationErrorRetryDelegate>

@property (readonly, nonatomic, strong) DWHomeHeaderView *headerView;
@property (readonly, nonatomic, strong) UIView *topOverscrollView;
@property (readonly, nonatomic, strong) UITableView *tableView;

@property (nullable, nonatomic, weak) DWSyncingHeaderView *syncingHeaderView;

// strong ref to current datasource to make sure it always exists while tableView uses it
@property (nonatomic, strong) DWTransactionListDataSource *currentDataSource;

@end

@implementation DWHomeView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_secondaryBackgroundColor];

        DWHomeHeaderView *headerView = [[DWHomeHeaderView alloc] initWithFrame:CGRectZero];
        headerView.delegate = self;
        _headerView = headerView;

        UIView *topOverscrollView = [[UIView alloc] initWithFrame:CGRectZero];
        topOverscrollView.backgroundColor = [UIColor dw_dashNavigationBlueColor];
        _topOverscrollView = topOverscrollView;

        UITableView *tableView = [[UITableView alloc] initWithFrame:self.bounds style:UITableViewStylePlain];
        tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        tableView.tableHeaderView = headerView;
        tableView.backgroundColor = [UIColor dw_secondaryBackgroundColor];
        tableView.dataSource = self;
        tableView.delegate = self;
        tableView.rowHeight = UITableViewAutomaticDimension;
        tableView.estimatedRowHeight = 74.0;
        tableView.sectionHeaderHeight = UITableViewAutomaticDimension;
        tableView.estimatedSectionHeaderHeight = 64.0;
        tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
        tableView.contentInset = UIEdgeInsetsMake(0.0, 0.0, DW_TABBAR_NOTCH, 0.0);
        [tableView addSubview:topOverscrollView];
        [self addSubview:tableView];
        _tableView = tableView;

        NSArray<NSString *> *cellIds = @[
            DWTxListEmptyTableViewCell.dw_reuseIdentifier,
            DWTxListTableViewCell.dw_reuseIdentifier,
            DWDPRegistrationStatusTableViewCell.dw_reuseIdentifier,
            DWDPRegistrationErrorTableViewCell.dw_reuseIdentifier,
            DWDPRegistrationDoneTableViewCell.dw_reuseIdentifier,
        ];
        for (NSString *cellId in cellIds) {
            UINib *nib = [UINib nibWithNibName:cellId bundle:nil];
            NSParameterAssert(nib);
            [tableView registerNib:nib forCellReuseIdentifier:cellId];
        }

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(setNeedsLayout)
                                                     name:UIContentSizeCategoryDidChangeNotification
                                                   object:nil];

        [self mvvm_observe:DW_KEYPATH(self, model.syncModel.state)
                      with:^(typeof(self) self, NSNumber *value) {
                          if (!value) {
                              return;
                          }

                          [self.syncingHeaderView setSyncState:self.model.syncModel.state];
                      }];

        [self mvvm_observe:DW_KEYPATH(self, model.syncModel.progress)
                      with:^(typeof(self) self, NSNumber *value) {
                          if (!value) {
                              return;
                          }

                          [self.syncingHeaderView setProgress:self.model.syncModel.progress];
                      }];
    }
    return self;
}

- (void)setModel:(id<DWHomeProtocol>)model {
    NSParameterAssert(model);
    _model = model;
    model.updatesObserver = self;

    self.headerView.model = model;
}

- (nullable id<DWShortcutsActionDelegate>)shortcutsDelegate {
    return self.headerView.shortcutsDelegate;
}

- (void)setShortcutsDelegate:(nullable id<DWShortcutsActionDelegate>)shortcutsDelegate {
    self.headerView.shortcutsDelegate = shortcutsDelegate;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGSize size = self.bounds.size;
    self.topOverscrollView.frame = CGRectMake(0.0, -size.height, size.width, size.height);

    UIView *tableHeaderView = self.tableView.tableHeaderView;
    if (tableHeaderView) {
        CGSize headerSize = [tableHeaderView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
        if (CGRectGetHeight(tableHeaderView.frame) != headerSize.height) {
            tableHeaderView.frame = CGRectMake(0.0, 0.0, headerSize.width, headerSize.height);
            self.tableView.tableHeaderView = tableHeaderView;
        }
    }
}

#pragma mark - DWHomeModelUpdatesObserver

- (void)homeModel:(id<DWHomeProtocol>)model didUpdateDataSource:(DWTransactionListDataSource *)dataSource shouldAnimate:(BOOL)shouldAnimate {
    self.currentDataSource = dataSource;
    dataSource.retryDelegate = self;

    if (dataSource.isEmpty) {
        self.tableView.dataSource = self;
        [self.tableView reloadData];
    }
    else {
        self.tableView.dataSource = dataSource;

        [self.tableView reloadData];

        //        if (shouldAnimate && self.window) {
        //            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0]
        //                          withRowAnimation:UITableViewRowAnimationAutomatic];
        //        }
        //        else {
        //            [self.tableView reloadData];
        //        }
    }
}

- (void)homeModel:(id<DWHomeProtocol>)model didReceiveNewTransaction:(DSTransaction *)transaction {
    [self.delegate homeView:self showReclassifyYourTransactionsFlowWithTransaction:transaction];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *cellId = DWTxListEmptyTableViewCell.dw_reuseIdentifier;
    DWTxListEmptyTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId
                                                                       forIndexPath:indexPath];
    return cell;
}

#pragma mark - UITableViewDelegate

- (nullable UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    DWSyncingHeaderView *headerView = [[DWSyncingHeaderView alloc] initWithFrame:CGRectZero];
    headerView.delegate = self;
    [headerView setSyncState:self.model.syncModel.state];
    [headerView setProgress:self.model.syncModel.progress];
    self.syncingHeaderView = headerView;
    return headerView;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (self.currentDataSource.isEmpty) {
        return;
    }

    DSTransaction *transaction = [self.currentDataSource transactionForIndexPath:indexPath];
    if (transaction) {
        [self.delegate homeView:self didSelectTransaction:transaction];
    }
    else { // registration status cell
        [self.delegate homeViewShowDashPayRegistrationFlow:self];
    }
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    [self.headerView parentScrollViewDidScroll:scrollView];
}

#pragma mark - DWSyncingHeaderViewDelegate

- (void)syncingHeaderView:(DWSyncingHeaderView *)view syncingButtonAction:(UIButton *)sender {
    [self.delegate homeView:self showSyncingStatus:sender];
}

- (void)syncingHeaderView:(DWSyncingHeaderView *)view filterButtonAction:(UIButton *)sender {
    [self.delegate homeView:self showTxFilter:sender];
}

#pragma mark - DWHomeHeaderViewDelegate

- (void)homeHeaderViewDidUpdateContents:(DWHomeHeaderView *)view {
    [self setNeedsLayout];
}

- (void)homeHeaderView:(DWHomeHeaderView *)view profileButtonAction:(UIControl *)sender {
    [self.delegate homeView:self profileButtonAction:sender];
}

#pragma mark - DWDPRegistrationErrorRetryDelegate

- (void)registrationErrorRetryAction {
    if ([self.model.dashPayModel canRetry]) {
        [self.model.dashPayModel retry];
    }
    else {
        [self.delegate homeViewShowDashPayRegistrationFlow:self];
    }
}

@end

NS_ASSUME_NONNULL_END
