//
//  Created by Andrew Podkovyrin
//  Copyright © 2020 Dash Core Group. All rights reserved.
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

#import "DWNotificationsDataSourceObject.h"

#import "DWDPBasicCell.h"
#import "DWEnvironment.h"
#import "DWNotificationsData.h"
#import "DWUIKit.h"
#import "UITableView+DWDPItemDequeue.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWNotificationsDataSourceObject ()

@property (nullable, nonatomic, weak) UITableView *tableView;
@property (nullable, nonatomic, weak) id<DWDPIncomingRequestItemDelegate> itemsDelegate;

@property (nonatomic, copy) DWNotificationsData *data;

@end

NS_ASSUME_NONNULL_END

@implementation DWNotificationsDataSourceObject

- (void)updateWithData:(DWNotificationsData *)data {
    self.data = data;
    [self.tableView reloadData];
}

- (void)setupWithTableView:(UITableView *)tableView itemsDelegate:(id<DWDPIncomingRequestItemDelegate>)itemsDelegate {
    self.tableView = tableView;
    self.itemsDelegate = itemsDelegate;
}

- (id<DWDPBasicItem>)itemAtIndexPath:(NSIndexPath *)indexPath {
    NSArray<id<DWDPBasicItem>> *items = indexPath.section == 0 ? self.data.unreadItems : self.data.oldItems;
    return items[indexPath.row];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSArray<id<DWDPBasicItem>> *items = section == 0 ? self.data.unreadItems : self.data.oldItems;
    return items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    id<DWDPBasicItem> item = [self itemAtIndexPath:indexPath];

    DWDPBasicCell *cell = [tableView dw_dequeueReusableCellForItem:item atIndexPath:indexPath];
    cell.displayItemBackgroundView = indexPath.section == 0;
    cell.delegate = self.itemsDelegate;
    cell.item = item;
    return cell;
}

@end
