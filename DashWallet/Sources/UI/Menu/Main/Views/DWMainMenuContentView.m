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

#import "DWMainMenuContentView.h"

#import "DWMainMenuModel.h"
#import "DWMainMenuTableViewCell.h"
#import "DWSharedUIConstants.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWMainMenuContentView () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) UITableView *tableView;

@end

@implementation DWMainMenuContentView

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
        tableView.contentInset = UIEdgeInsetsMake(DWDefaultMargin(), 0.0, DW_TABBAR_NOTCH, 0.0);
        [self addSubview:tableView];
        _tableView = tableView;

        NSString *cellId = DWMainMenuTableViewCell.dw_reuseIdentifier;
        UINib *nib = [UINib nibWithNibName:cellId bundle:nil];
        NSParameterAssert(nib);
        [tableView registerNib:nib forCellReuseIdentifier:cellId];
    }
    return self;
}

- (void)setModel:(DWMainMenuModel *)model {
    _model = model;

    [self.tableView reloadData];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.model.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *cellId = DWMainMenuTableViewCell.dw_reuseIdentifier;
    DWMainMenuTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId forIndexPath:indexPath];

    id<DWMainMenuItem> menuItem = self.model.items[indexPath.row];
    cell.model = menuItem;

#if SNAPSHOT
    if (menuItem.type == DWMainMenuItemType_Security) {
        cell.accessibilityIdentifier = @"menu_security_item";
    }
#endif /* SNAPSHOT */

    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    id<DWMainMenuItem> menuItem = self.model.items[indexPath.row];
    [self.delegate mainMenuContentView:self didSelectMenuItem:menuItem];
}

@end

NS_ASSUME_NONNULL_END
