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

#import "DWDPRegistrationDoneTableViewCell.h"
#import "DWDPRegistrationErrorTableViewCell.h"
#import "DWDPRegistrationStatus.h"
#import "DWDPRegistrationStatusTableViewCell.h"
#import "DWTxListTableViewCell.h"
#import "DWUIKit.h"

NS_ASSUME_NONNULL_BEGIN

@interface DWTransactionListDataSource ()

@property (nullable, nonatomic, weak) id<DWTransactionListDataProviderProtocol> dataProvider;

@end

@implementation DWTransactionListDataSource


- (instancetype)initWithTransactions:(NSArray<DSTransaction *> *)transactions
                  registrationStatus:(nullable DWDPRegistrationStatus *)registrationStatus
                        dataProvider:(id<DWTransactionListDataProviderProtocol>)dataProvider {
    self = [super init];
    if (self) {
        _items = [transactions copy];
        _registrationStatus = registrationStatus;
        _dataProvider = dataProvider;
    }
    return self;
}

- (BOOL)isEmpty {
    return (self.items.count == 0);
}

- (BOOL)showsRegistrationStatus {
    return self.registrationStatus != nil;
}

- (nullable DSTransaction *)transactionForIndexPath:(NSIndexPath *)indexPath {
    NSInteger index;
    if (self.showsRegistrationStatus) {
        if (indexPath.row == 0) {
            return nil;
        }

        index = indexPath.row - 1;
    }
    else {
        index = indexPath.row;
    }
    return self.items[index];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    const NSInteger itemsCount = self.items.count;
    if (self.showsRegistrationStatus) {
        return 1 + itemsCount;
    }
    else {
        return itemsCount;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.showsRegistrationStatus && indexPath.row == 0) {
        if (self.registrationStatus.failed) {
            NSString *cellID = DWDPRegistrationErrorTableViewCell.dw_reuseIdentifier;
            DWDPRegistrationErrorTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID
                                                                                       forIndexPath:indexPath];
            cell.status = self.registrationStatus;
            cell.delegate = self.retryDelegate;
            return cell;
        }
        if (self.registrationStatus.state == DWDPRegistrationState_Done) {
            NSString *cellID = DWDPRegistrationDoneTableViewCell.dw_reuseIdentifier;
            DWDPRegistrationDoneTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID
                                                                                      forIndexPath:indexPath];
            cell.status = self.registrationStatus;
            return cell;
        }
        else {
            NSString *cellID = DWDPRegistrationStatusTableViewCell.dw_reuseIdentifier;
            DWDPRegistrationStatusTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID
                                                                                        forIndexPath:indexPath];
            cell.status = self.registrationStatus;
            return cell;
        }
    }
    else {
        NSString *cellId = DWTxListTableViewCell.dw_reuseIdentifier;
        DWTxListTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId
                                                                      forIndexPath:indexPath];
        DSTransaction *transaction = [self transactionForIndexPath:indexPath];
        [cell configureWithTransaction:transaction dataProvider:self.dataProvider];
        return cell;
    }
}

@end

NS_ASSUME_NONNULL_END
