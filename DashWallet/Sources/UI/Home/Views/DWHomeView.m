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

#import "DWHomeHeaderView.h"
#import "DWHomeModel.h"
#import "DWTransactionListDataSource.h"
#import "DWTxListEmptyTableViewCell.h"
#import "DWTxListHeaderView.h"
#import "DWTxListTableViewCell.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWHomeView () <DWHomeHeaderViewDelegate,
                          UITableViewDataSource,
                          UITableViewDelegate,
                          DWHomeModelUpdatesObserver,
                          DWTxListHeaderViewDelegate>

@property (readonly, nonatomic, strong) DWHomeHeaderView *headerView;
@property (readonly, nonatomic, strong) UIView *topOverscrollView;
@property (readonly, nonatomic, strong) UITableView *tableView;

// strong ref to current datasource to make sure it always exists while tableView use it
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
        topOverscrollView.backgroundColor = [UIColor dw_dashBlueColor];
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
        [tableView addSubview:topOverscrollView];
        [self addSubview:tableView];
        _tableView = tableView;

        NSArray<NSString *> *cellIds = @[
            DWTxListEmptyTableViewCell.dw_reuseIdentifier,
            DWTxListTableViewCell.dw_reuseIdentifier,
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
    }
    return self;
}

- (void)setModel:(DWHomeModel *)model {
    NSParameterAssert(model);
    _model = model;
    model.updatesObserver = self;

    self.headerView.model = model;
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

- (void)homeModel:(DWHomeModel *)model didUpdateDataSourceShouldAnimate:(BOOL)shouldAnimate {
    DWTransactionListDataSource *dataSource = self.model.dataSource;
    self.currentDataSource = dataSource;

    if (dataSource.isEmpty) {
        self.tableView.dataSource = self;
        [self.tableView reloadData];
    }
    else {
        self.tableView.dataSource = dataSource;

        if (shouldAnimate) {
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0]
                          withRowAnimation:UITableViewRowAnimationAutomatic];
        }
        else {
            [self.tableView reloadData];
        }
    }
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
    DWTxListHeaderView *headerView = [[DWTxListHeaderView alloc] initWithFrame:CGRectZero];
    headerView.model = self.model;
    headerView.delegate = self;
    return headerView;
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    [self.headerView parentScrollViewDidScroll:scrollView];
}

#pragma mark - DWTxListHeaderViewDelegate

- (void)txListHeaderView:(DWTxListHeaderView *)view filterButtonAction:(UIView *)sender {
    [self.delegate homeView:self showTxFilter:sender];
}

#pragma mark - DWHomeHeaderViewDelegate

- (void)homeHeaderViewDidUpdateContents:(DWHomeHeaderView *)view {
    [self setNeedsLayout];
}

@end

NS_ASSUME_NONNULL_END
