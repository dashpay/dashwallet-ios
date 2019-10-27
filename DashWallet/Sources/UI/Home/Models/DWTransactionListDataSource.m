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

#import "DWTransactionListDataSource+DWProtected.h"

#import <DashSync/DashSync.h>

#import "DWTxListTableViewCell.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWTransactionListDataSource ()

@property (nullable, nonatomic, weak) id<DWTransactionListDataProviderProtocol> dataProvider;

@end

@implementation DWTransactionListDataSource


- (instancetype)initWithTransactions:(NSArray<DSTransaction *> *)transactions
                        dataProvider:(id<DWTransactionListDataProviderProtocol>)dataProvider {
    self = [super init];
    if (self) {
        _items = [transactions copy];
        _dataProvider = dataProvider;
    }
    return self;
}

- (BOOL)isEmpty {
    return (self.items.count == 0);
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *cellId = DWTxListTableViewCell.dw_reuseIdentifier;
    DWTxListTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId
                                                                  forIndexPath:indexPath];
    DSTransaction *transaction = self.items[indexPath.row];
    [cell configureWithTransaction:transaction dataProvider:self.dataProvider];
    return cell;
}

@end

NS_ASSUME_NONNULL_END
