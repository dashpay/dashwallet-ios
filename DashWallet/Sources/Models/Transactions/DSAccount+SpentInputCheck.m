//
//  Created by Roman Chornyi
//  Copyright © 2024 Dash Core Group. All rights reserved.
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

#import "DSAccount+SpentInputCheck.h"
#import <DashSync/BigIntTypes.h>
#import <DashSync/DSTransaction.h>
#import <DashSync/DSTransactionOutput.h>

@implementation DSAccount (SpentInputCheck)

- (BOOL)isInputSpent:(UInt256)txHash atIndex:(uint32_t)index {
    DSUTXO utxo = {.hash = txHash, .n = (unsigned long)index};
    return [self isSpent:dsutxo_obj(utxo)];
}

@end
