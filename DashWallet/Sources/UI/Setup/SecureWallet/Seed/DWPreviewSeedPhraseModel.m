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
    if (!hasAWallet) {
        // SwiftDashSDK is the entropy source. Generate the 12-word
        // mnemonic and store it in WalletStorage synchronously so the
        // display read below always finds it.
        NSString *mnemonic = [DWSwiftDashSDKMnemonicGenerator generateAndStore];
        if (mnemonic.length == 0) {
            return [[DWSeedPhraseModel alloc] initWithSeed:nil];
        }

        // Feed the SwiftDashSDK-generated mnemonic TO DashSync.
        // DashSync still owns SPV sync — it needs the wallet structure.
        [DSWallet standardWalletWithSeedPhrase:mnemonic
                               setCreationDate:[[NSDate date] timeIntervalSince1970]
                                      forChain:[DWEnvironment sharedInstance].currentChain
                               storeSeedPhrase:YES
                                   isTransient:NO];

        [DWGlobalOptions sharedInstance].walletNeedsBackup = YES;

        // Create full SwiftDashSDK wallet async (seed encryption, HDWallet
        // SwiftData record, etc.). Mnemonic is already in WalletStorage.
        [self createSwiftDashSDKWalletWithMnemonic:mnemonic];
    }

    // START_SYNC_ENTRY_POINT
    [[DWEnvironment sharedInstance].currentChainManager startSync];

    // SwiftDashSDK is the single source for BOTH paths:
    // - Existing wallet: stored by migrator/backfiller/creator
    // - Just-created: stored synchronously by generateAndStore above
    NSString *seedPhrase = [DWSwiftDashSDKMnemonicReader readMnemonic];

    DWSeedPhraseModel *seedPhraseModel = [[DWSeedPhraseModel alloc] initWithSeed:seedPhrase];

    return seedPhraseModel;
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
