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

#import "DWRecoverModel.h"

#import "DWAppGroupOptions.h"
#import "DWEnvironment.h"
#import "DWGlobalOptions.h"

NS_ASSUME_NONNULL_BEGIN

NSString *const DW_WIPE = @"wipe";
NSString *const DW_WIPE_STRONG = @"wipe!!!";
NSString *const DW_WATCH = @"watch";
NSInteger const DW_PHRASE_LENGTH = 12;

@implementation DWRecoverModel

- (instancetype)initWithAction:(DWRecoverAction)action {
    self = [super init];
    if (self) {
        _action = action;
    }
    return self;
}

- (void)dealloc {
    DSLogVerbose(@"☠️ %@", NSStringFromClass(self.class));
}

- (BOOL)hasWallet {
    return [DWEnvironment sharedInstance].currentChain.hasAWallet;
}

- (BOOL)isWalletEmpty {
    DSChain *chain = [DWEnvironment sharedInstance].currentChain;
    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    // make sure there's no block for 60 mins
    const NSTimeInterval lastBlockTimestamp = chain.lastSyncBlockTimestamp;
    const NSTimeInterval delta = HOUR_TIME_INTERVAL;
    const NSTimeInterval now = [NSDate timeIntervalSince1970];
    const BOOL isSyncedUp = (chain.lastSyncBlockHeight == chain.lastTerminalBlockHeight);
    return (wallet.balance == 0) && (lastBlockTimestamp + delta > now) && isSyncedUp;
}

- (NSString *)cleanupPhrase:(NSString *)phrase {
    return [[DSBIP39Mnemonic sharedInstance] cleanupPhrase:phrase];
}

- (nullable NSString *)normalizePhrase:(NSString *)phrase {
    return [[DSBIP39Mnemonic sharedInstance] normalizePhrase:phrase];
}

- (BOOL)wordIsLocal:(NSString *)word {
    return [[DSBIP39Mnemonic sharedInstance] wordIsLocal:word];
}

- (BOOL)wordIsValid:(NSString *)word {
    return [[DSBIP39Mnemonic sharedInstance] wordIsValid:word];
}

- (BOOL)phraseIsValid:(NSString *)phrase {
    return [[DSBIP39Mnemonic sharedInstance] phraseIsValid:phrase];
}

- (void)wipeWallet {
    [[DWEnvironment sharedInstance] clearAllWallets];

    [[DWGlobalOptions sharedInstance] restoreToDefaults];
    [[DWAppGroupOptions sharedInstance] restoreToDefaults];
}

- (BOOL)canWipeWithPhrase:(NSString *)phrase {
    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    DSChain *chain = [DWEnvironment sharedInstance].currentChain;
    const NSTimeInterval creationDate = [NSDate timeIntervalSince1970];
    DSWallet *testingWallet = [DSWallet standardWalletWithSeedPhrase:phrase
                                                     setCreationDate:creationDate
                                                            forChain:chain
                                                     storeSeedPhrase:NO
                                                         isTransient:YES];
    DSAccount *testingAccount = [testingWallet accountWithNumber:0];
    DSAccount *ourAccount = [DWEnvironment sharedInstance].currentAccount;

    NSData *testingExtended32Data = testingAccount.bip32DerivationPath.extendedPublicKey.publicKeyData;
    NSData *accountExtended32Data = ourAccount.bip32DerivationPath.extendedPublicKey.publicKeyData;

    NSData *testingExtended44Data = testingAccount.bip44DerivationPath.extendedPublicKey.publicKeyData;
    NSData *accountExtended44Data = ourAccount.bip44DerivationPath.extendedPublicKey.publicKeyData;

    return ([testingExtended32Data isEqual:accountExtended32Data] ||
            [testingExtended44Data isEqual:accountExtended44Data] ||
            [phrase isEqual:DW_WIPE]);
}

- (NSString *)wipeAcceptPhrase {
    return NSLocalizedString(@"I accept that I will lose my coins if I no longer possess the recovery phrase", nil);
}

@end

NS_ASSUME_NONNULL_END
