//
//  Created by Andrew Podkovyrin
//  Copyright © 2018 Dash Core Group. All rights reserved.
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

#import "DWUpholdTransactionObject.h"

NS_ASSUME_NONNULL_BEGIN

@implementation DWUpholdTransactionObject

- (nullable instancetype)initWithDictionary:(NSDictionary *)dictionary {
    NSString *identifier = dictionary[@"id"];
    if (!identifier) {
        return nil;
    }

    NSString *typeString = dictionary[@"type"];
    DWUpholdTransactionObjectType type;
    NSDecimalNumber *amount = nil;
    NSDecimalNumber *fee = nil;
    NSDecimalNumber *total = nil;
    NSString *currency = nil;

    if ([typeString isEqualToString:@"withdrawal"]) {
        type = DWUpholdTransactionObjectTypeWithdrawal;
        NSDictionary *origin = dictionary[@"origin"];
        if (!origin) {
            return nil;
        }
        amount = [NSDecimalNumber decimalNumberWithString:origin[@"base"]];
        fee = [NSDecimalNumber decimalNumberWithString:origin[@"fee"]];
        total = [NSDecimalNumber decimalNumberWithString:origin[@"amount"]];
        currency = origin[@"currency"];
    }
    else if ([typeString isEqualToString:@"deposit"]) {
        type = DWUpholdTransactionObjectTypeDeposit;
        NSDictionary *normalized = [dictionary[@"normalized"] firstObject];
        if (!normalized) {
            return nil;
        }
        amount = [NSDecimalNumber decimalNumberWithString:normalized[@"amount"]];
        fee = [NSDecimalNumber decimalNumberWithString:normalized[@"fee"]];
        total = [amount decimalNumberByAdding:fee];
        currency = normalized[@"currency"];
    }
    else {
        return nil;
    }

    if (!amount || !fee || !total || !currency) {
        return nil;
    }

    self = [super init];
    if (self) {
        _identifier = [identifier copy];
        _type = type;
        _amount = amount;
        _fee = fee;
        _total = total;
        _currency = [currency copy];
    }
    return self;
}

@end

NS_ASSUME_NONNULL_END
