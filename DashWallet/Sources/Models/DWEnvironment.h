//
//  Created by Sam Westrich
//  Copyright © 2018-2019 Dash Core Group. All rights reserved.
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

#import <Foundation/Foundation.h>

#import <DashSync/DashSync.h>

NS_ASSUME_NONNULL_BEGIN

/// Posted by `WalletEnvironment.switchToNetwork` after the persisted network
/// selection changes. The SDK wallet runtime restarts SPV on it;
/// DWRootModel rebuilds the home stack.
extern NSNotificationName const DWCurrentNetworkDidChangeNotification;
extern NSNotificationName const DWWillWipeWalletNotification;
/// Posted by DWAppRootViewController once the lock screen has been dismissed
/// after a successful PIN / biometric unlock. Not posted when the lock screen
/// is disabled or was never required this session.
extern NSNotificationName const DWAppDidUnlockNotification;

/// Frozen DashSync wallet-registry shim (post-M6). DashSync no longer syncs;
/// its wallet objects survive only as a derivation-path/identity registry for
/// the not-yet-migrated consumers — DashPay/invites (C10), Apple Watch (D1),
/// and xpub export. Wallet state (balance, UTXOs, transactions) lives in
/// `SwiftDashSDKWalletState`; network identity lives in `WalletEnvironment`.
/// The whole shim goes away with the C6-E dual-write cut.
@interface DWEnvironment : NSObject

/// The DSChain matching the persisted network selection, derived per-read
/// from `WalletEnvironment` (devnet/unknown map to mainnet — registry-only;
/// the SDK runtime fails fast on unsupported networks itself).
@property (nonatomic, readonly) DSChain *currentChain;
@property (nonatomic, readonly) DSWallet *currentWallet;
@property (nonatomic, readonly) DSAccount *currentAccount;
@property (nonatomic, readonly) DSChainManager *currentChainManager;
+ (instancetype)sharedInstance;

- (void)clearAllWallets;
- (void)clearAllWalletsAndRemovePin:(BOOL)shouldRemovePin;

/// Registers a DSWallet for `seedPhrase` on the chain matching `chainType`
/// (`ChainType_Tag` raw value) so the registry keeps resolving after a network
/// switch — nonnull `currentWallet`/`currentAccount` consumers (DashPay, xpub
/// export, watch) read it on the new chain. Registry-only: no sync, no SPV.
/// Returns YES when the chain already has a wallet or `seedPhrase` is nil
/// (nothing to mirror); NO for unsupported chain types.
- (BOOL)mirrorWalletRegistryToChainType:(NSInteger)chainType seedPhrase:(nullable NSString *)seedPhrase;

@end

NS_ASSUME_NONNULL_END
