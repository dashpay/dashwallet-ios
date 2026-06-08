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

#import <DashSync/BigIntTypes.h>
#import <DashSync/DSAccount.h>

NS_ASSUME_NONNULL_BEGIN

/// Swift-callable wrapper around DSAccount's -isSpent: method.
///
/// DSAccount maintains two sets during updateBalance:
///   - spentOutputs  — correctly updated for ALL registered transactions
///   - utxos         — NOT updated when a tx is marked pending
///
/// A Maya swap transaction is always marked pending because its OP_RETURN
/// output has amount=0 < TX_MIN_OUTPUT_AMOUNT (546 duffs).  That causes the
/// reconciliation step (which removes spent entries from utxos) to be skipped.
/// The result: the just-spent input stays in utxos and gets re-selected for
/// the next coin-selection call, producing a double-spend.
///
/// -isSpent: reads spentOutputs, which IS correct.  This category exposes it
/// with plain scalar arguments so Swift code does not need to construct an
/// NSValue<DSUTXO> manually (requires @encode, unavailable in Swift).
@interface DSAccount (SpentInputCheck)

/// Returns YES if the output identified by (txHash, index) is already listed
/// in the account's spentOutputs set.
- (BOOL)isInputSpent:(UInt256)txHash atIndex:(uint32_t)index;

/// Returns YES if the account has an UNCONFIRMED transaction that carries an
/// OP_RETURN output (script first byte 0x6a). This app only builds OP_RETURN
/// outputs for Maya swaps, so this is a wallet-level "a swap is still
/// confirming" check — used to block other spends until the swap confirms.
- (BOOL)hasUnconfirmedSwapTransaction;

@end

NS_ASSUME_NONNULL_END
