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

#import <DashSync/DashSync.h>

#import "DWAppGroupOptions.h"
#import "DWEnvironment.h"
#import "DWGlobalOptions.h"

NS_ASSUME_NONNULL_BEGIN

NSString *const DW_WIPE = @"wipe";
NSString *const DW_WATCH = @"watch";
NSInteger const DW_PHRASE_LENGTH = 12;

@interface DWRecoverModel ()

@property (readonly, nonatomic, strong) NSCharacterSet *invalidCharacterSet;

@end

@implementation DWRecoverModel

- (instancetype)init {
    self = [super init];
    if (self) {
        NSMutableCharacterSet *set = [NSMutableCharacterSet letterCharacterSet];
        [set formUnionWithCharacterSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        _invalidCharacterSet = set.invertedSet;
    }
    return self;
}

- (BOOL)hasWallet {
    return [DWEnvironment sharedInstance].currentChain.hasAWallet;
}

- (BOOL)isWalletEmpty {
    DSChain *chain = [DWEnvironment sharedInstance].currentChain;
    DSWallet *wallet = [DWEnvironment sharedInstance].currentWallet;
    const NSTimeInterval lastBlockTimestamp = [chain timestampForBlockHeight:chain.lastBlockHeight];
    const NSTimeInterval delta = 60 * 2.5 * 5;
    const NSTimeInterval now = [NSDate timeIntervalSince1970];
    return (wallet.balance == 0) && (lastBlockTimestamp + delta > now);
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

- (void)recoverWalletWithPhrase:(NSString *)phrase {
    DSChain *chain = [[DWEnvironment sharedInstance] currentChain];
    NSParameterAssert(chain);
    [DSWallet standardWalletWithSeedPhrase:phrase
                           setCreationDate:BIP39_WALLET_UNKNOWN_CREATION_TIME
                                  forChain:chain
                           storeSeedPhrase:YES
                               isTransient:NO];

    // START_SYNC_ENTRY_POINT
    [[DWEnvironment sharedInstance].currentChainManager.peerManager connect];
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
    DSAccount *testingAccount = [wallet accountWithNumber:0];
    DSAccount *ourAccount = [DWEnvironment sharedInstance].currentAccount;

    return ([testingAccount.bip32DerivationPath.extendedPublicKey
                isEqual:ourAccount.bip32DerivationPath.extendedPublicKey] ||
            [testingAccount.bip44DerivationPath.extendedPublicKey
                isEqual:ourAccount.bip44DerivationPath.extendedPublicKey] ||
            [phrase isEqual:DW_WIPE]);
}

- (NSString *)wipeAcceptPhrase {
    return NSLocalizedString(@"I accept that I will lose my coins if I no longer possess the recovery phrase", nil);
}

@end

NS_ASSUME_NONNULL_END
