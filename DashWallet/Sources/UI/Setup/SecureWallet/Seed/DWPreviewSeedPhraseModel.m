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

#import <DashSync/DashSync.h>

#import "DWEnvironment.h"
#import "DWGlobalOptions.h"
#import "DWSeedPhraseModel.h"

NS_ASSUME_NONNULL_BEGIN

@implementation DWPreviewSeedPhraseModel

- (void)dealloc {
    DSLogVerbose(@"☠️ %@", NSStringFromClass(self.class));
}

+ (BOOL)shouldVerifyPassphrase {
    return [DWGlobalOptions sharedInstance].walletNeedsBackup;
}

- (DWSeedPhraseModel *)getOrCreateNewWallet {
    BOOL hasAWallet = [DWEnvironment sharedInstance].currentWallet != nil;
    if (!hasAWallet) {
        [DSWallet standardWalletWithRandomSeedPhraseForChain:[DWEnvironment sharedInstance].currentChain storeSeedPhrase:YES isTransient:NO];

        [DWGlobalOptions sharedInstance].walletNeedsBackup = YES;
    }

    // START_SYNC_ENTRY_POINT
    [[DWEnvironment sharedInstance].currentChainManager.peerManager connect];

    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    NSString *seedPhrase = wallet.seedPhraseIfAuthenticated;

    DWSeedPhraseModel *seedPhraseModel = [[DWSeedPhraseModel alloc] initWithSeed:seedPhrase];

    return seedPhraseModel;
}

- (void)clearAllWallets {
    [[DWEnvironment sharedInstance] clearAllWalletsAndRemovePin:NO];
}

@end

NS_ASSUME_NONNULL_END
