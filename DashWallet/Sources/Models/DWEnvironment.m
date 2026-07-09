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

#import "DWEnvironment.h"

#import "dashwallet-Swift.h"

NSNotificationName const DWCurrentNetworkDidChangeNotification = @"DWCurrentNetworkDidChangeNotification";
NSNotificationName const DWWillWipeWalletNotification = @"DWWillWipeWalletNotification";

@implementation DWEnvironment


+ (instancetype)sharedInstance {
    static id singleton = nil;
    static dispatch_once_t onceToken = 0;

    dispatch_once(&onceToken, ^{
        singleton = [self new];
    });

    return singleton;
}

- (instancetype)init {
    if (!(self = [super init]))
        return nil;

    // Registers both chains with DSChainsManager. Load-bearing for the wipe:
    // clearAllWalletsAndRemovePin iterates DSChainsManager.chains, which is
    // populated only by these calls, to unregister wallets on BOTH networks.
    [[DSChainsManager sharedInstance] chainManagerForChain:[DSChain mainnet]];
    [[DSChainsManager sharedInstance] chainManagerForChain:[DSChain testnet]];

    return self;
}

- (DSChain *)currentChain {
    // Derived per-read from the selection WalletEnvironment owns — never
    // cached, so an external network switch can't leave the shim stale.
    return DWWalletEnvironment.isTestnet ? [DSChain testnet] : [DSChain mainnet];
}

- (DSChainManager *)currentChainManager {
    return [[DSChainsManager sharedInstance] chainManagerForChain:self.currentChain];
}

- (DSWallet *)currentWallet {
    return [[self.currentChain wallets] firstObject];
}

- (DSAccount *)currentAccount {
    return [[self.currentWallet accounts] firstObject];
}

- (void)clearAllWallets {
    [self clearAllWalletsAndRemovePin:YES];
}

- (void)clearAllWalletsAndRemovePin:(BOOL)shouldRemovePin {
    [[NSNotificationCenter defaultCenter] postNotificationName:DWWillWipeWalletNotification object:self];

    NSManagedObjectContext *context = [NSManagedObjectContext chainContext];
    for (DSChain *chain in [[DSChainsManager sharedInstance] chains]) {
        [[DashSync sharedSyncController] wipeBlockchainNonTerminalDataForChain:chain inContext:context];
        [chain unregisterAllWallets];
    }

    if (shouldRemovePin) {
        [[DWAuthenticationService shared] removePin]; // this can only work if there are no wallets
    }
}

- (BOOL)mirrorWalletRegistryToChainType:(NSInteger)chainType seedPhrase:(NSString *)seedPhrase {
    DSChain *destinationChain = nil;
    switch (chainType) {
        case ChainType_MainNet:
            destinationChain = [DSChain mainnet];
            break;
        case ChainType_TestNet:
            destinationChain = [DSChain testnet];
            break;
        default:
            break;
    }
    if (!destinationChain) {
        return NO;
    }
    if ([destinationChain hasAWallet] || seedPhrase == nil) {
        return YES;
    }

    // Same registration the create/recover dual-write performs, on the
    // destination chain. Replaces the legacy copyForChain: (which ran a
    // DashSync-pod PIN prompt to read the phrase — the phrase now comes from
    // the SDK's WalletStorage, the keychain being the security boundary).
    // BIP39 derivation runs on the calling thread (~100 ms), the same cost
    // copyForChain paid post-auth.
    DSWallet *wallet = [DSWallet standardWalletWithSeedPhrase:seedPhrase
                                              setCreationDate:BIP39_WALLET_UNKNOWN_CREATION_TIME
                                                     forChain:destinationChain
                                              storeSeedPhrase:YES
                                                  isTransient:NO];
    return wallet != nil;
}

@end
