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
        [DSWallet standardWalletWithRandomSeedPhraseForChain:[DWEnvironment sharedInstance].currentChain storeSeedPhrase:YES isTransient:NO];

        [DWGlobalOptions sharedInstance].walletNeedsBackup = YES;

        // Also create the wallet in SwiftDashSDK so fresh-install and restored
        // users get a SwiftDashSDK side from day one — same end state as
        // upgraded users get from SwiftDashSDKKeyMigrator at launch. The two
        // libraries run independently; DashSync continues to own its own state.
        [self createWalletInSwiftDashSDK];
    }

    // SwiftDashSDK SPV is started by SwiftDashSDKWalletCreator after the
    // wallet record is committed to SwiftData (see SwiftDashSDKWalletCreator.swift).
    // No DashSync startSync needed — DashSync's parallel SPV was retired in M6.

    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    NSString *seedPhrase = wallet.seedPhraseIfAuthenticated;

    DWSeedPhraseModel *seedPhraseModel = [[DWSeedPhraseModel alloc] initWithSeed:seedPhrase];

    return seedPhraseModel;
}

- (void)createWalletInSwiftDashSDK {
    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    if (!wallet) {
        return;
    }

    NSString *mnemonic = wallet.seedPhraseIfAuthenticated;
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
