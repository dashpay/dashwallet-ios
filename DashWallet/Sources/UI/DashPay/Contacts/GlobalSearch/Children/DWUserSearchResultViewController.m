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

#import "DWUserSearchResultViewController.h"

#import "DWUIKit.h"

#import "DWDPBasicCell.h"
#import "DWDPNewIncomingRequestItem.h"
#import "UITableView+DWDPItemDequeue.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWUserSearchResultViewController () <DWDPNewIncomingRequestItemDelegate>
@end

NS_ASSUME_NONNULL_END

@implementation DWUserSearchResultViewController

- (void)setItems:(NSArray<id<DWDPBasicItem>> *)items {
    _items = [items copy];

    [self.tableView reloadData];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor dw_secondaryBackgroundColor];

    [self.tableView dw_registerDPItemCells];
    self.tableView.backgroundColor = [UIColor dw_secondaryBackgroundColor];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 72.0;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    id<DWDPBasicItem> item = self.items[indexPath.row];

    DWDPBasicCell *cell = [tableView dw_dequeueReusableCellForItem:item atIndexPath:indexPath];
    cell.displayItemBackgroundView = YES;
    cell.delegate = self;
    [cell setItem:item highlightedText:self.searchQuery];

    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    [self.delegate userSearchResultViewController:self willDisplayItemAtIndex:indexPath.row];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [self.tableView deselectRowAtIndexPath:indexPath animated:YES];

    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    [self.delegate userSearchResultViewController:self didSelectItemAtIndex:indexPath.row cell:cell];
}

#pragma mark - DWDPNewIncomingRequestItemDelegate

- (void)acceptIncomingRequest:(id<DWDPBasicItem>)item {
    [self.delegate userSearchResultViewController:self acceptContactRequest:item];
}

- (void)declineIncomingRequest:(id<DWDPBasicItem>)item {
    [self.delegate userSearchResultViewController:self declineContactRequest:item];
}

@end
