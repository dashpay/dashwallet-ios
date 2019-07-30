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
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWHomeView () <UITableViewDelegate>

@property (readonly, nonatomic, strong) DWHomeHeaderView *headerView;
@property (readonly, nonatomic, strong) UIView *topOverscrollView;
@property (readonly, nonatomic, strong) DWTxListHeaderView *txListHeaderView;
@property (readonly, nonatomic, strong) UITableView *tableView;

@end

@implementation DWHomeView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_secondaryBackgroundColor];

        DWHomeHeaderView *headerView = [[DWHomeHeaderView alloc] initWithFrame:CGRectZero];
        _headerView = headerView;

        UIView *topOverscrollView = [[UIView alloc] initWithFrame:CGRectZero];
        topOverscrollView.backgroundColor = [UIColor dw_dashBlueColor];
        _topOverscrollView = topOverscrollView;

        DWTxListHeaderView *txListHeaderView = [[DWTxListHeaderView alloc] initWithFrame:CGRectZero];
        _txListHeaderView = txListHeaderView;

        UITableView *tableView = [[UITableView alloc] initWithFrame:self.bounds style:UITableViewStylePlain];
        tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        tableView.tableHeaderView = headerView;
        tableView.backgroundColor = [UIColor dw_secondaryBackgroundColor];
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

    self.tableView.dataSource = model.allDataSource;
    [self.tableView reloadData];
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

#pragma mark - UITableViewDelegate

- (nullable UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    DWTxListHeaderView *headerView = [[DWTxListHeaderView alloc] initWithFrame:CGRectZero];
    return headerView;
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    [self.headerView parentScrollViewDidScroll:scrollView];
}

@end

NS_ASSUME_NONNULL_END
