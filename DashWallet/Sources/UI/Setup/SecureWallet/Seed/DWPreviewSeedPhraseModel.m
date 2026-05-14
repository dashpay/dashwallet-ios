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

#import "DWPreviewSeedPhraseModel.h"

#import <DashSync/DSAuthenticationManager+Private.h>

#import "DWEnvironment.h"
#import "DWGlobalOptions.h"
#import "DWSeedPhraseModel.h"
#import "dashwallet-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@implementation DWPreviewSeedPhraseModel

- (void)dealloc {
    DSLog(@"☠️ %@", NSStringFromClass(self.class));
}

+ (BOOL)shouldVerifyPassphrase {
    return [DWGlobalOptions sharedInstance].walletNeedsBackup;
}

- (DWSeedPhraseModel *)getOrCreateNewWallet {
    BOOL hasAWallet = [DWEnvironment sharedInstance].currentWallet != nil;
    NSString *seedPhrase;

    if (!hasAWallet) {
        // SwiftDashSDK is the entropy source. `generateAndStore` no longer
        // persists synchronously — the SwiftDashSDK refactor made
        // `WalletStorage` require a walletId, so persistence is deferred to
        // the async `SwiftDashSDKHost.createOrImportWallet` path kicked off
        // by `createSwiftDashSDKWalletWithMnemonic:` below. Use the in-hand
        // string here rather than `readMnemonic`, which would race against
        // that background dispatch and return nil → crash on `initWithSeed:`.
        NSString *mnemonic = [self generateAndStoreMnemonic];
        if (mnemonic.length == 0) {
            return [[DWSeedPhraseModel alloc] initWithSeed:nil];
        }

        // Feed the SwiftDashSDK-generated mnemonic TO DashSync. DashSync
        // still owns SPV sync — it needs the wallet structure.
        [DSWallet standardWalletWithSeedPhrase:mnemonic
                               setCreationDate:[[NSDate date] timeIntervalSince1970]
                                      forChain:[DWEnvironment sharedInstance].currentChain
                               storeSeedPhrase:YES
                                   isTransient:NO];

        [DWGlobalOptions sharedInstance].walletNeedsBackup = YES;

        // Async: persists mnemonic to WalletStorage under the new walletId
        // (ManagedPlatformWallet, SwiftData record, and mnemonic stored by
        // wallet id). Nothing on this screen depends on completion.
        [self createSwiftDashSDKWalletWithMnemonic:mnemonic];

        seedPhrase = mnemonic;
    }
    else {
        // Settings → View Recovery Phrase path. Mnemonic was persisted earlier
        // (by migration / first-create) under an existing walletId. Two
        // realistic ways this read still returns nil though:
        //  1) migrator deferred this wallet (multi-wallet or unknown chain
        //     — see `enumerateDashSyncMnemonicAccounts` / `detectNetwork`).
        //  2) async `SwiftDashSDKHost.createOrImportWallet` failed earlier
        //     in the lifecycle, leaving DashSync's wallet without a paired
        //     SwiftDashSDK record.
        // Both cases would otherwise crash `NSParameterAssert(seed)` in
        // `DWSeedPhraseModel initWithSeed:`. Fall back to an empty string —
        // the screen renders blank words, which is a degraded UX but
        // survivable. Proper fix (DashSync fallback or error banner) is
        // a follow-up once the broader DashSync-drop is in flight.
        seedPhrase = [self readStoredMnemonic] ?: @"";
    }

    return [[DWSeedPhraseModel alloc] initWithSeed:seedPhrase];
}

- (void)createSwiftDashSDKWalletWithMnemonic:(NSString *)mnemonic {
    if (mnemonic.length == 0) {
        return;
    }

    NSError *pinError = nil;
    NSString *pin = [[DSAuthenticationManager sharedInstance] getPin:&pinError];
    if (pin.length == 0) {
        return;
    }

    DWSwiftDashSDKNetwork network;
    switch ([DWEnvironment sharedInstance].currentChain.chainType.tag) {
        case ChainType_MainNet:
            network = DWSwiftDashSDKNetworkMainnet;
            break;
        case ChainType_TestNet:
            network = DWSwiftDashSDKNetworkTestnet;
            break;
        default:
            return; // devnet/regtest unsupported in v1
    }

    [DWSwiftDashSDKWalletCreator createWalletWithMnemonic:mnemonic pin:pin network:network];
}

- (void)clearAllWallets {
    [[DWEnvironment sharedInstance] clearAllWalletsAndRemovePin:NO];
}

@end

NS_ASSUME_NONNULL_END
