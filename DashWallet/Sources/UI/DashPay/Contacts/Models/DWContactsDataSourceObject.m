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

#import "DWUIKit.h"
#import "DWUserDetailsCell.h"
#import "DWUserDetailsContactCell.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWContactsDataSourceObject ()

@end

NS_ASSUME_NONNULL_END

@implementation DWContactsDataSourceObject

@synthesize contactsDelegate;

- (BOOL)isEmpty {
    return YES;
}

- (id<DWUserDetails>)userDetailsAtIndexPath:(NSIndexPath *)indexPath {
    return nil;
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    id<DWUserDetails> item = [self userDetailsAtIndexPath:indexPath];
    NSString *cellId = nil;
    if (item.displayingType == DWUserDetailsDisplayingType_Contact) {
        cellId = DWUserDetailsContactCell.dw_reuseIdentifier;
    }
    else {
        cellId = DWUserDetailsCell.dw_reuseIdentifier;
    }

    DWUserDetailsCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId
                                                              forIndexPath:indexPath];
    cell.userDetails = item;
    cell.delegate = self.contactsDelegate;

    return cell;
}

@end
