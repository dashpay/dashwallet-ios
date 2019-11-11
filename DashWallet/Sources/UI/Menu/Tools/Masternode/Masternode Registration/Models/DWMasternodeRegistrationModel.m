//
//  Created by Sam Westrich
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

#import "DWMasternodeRegistrationModel.h"
#include <arpa/inet.h>

@interface DWMasternodeRegistrationModel ()

@property (nonatomic, strong) DSWallet *wallet;
@property (nonatomic, strong) DSAccount *account;

@property (nonatomic, strong) DSTransaction *collateralTransaction;
@property (nonatomic, strong) DSProviderRegistrationTransaction *providerRegistrationTransaction;

@property (readonly, nonatomic, strong) DSAuthenticationKeysDerivationPath *ownerDerivationPath;
@property (readonly, nonatomic, strong) DSAuthenticationKeysDerivationPath *votingDerivationPath;
@property (readonly, nonatomic, strong) DSAuthenticationKeysDerivationPath *operatorDerivationPath;

@end

@implementation DWMasternodeRegistrationModel

- (instancetype)initForAccount:(DSAccount *)account {
    self = [super init];
    if (self) {
        _wallet = account.wallet;
        _account = account;
        _port = _wallet.chain.standardPort;
        DSDerivationPathFactory *factory = [DSDerivationPathFactory sharedInstance];
        _ownerDerivationPath = [factory providerOwnerKeysDerivationPathForWallet:_wallet];
        _votingDerivationPath = [factory providerVotingKeysDerivationPathForWallet:_wallet];
        _operatorDerivationPath = [factory providerOperatorKeysDerivationPathForWallet:_wallet];
    }
    return self;
}

- (void)setOperatorKeyIndex:(uint32_t)operatorKeyIndex {
    _operatorKeyIndex = operatorKeyIndex;
    @autoreleasepool {
        NSData *seed = [[DSBIP39Mnemonic sharedInstance] deriveKeyFromPhrase:_wallet.seedPhraseIfAuthenticated
                                                              withPassphrase:nil];
        _operatorKey = (DSBLSKey *)[self.operatorDerivationPath privateKeyAtIndex:operatorKeyIndex fromSeed:seed];
    }
}

- (void)setOwnerKeyIndex:(uint32_t)ownerKeyIndex {
    _ownerKeyIndex = ownerKeyIndex;
    @autoreleasepool {
        NSData *seed = [[DSBIP39Mnemonic sharedInstance] deriveKeyFromPhrase:_wallet.seedPhraseIfAuthenticated
                                                              withPassphrase:nil];
        _ownerKey = (DSECDSAKey *)[self.ownerDerivationPath privateKeyAtIndex:ownerKeyIndex fromSeed:seed];
    }
}

- (void)setVotingKeyIndex:(uint32_t)votingKeyIndex {
    _votingKeyIndex = votingKeyIndex;
    @autoreleasepool {
        NSData *seed = [[DSBIP39Mnemonic sharedInstance] deriveKeyFromPhrase:_wallet.seedPhraseIfAuthenticated
                                                              withPassphrase:nil];
        _votingKey = (DSECDSAKey *)[self.votingDerivationPath privateKeyAtIndex:votingKeyIndex fromSeed:seed];
    }
}

- (void)setOperatorKey:(DSBLSKey *)operatorKey {
    _operatorKey = operatorKey;
    NSString *address = [operatorKey addressForChain:_wallet.chain];
    _operatorKeyIndex = [self.operatorDerivationPath indexOfKnownAddress:address];
}

- (void)setOwnerKey:(DSECDSAKey *)ownerKey {
    _ownerKey = ownerKey;
    NSString *address = [ownerKey addressForChain:_wallet.chain];
    _ownerKeyIndex = [self.ownerDerivationPath indexOfKnownAddress:address];
}

- (void)setVotingKey:(DSECDSAKey *)votingKey {
    _votingKey = votingKey;
    NSString *address = [votingKey addressForChain:_wallet.chain];
    _votingKeyIndex = [self.votingDerivationPath indexOfKnownAddress:address];
}

- (void)setIpAddressFromString:(NSString *)ipAddressString {
    UInt128 ipAddress = {.u32 = {0, 0, CFSwapInt32HostToBig(0xffff), 0}};
    struct in_addr addrV4;
    if (inet_aton([ipAddressString UTF8String], &addrV4) != 0) {
        uint32_t ip = ntohl(addrV4.s_addr);
        ipAddress.u32[3] = CFSwapInt32HostToBig(ip);
        DSDLog(@"%08x", ip);
    }
    self.ipAddress = ipAddress;
}

- (void)lookupIndexesForCollateralHash:(UInt256)collateralHash completion:(void (^_Nullable)(DSTransaction *transaction, NSIndexSet *indexSet, NSError *error))completion {
    [[DSInsightManager sharedInstance] queryInsightForTransactionWithHash:self.collateral.hash
                                                                  onChain:self.account.wallet.chain
                                                               completion:^(DSTransaction *transaction, NSError *error) {
                                                                   if (error) {
                                                                       dispatch_async(dispatch_get_main_queue(), ^{
                                                                           completion(transaction, nil, [NSError errorWithDomain:@"Dashwallet" code:500 userInfo:@{NSLocalizedDescriptionKey : NSLocalizedString(@"Network error", nil)}]);
                                                                       });
                                                                       return;
                                                                   }
                                                                   if (!transaction) {
                                                                       dispatch_async(dispatch_get_main_queue(), ^{
                                                                           completion(nil, nil, [NSError errorWithDomain:@"Dashwallet" code:500 userInfo:@{NSLocalizedDescriptionKey : NSLocalizedString(@"Transaction could not be found", nil)}]);
                                                                       });
                                                                       return;
                                                                   }
                                                                   NSIndexSet *indexSet = [[transaction outputAmounts] indexesOfObjectsPassingTest:^BOOL(id _Nonnull obj, NSUInteger idx, BOOL *_Nonnull stop) {
                                                                       if ([obj isEqual:@(MASTERNODE_COST)])
                                                                           return TRUE;
                                                                       return FALSE;
                                                                   }];
                                                                   if ([indexSet count]) {
                                                                       dispatch_async(dispatch_get_main_queue(), ^{
                                                                           completion(transaction, indexSet, nil);
                                                                       });
                                                                   }
                                                                   else {
                                                                       dispatch_async(dispatch_get_main_queue(), ^{
                                                                           completion(transaction, nil, nil);
                                                                       });
                                                                   }
                                                               }];
}

- (void)findCollateralTransactionWithCompletion:(void (^_Nullable)(NSError *error))completion {
    if (self.collateralTransaction) {
        if (completion) {
            completion(nil);
        }
        return;
    }
    if (!dsutxo_is_zero(self.collateral)) {
        [self lookupIndexesForCollateralHash:self.collateral.hash
                                  completion:^(DSTransaction *_Nonnull transaction, NSIndexSet *_Nonnull indexSet, NSError *_Nonnull error) {
                                      if (error) {
                                          if (completion) {
                                              completion(error);
                                          }
                                          return;
                                      }
                                      if ([indexSet containsIndex:self.collateral.n]) {
                                          self.collateralTransaction = transaction;
                                          if (completion) {
                                              completion(nil);
                                          }
                                      }
                                      else {
                                          if (completion) {
                                              completion([NSError errorWithDomain:@"Dashwallet" code:500 userInfo:@{NSLocalizedDescriptionKey : NSLocalizedString(@"Incorrect collateral", nil)}]);
                                          }
                                      }
                                  }];
    }
}

- (void)registerMasternode:(id)sender requestsPayloadSigning:(void (^_Nullable)(void))payloadSigningRequest completion:(void (^_Nullable)(NSError *error))completion {


    DSMasternodeManager *masternodeManager = self.wallet.chain.chainManager.masternodeManager;

    DSLocalMasternode *masternode = [masternodeManager createNewMasternodeWithIPAddress:self.ipAddress onPort:self.port inFundsWallet:self.wallet fundsWalletIndex:UINT32_MAX inOperatorWallet:self.wallet operatorWalletIndex:self.operatorKeyIndex operatorPublicKey:self.operatorKey inOwnerWallet:self.wallet ownerWalletIndex:self.ownerKeyIndex ownerPrivateKey:self.ownerKey inVotingWallet:self.wallet votingWalletIndex:self.votingKeyIndex votingKey:self.votingKey];

    //    NSString *payoutAddress = [self.payToAddressTableViewCell.valueTextField.text isValidDashAddressOnChain:self.chain] ? self.payToAddressTableViewCell.textLabel.text : self.account.receiveAddress;


    //    DSUTXO collateral = DSUTXO_ZERO;
    //    UInt256 nonReversedCollateralHash = UINT256_ZERO;
    //    NSString *collateralTransactionHash = self.collateralTransactionTableViewCell.valueTextField.text;
    //    if (![collateralTransactionHash isEqual:@""]) {
    //        NSData *collateralTransactionHashData = [collateralTransactionHash hexToData];
    //        if (collateralTransactionHashData.length != 32)
    //            return;
    //        collateral.hash = collateralTransactionHashData.reverse.UInt256;
    //
    //        nonReversedCollateralHash = collateralTransactionHashData.UInt256;
    //        collateral.n = [self.collateralIndexTableViewCell.valueTextField.text integerValue];
    //    }


    [masternode registrationTransactionFundedByAccount:self.account
                                             toAddress:self.payoutAddress
                                        withCollateral:self.collateral
                                            completion:^(DSProviderRegistrationTransaction *_Nonnull providerRegistrationTransaction) {
                                                if (providerRegistrationTransaction) {
                                                    self.providerRegistrationTransaction = providerRegistrationTransaction;
                                                    if (dsutxo_is_zero(self.collateral)) {
                                                        [self signTransactionInputsWithCompletion:completion];
                                                    }
                                                    else {
                                                        payloadSigningRequest();
                                                    }
                                                }
                                                else {
                                                    if (completion) {
                                                        completion([NSError errorWithDomain:@"Dashwallet" code:500 userInfo:@{NSLocalizedDescriptionKey : NSLocalizedString(@"Unable to create ProviderRegistrationTransaction.", nil)}]);
                                                    }
                                                }
                                            }];
}

- (void)signTransactionInputsWithCompletion:(void (^_Nullable)(NSError *error))completion {
    [self.account signTransaction:self.providerRegistrationTransaction
                       withPrompt:NSLocalizedString(@"Would you like to register this masternode?", nil)
                       completion:^(BOOL signedTransaction, BOOL cancelled) {
                           if (signedTransaction) {
                               [self.account.wallet.chain.chainManager.transactionManager publishTransaction:self.providerRegistrationTransaction
                                                                                                  completion:^(NSError *_Nullable error) {
                                                                                                      if (completion) {
                                                                                                          completion(error);
                                                                                                      }
                                                                                                  }];
                           }
                           else {
                               if (completion) {
                                   completion([NSError errorWithDomain:@"Dashwallet" code:500 userInfo:@{NSLocalizedDescriptionKey : NSLocalizedString(@"Transaction was not signed.", nil)}]);
                               }
                           }
                       }];
}


@end
