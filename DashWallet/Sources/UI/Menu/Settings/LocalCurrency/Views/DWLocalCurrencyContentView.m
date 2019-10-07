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

#import "DWLocalCurrencyContentView.h"

#import "DWLocalCurrencyModel.h"
#import "DWLocalCurrencyTableViewCell.h"
#import "DWSharedUIConstants.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWLocalCurrencyContentView () <UITableViewDataSource, UITableViewDelegate>

@property (readonly, nonatomic, strong) UITableView *tableView;

@end

@implementation DWLocalCurrencyContentView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor dw_secondaryBackgroundColor];

        UITableView *tableView = [[UITableView alloc] initWithFrame:self.bounds style:UITableViewStylePlain];
        tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        tableView.backgroundColor = self.backgroundColor;
        tableView.dataSource = self;
        tableView.delegate = self;
        tableView.rowHeight = UITableViewAutomaticDimension;
        tableView.estimatedRowHeight = 74.0;
        tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
        tableView.contentInset = UIEdgeInsetsMake(DWDefaultMargin(), 0.0, 0.0, 0.0);
        [self addSubview:tableView];
        _tableView = tableView;

        [tableView registerClass:DWLocalCurrencyTableViewCell.class
            forCellReuseIdentifier:DWLocalCurrencyTableViewCell.dw_reuseIdentifier];
    }
    return self;
}

- (void)setModel:(DWLocalCurrencyModel *)model {
    _model = model;

    [self.tableView reloadData];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.model.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *cellId = DWLocalCurrencyTableViewCell.dw_reuseIdentifier;
    DWLocalCurrencyTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId forIndexPath:indexPath];

    id<DWCurrencyItem> item = self.model.items[indexPath.row];
    const BOOL selected = [self.model isCurrencyItemsSelected:item];
    [cell configureWithModel:item selected:selected];

    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    id<DWCurrencyItem> item = self.model.items[indexPath.row];
    [self.model selectItem:item];

    [self.tableView reloadRowsAtIndexPaths:self.tableView.indexPathsForVisibleRows
                          withRowAnimation:UITableViewRowAnimationNone];

    [self.delegate localCurrencyContentViewdidSelectCurrencyItem:self];
}

@end

NS_ASSUME_NONNULL_END
