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

#import "DWContactsDataSourceObject.h"

#import "DWContactListTableViewCell.h"
#import "DWUIKit.h"

@interface DWContactsDataSourceObject ()

@property (nonatomic, copy) NSArray<id<DWContactItem>> *items;

@end

@implementation DWContactsDataSourceObject

@synthesize contactsDelegate;

- (instancetype)initWithItems:(NSArray<id<DWContactItem>> *)items {
    self = [super init];
    if (self) {
        _items = [items copy];
    }
    return self;
}

- (BOOL)isEmpty {
    return (self.items.count == 0);
}

- (id<DWContactItem>)contactAtIndexPath:(NSIndexPath *)indexPath {
    id<DWContactItem> contact = self.items[indexPath.row];
    return contact;
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *cellId = DWContactListTableViewCell.dw_reuseIdentifier;
    DWContactListTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId
                                                                       forIndexPath:indexPath];
    id<DWContactItem> contact = [self contactAtIndexPath:indexPath];
    cell.contact = contact;
    cell.delegate = self.contactsDelegate;

    return cell;
}

@end
