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
#import "DWNotificationsSection.h"
#import "DWUIKit.h"
#import "UITableView+DWDPItemDequeue.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWNotificationsDataSourceObject ()

@property (nullable, nonatomic, weak) UITableView *tableView;
@property (nullable, nonatomic, weak) id<DWDPIncomingRequestItemDelegate> itemsDelegate;

@property (nonatomic, copy) NSArray<DWNotificationsSection *> *sections;

@end

NS_ASSUME_NONNULL_END

@implementation DWNotificationsDataSourceObject

- (void)updateWithSections:(NSArray<DWNotificationsSection *> *)sections {
    self.sections = sections;
    [self.tableView reloadData];
}

- (void)setupWithTableView:(UITableView *)tableView itemsDelegate:(id<DWDPIncomingRequestItemDelegate>)itemsDelegate {
    self.tableView = tableView;
    self.itemsDelegate = itemsDelegate;
}

- (id<DWDPBasicItem>)itemAtIndexPath:(NSIndexPath *)indexPath {
    DWNotificationsSection *section = self.sections[indexPath.section];
    return [section itemAtIndex:indexPath.row];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    DWNotificationsSection *notificationsSection = self.sections[section];
    return notificationsSection.count;
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