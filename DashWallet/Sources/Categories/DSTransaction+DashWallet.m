//
//  Created by Pavel Tikhonenko
//  Copyright © 2022 Dash Core Group. All rights reserved.
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

#import "DSTransaction+DashWallet.h"
#import "NSData+Dash.h"

@implementation DSTransaction (DashWallet)

- (NSDate *)date {
    DSChain *chain = self.chain;
    NSTimeInterval now = [chain timestampForBlockHeight:TX_UNCONFIRMED];
    NSTimeInterval txTime = (self.timestamp > 1) ? self.timestamp : now;
    NSDate *txDate = [NSDate dateWithTimeIntervalSince1970:txTime];

    return txDate;
}

- (NSData *)txHashData {
    return [NSData dataWithBytes:self.txHash.u8 length:sizeof(UInt256)];
}

- (NSString *)txHashHexString {
    return uint256_reverse_data(self.txHash).hexString;
}

+ (uint64_t)txMinOutputAmount {
    return TX_MIN_OUTPUT_AMOUNT;
}
@end
