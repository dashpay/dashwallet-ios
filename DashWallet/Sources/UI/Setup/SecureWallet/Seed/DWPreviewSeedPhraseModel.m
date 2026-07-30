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


#import "DWGlobalOptions.h"
#import "DWSeedPhraseModel.h"
#import "dashwallet-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@implementation DWPreviewSeedPhraseModel

- (void)dealloc {
    DWLog(@"☠️ %@", NSStringFromClass(self.class));
}

+ (BOOL)shouldVerifyPassphrase {
    return [DWGlobalOptions sharedInstance].walletNeedsBackup;
}

- (DWSeedPhraseModel *)getOrCreateNewWallet {
    BOOL hasAWallet = DWWalletEnvironment.hasWallet;
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
        // If persistence failed earlier this can still return nil. That would
        // otherwise crash `NSParameterAssert(seed)` in
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

    NSString *pin = [DWAuthenticationService shared].currentPin;
    if (pin.length == 0) {
        return;
    }

    DWSwiftDashSDKNetwork network;
    if (DWWalletEnvironment.isMainnet) {
        network = DWSwiftDashSDKNetworkMainnet;
    }
    else if (DWWalletEnvironment.isTestnet) {
        network = DWSwiftDashSDKNetworkTestnet;
    }
    else {
        return; // devnet/regtest unsupported in v1
    }

    [DWSwiftDashSDKWalletCreator createWalletWithMnemonic:mnemonic pin:pin network:network];
}

- (void)clearAllWallets {
    [DWSwiftDashSDKWalletWiper wipeWalletRemovingPin:NO];
}

@end

NS_ASSUME_NONNULL_END
