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

#import "DWTransactionListDataItem.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, DWTransactionState) {
    DWTransactionState_OK,
    DWTransactionState_Invalid,
    DWTransactionState_Locked,
    DWTransactionState_Processing,
    DWTransactionState_Confirming,
};

typedef NS_ENUM(NSUInteger, DWTransactionType) {
    DWTransactionType_Classic,
    DWTransactionType_Reward,
    DWTransactionType_MasternodeRegistration,
    DWTransactionType_MasternodeUpdate,
    DWTransactionType_MasternodeRevoke,
};

@interface DWTransactionListDataItemObject : NSObject <DWTransactionListDataItem>

@property (nonatomic, assign) DWTransactionState state;

@property (nonatomic, copy) NSArray<NSString *> *outputReceiveAddresses;
@property (nonatomic, copy) NSDictionary<NSString *, NSNumber *> *specialInfoAddresses;
@property (nonatomic, copy) NSArray<NSString *> *inputSendAddresses;
@property (nonatomic, assign) uint64_t dashAmount;
@property (nonatomic, assign) DSTransactionDirection direction;
@property (nonatomic, assign) DWTransactionType transactionType;
@property (nonatomic, copy) NSString *fiatAmount;

@end

NS_ASSUME_NONNULL_END
