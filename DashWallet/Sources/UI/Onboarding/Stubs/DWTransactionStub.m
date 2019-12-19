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

#import "DWTransactionStub.h"

NS_ASSUME_NONNULL_BEGIN

static UInt256 RandomUInt256() {
    return ((UInt256){.u64 = {
                          ((uint64_t)arc4random() << 32) | (uint64_t)arc4random(),
                          ((uint64_t)arc4random() << 32) | (uint64_t)arc4random(),
                          ((uint64_t)arc4random() << 32) | (uint64_t)arc4random(),
                          ((uint64_t)arc4random() << 32) | (uint64_t)arc4random(),
                      }});
}

@implementation DWTransactionStub

+ (NSArray<DWTransactionStub *> *)stubs {
    NSMutableArray<DWTransactionStub *> *stubs = [NSMutableArray array];

    DSChain *dummyChain = nil;

    {
        DWTransactionStub *tx = [[DWTransactionStub alloc] initOnChain:dummyChain];
        tx.txHash = RandomUInt256();
        tx.timestamp = [NSDate timeIntervalSince1970] - 0 * 100000;
        tx.dashAmount = DUFFS * 3.140000000001;
        tx.detailedDirection = DWTransactionDetailedDirection_Sent;
        [stubs addObject:tx];
    }

    {
        DWTransactionStub *tx = [[DWTransactionStub alloc] initOnChain:dummyChain];
        tx.txHash = RandomUInt256();
        tx.timestamp = [NSDate timeIntervalSince1970] - 1 * 100000;
        tx.dashAmount = DUFFS * 2.710000000001;
        tx.detailedDirection = DWTransactionDetailedDirection_Received;
        [stubs addObject:tx];
    }

    {
        DWTransactionStub *tx = [[DWTransactionStub alloc] initOnChain:dummyChain];
        tx.txHash = RandomUInt256();
        tx.timestamp = [NSDate timeIntervalSince1970] - 2 * 100000;
        tx.dashAmount = DUFFS * 1.6180000000001;
        tx.detailedDirection = DWTransactionDetailedDirection_Sent;
        [stubs addObject:tx];
    }

    {
        DWTransactionStub *tx = [[DWTransactionStub alloc] initOnChain:dummyChain];
        tx.txHash = RandomUInt256();
        tx.timestamp = [NSDate timeIntervalSince1970] - 3 * 100000;
        tx.dashAmount = DUFFS * 44.0480000000001;
        tx.detailedDirection = DWTransactionDetailedDirection_Received;
        [stubs addObject:tx];
    }

    return [stubs copy];
}

- (DSTransactionDirection)direction {
    if (self.detailedDirection == DWTransactionDetailedDirection_Received) {
        return DSTransactionDirection_Received;
    }
    else {
        return DSTransactionDirection_Sent;
    }
}

@end

NS_ASSUME_NONNULL_END
