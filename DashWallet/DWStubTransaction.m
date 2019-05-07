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

#import "DWStubTransaction.h"

#if SNAPSHOT

NS_ASSUME_NONNULL_BEGIN

static UInt256 RandomUInt256() {
    return ((UInt256){.u64 = {
                          ((uint64_t)arc4random() << 32) | (uint64_t)arc4random(),
                          ((uint64_t)arc4random() << 32) | (uint64_t)arc4random(),
                          ((uint64_t)arc4random() << 32) | (uint64_t)arc4random(),
                          ((uint64_t)arc4random() << 32) | (uint64_t)arc4random(),
                      }});
}

@implementation DWStubTransaction

+ (NSArray *)stubTxs {
    NSMutableArray<DWStubTransaction *> *txs = [NSMutableArray array];

    {
        DWStubTransaction *tx = [[DWStubTransaction alloc] init];
        tx.timestamp = [NSDate timeIntervalSince1970] - 0 * 100000;
        tx.received = DUFFS * 3.140000000001;
        tx.balance = DUFFS * 42;
        tx.instantSendReceived = YES;

        [txs addObject:tx];
    }
    {
        DWStubTransaction *tx = [[DWStubTransaction alloc] init];
        tx.timestamp = [NSDate timeIntervalSince1970] - 1 * 100000;
        tx.sent = DUFFS * 2.710000000001;
        tx.balance = DUFFS * 36.4840000000001;

        [txs addObject:tx];
    }
    {
        DWStubTransaction *tx = [[DWStubTransaction alloc] init];
        tx.timestamp = [NSDate timeIntervalSince1970] - 2 * 100000;
        tx.sent = DUFFS * 1.6180000000001;
        tx.balance = DUFFS * 39.1940000000001;

        [txs addObject:tx];
    }
    {
        DWStubTransaction *tx = [[DWStubTransaction alloc] init];
        tx.timestamp = [NSDate timeIntervalSince1970] - 3 * 100000;
        tx.received = DUFFS * 43.1880000000001;
        tx.balance = 0;
        tx.instantSendReceived = NO;

        [txs addObject:tx];
    }

    return [txs copy];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _txHash = RandomUInt256();
        _blockHeight = 100;
        _confirms = 6;
        _transactionIsValid = YES;
        _transactionIsVerified = YES;
        _processAsAuthenticated = YES;
    }
    return self;
}

@end

NS_ASSUME_NONNULL_END

#endif /* SNAPSHOT */
