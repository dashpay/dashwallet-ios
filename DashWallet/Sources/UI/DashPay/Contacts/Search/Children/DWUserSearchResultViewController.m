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
#import "DWUserDetailsCell.h"

@implementation DWUserSearchResultViewController

- (void)setItems:(NSArray<DWUserSearchItem *> *)items {
    _items = [items copy];

    [self.tableView reloadData];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    NSArray<NSString *> *cellIds = @[
        DWUserDetailsCell.dw_reuseIdentifier,
    ];
    for (NSString *cellId in cellIds) {
        UINib *nib = [UINib nibWithNibName:cellId bundle:nil];
        NSParameterAssert(nib);
        [self.tableView registerNib:nib forCellReuseIdentifier:cellId];
    }

    self.view.backgroundColor = [UIColor dw_secondaryBackgroundColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *cellId = DWUserDetailsCell.dw_reuseIdentifier;
    DWUserDetailsCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId
                                                              forIndexPath:indexPath];
    id<DWUserDetails> item = self.items[indexPath.row];
    cell.userDetails = item;
    cell.delegate = self.contactsDelegate;
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    [self.delegate userSearchResultViewController:self willDisplayItemAtIndex:indexPath.row];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [self.tableView deselectRowAtIndexPath:indexPath animated:YES];

    [self.delegate userSearchResultViewController:self didSelectItemAtIndex:indexPath.row];
}

@end
