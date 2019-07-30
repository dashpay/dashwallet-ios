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

#import "DWTransactionListDataSource.h"

#import "DWTxListEmptyTableViewCell.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@implementation DWTransactionListDataSource

- (BOOL)isEmpty {
    return (self.items.count == 0);
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.isEmpty) {
        return 1;
    }
    else {
        return self.items.count;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.isEmpty) {
        NSString *cellId = DWTxListEmptyTableViewCell.dw_reuseIdentifier;
        DWTxListEmptyTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId
                                                                           forIndexPath:indexPath];
        return cell;
    }
    else {
        // TODO
        return UITableViewCell.new;
    }
}

@end

NS_ASSUME_NONNULL_END
