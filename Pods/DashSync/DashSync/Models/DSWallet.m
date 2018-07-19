//
//  DSWallet.m
//  DashSync
//
//  Created by Sam Westrich on 5/20/18.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

#import "DSWallet.h"
#import "DSAccount.h"
#import "DSAuthenticationManager.h"
#import "DSWalletManager.h"
#import "DSBIP39Mnemonic.h"
#import "NSManagedObject+Sugar.h"
#import "NSMutableData+Dash.h"
#import "DSAddressEntity+CoreDataProperties.h"
#import "DSTransactionEntity+CoreDataProperties.h"
#import "DSKey.h"
#import "NSData+Bitcoin.h"


#define SEED_ENTROPY_LENGTH   (128/8)
#define WALLET_CREATION_TIME_KEY   @"WALLET_CREATION_TIME_KEY"
#define AUTH_PRIVKEY_KEY    @"authprivkey"
#define WALLET_MNEMONIC_KEY        @"WALLET_MNEMONIC_KEY"
#define WALLET_MASTER_PUBLIC_KEY        @"WALLET_MASTER_PUBLIC_KEY"

@interface DSWallet()

@property (nonatomic, strong) DSChain * chain;
@property (nonatomic, strong) NSMutableDictionary * mAccounts;
@property (nonatomic, copy) NSString * uniqueID;
@property (nonatomic, assign) NSTimeInterval walletCreationTime;

@end

@implementation DSWallet

+ (DSWallet*)standardWalletWithSeedPhrase:(NSString*)seedPhrase forChain:(DSChain*)chain storeSeedPhrase:(BOOL)store {
    DSAccount * account = [DSAccount accountWithDerivationPaths:[chain standardDerivationPathsForAccountNumber:0]];
    NSString * uniqueId = [self setSeedPhrase:seedPhrase withAccounts:@[account] storeOnKeychain:store]; //make sure we can create the wallet first
    if (!uniqueId) return nil;
    DSWallet * wallet = [[DSWallet alloc] initWithUniqueID:uniqueId andAccount:account forChain:chain storeSeedPhrase:store];
    return wallet;
}

+ (DSWallet*)standardWalletWithRandomSeedPhraseForChain:(DSChain* )chain {
    return [self standardWalletWithSeedPhrase:[self generateRandomSeed] forChain:chain storeSeedPhrase:YES];
}

-(instancetype)initWithChain:(DSChain*)chain {
    if (! (self = [super init])) return nil;
    self.mAccounts = [NSMutableDictionary dictionary];
    self.chain = chain;
    return self;
}

-(instancetype)initWithUniqueID:(NSString*)uniqueID andAccount:(DSAccount*)account forChain:(DSChain*)chain storeSeedPhrase:(BOOL)store {
    if (! (self = [self initWithChain:chain])) return nil;
    self.uniqueID = uniqueID;
    if (store) {
        __weak typeof(self) weakSelf = self;
        self.seedRequestBlock = ^void(NSString *authprompt, uint64_t amount, SeedCompletionBlock seedCompletion) {
            //this happens when we request the seed
            [weakSelf seedWithPrompt:authprompt forAmount:amount completion:seedCompletion];
        };
    }
    if (account) [self addAccount:account]; //this must be last, as adding the account queries the wallet unique ID
    return self;
}

-(instancetype)initWithUniqueID:(NSString*)uniqueID forChain:(DSChain*)chain {
    if (! (self = [self initWithUniqueID:uniqueID andAccount:[DSAccount accountWithDerivationPaths:[chain standardDerivationPathsForAccountNumber:0]] forChain:chain storeSeedPhrase:YES])) return nil;

    return self;
}

+(BOOL)verifyUniqueId:(NSString*)uniqueId {
    NSError * error = nil;
    BOOL hasData = hasKeychainData(uniqueId, &error);
    return (!error && hasData);
}

+ (DSWallet*)walletWithIdentifier:(NSString*)uniqueId forChain:(DSChain*)chain {
    if (![self verifyUniqueId:(NSString*)uniqueId]) return nil;
    DSWallet * wallet = [[DSWallet alloc] initWithChain:chain];
    wallet.uniqueID = uniqueId;
    return wallet;
}


-(NSArray *)accounts {
    return [self.mAccounts allValues];
}

-(void)addAccount:(DSAccount*)account {
    [self.mAccounts setObject:account forKey:@(account.accountNumber)];
    account.wallet = self;
}

- (DSAccount* _Nullable)accountWithNumber:(NSUInteger)accountNumber {
    return [self.mAccounts objectForKey:@(accountNumber)];
}

// MARK: - Unique Identifiers

+(NSString*)mnemonicUniqueIDForUniqueID:(NSString*)uniqueID {
    return [NSString stringWithFormat:@"%@_%@",WALLET_MNEMONIC_KEY,uniqueID];
}

-(NSString*)mnemonicUniqueID {
    return [DSWallet mnemonicUniqueIDForUniqueID:self.uniqueID];
}

+(NSString*)creationTimeUniqueIDForUniqueID:(NSString*)uniqueID {
    return [NSString stringWithFormat:@"%@_%@",WALLET_CREATION_TIME_KEY,uniqueID];
}

-(NSString*)creationTimeUniqueID {
    return [DSWallet creationTimeUniqueIDForUniqueID:self.uniqueID];
}

// MARK: - Seed

// generates a random seed, saves to keychain and returns the associated seedPhrase
+ (NSString *)generateRandomSeed
{
    NSMutableData *entropy = [NSMutableData secureDataWithLength:SEED_ENTROPY_LENGTH];
    
    if (SecRandomCopyBytes(kSecRandomDefault, entropy.length, entropy.mutableBytes) != 0) return nil;
    
    NSString *phrase = [[DSBIP39Mnemonic sharedInstance] encodePhrase:entropy];
    
    return phrase;
}

- (void)seedPhraseAfterAuthentication:(void (^)(NSString * _Nullable))completion
{
    [self seedPhraseWithPrompt:nil completion:completion];
}

-(BOOL)hasSeedPhrase {
    NSError * error = nil;
    BOOL hasSeed = hasKeychainData(self.uniqueID, &error);
    return hasSeed;
}

-(NSTimeInterval)walletCreationTime {
    if (_walletCreationTime) return _walletCreationTime;
    // interval since refrence date, 00:00:00 01/01/01 GMT
    NSData *d = getKeychainData(self.creationTimeUniqueID, nil);
    
    if (d.length == sizeof(NSTimeInterval)) return *(const NSTimeInterval *)d.bytes;
    return ([DSWalletManager sharedInstance].watchOnly) ? 0 : BIP39_CREATION_TIME;
}

+ (NSString*)setSeedPhrase:(NSString *)seedPhrase withAccounts:(NSArray*)accounts storeOnKeychain:(BOOL)storeOnKeychain
{
    if (!seedPhrase) return nil;
    NSString * uniqueID = nil;
    @autoreleasepool { // @autoreleasepool ensures sensitive data will be deallocated immediately
        // we store the wallet creation time on the keychain because keychain data persists even when an app is deleted
        seedPhrase = [[DSBIP39Mnemonic sharedInstance] normalizePhrase:seedPhrase];
        
        NSData * derivedKeyData = (seedPhrase) ?[[DSBIP39Mnemonic sharedInstance]
                                                 deriveKeyFromPhrase:seedPhrase withPassphrase:nil]:nil;
        UInt512 I;
        
        HMAC(&I, SHA512, sizeof(UInt512), BIP32_SEED_KEY, strlen(BIP32_SEED_KEY), derivedKeyData.bytes, derivedKeyData.length);
        
        NSData * publicKey = [DSKey keyWithSecret:*(UInt256 *)&I compressed:YES].publicKey;
        uniqueID = [NSData dataWithUInt256:[publicKey SHA256]].shortHexString; //one way injective function
        if (storeOnKeychain) {
            if (! setKeychainString(seedPhrase, [DSWallet mnemonicUniqueIDForUniqueID:uniqueID], YES) || ! setKeychainData([NSData dataWithBytes:&time length:sizeof(time)], [DSWallet creationTimeUniqueIDForUniqueID:uniqueID], NO)) {
                NSLog(@"error setting wallet seed");
                
                if (seedPhrase) {
                    UIAlertController * alert = [UIAlertController
                                                 alertControllerWithTitle:@"couldn't create wallet"
                                                 message:@"error adding master private key to iOS keychain, make sure app has keychain entitlements"
                                                 preferredStyle:UIAlertControllerStyleAlert];
                    UIAlertAction* okButton = [UIAlertAction
                                               actionWithTitle:@"abort"
                                               style:UIAlertActionStyleCancel
                                               handler:^(UIAlertAction * action) {
                                                   exit(0);
                                               }];
                    [alert addAction:okButton];
                    [[[DSWalletManager sharedInstance] presentingViewController] presentViewController:alert animated:YES completion:nil];
                }
                
                return nil;
            }
            
            for (DSAccount * account in accounts) {
                for (DSDerivationPath * derivationPath in account.derivationPaths) {
                    [derivationPath generateExtendedPublicKeyFromSeed:derivedKeyData storeUnderWalletUniqueId:uniqueID];
                }
            }
        }
    }
    return uniqueID;
}

// authenticates user and returns seed
- (void)seedWithPrompt:(NSString *)authprompt forAmount:(uint64_t)amount completion:(void (^)(NSData * seed))completion
{
    @autoreleasepool {
        BOOL touchid = (self.totalSent + amount < getKeychainInt(SPEND_LIMIT_KEY, nil)) ? YES : NO;
        
        [[DSAuthenticationManager sharedInstance] authenticateWithPrompt:authprompt andTouchId:touchid alertIfLockout:YES completion:^(BOOL authenticated,BOOL cancelled) {
            if (!authenticated) {
                completion(nil);
            } else {
                // BUG: if user manually chooses to enter pin, the touch id spending limit is reset, but the tx being authorized
                // still counts towards the next touch id spending limit
                if (! touchid) setKeychainInt(self.totalSent + amount + [DSWalletManager sharedInstance].spendingLimit, SPEND_LIMIT_KEY, NO);
                completion([[DSBIP39Mnemonic sharedInstance] deriveKeyFromPhrase:getKeychainString(self.mnemonicUniqueID, nil) withPassphrase:nil]);
            }
        }];
        
    }
}

-(NSString*)seedPhraseIfAuthenticated {
    
    if (![DSAuthenticationManager sharedInstance].usesAuthentication || [DSAuthenticationManager sharedInstance].didAuthenticate) {
        return getKeychainString(self.mnemonicUniqueID, nil);
    } else {
        return nil;
    }
}

// authenticates user and returns seedPhrase
- (void)seedPhraseWithPrompt:(NSString *)authprompt completion:(void (^)(NSString * seedPhrase))completion
{
    @autoreleasepool {
        [[DSAuthenticationManager sharedInstance] authenticateWithPrompt:authprompt andTouchId:NO alertIfLockout:YES completion:^(BOOL authenticated,BOOL cancelled) {
            NSString * rSeedPhrase = authenticated?getKeychainString(self.uniqueID, nil):nil;
            completion(rSeedPhrase);
        }];
    }
}

// MARK: - Authentication

// private key for signing authenticated api calls

-(void)authPrivateKey:(void (^ _Nullable)(NSString * _Nullable authKey))completion;
{
    @autoreleasepool {
        self.seedRequestBlock(@"Please authorize", 0, ^(NSData * _Nullable seed) {
            @autoreleasepool {
                NSString *privKey = getKeychainString(AUTH_PRIVKEY_KEY, nil);
                if (! privKey) {
                    privKey = [DSDerivationPath authPrivateKeyFromSeed:seed forChain:self.chain];
                    setKeychainString(privKey, AUTH_PRIVKEY_KEY, NO);
                }
                
                completion(privKey);
            }
        });
    }
}

// MARK: - Combining Accounts

-(uint64_t)balance {
    uint64_t rBalance = 0;
    for (DSAccount * account in self.accounts) {
        rBalance += account.balance;
    }
    return rBalance;
}

-(NSArray *)registerAddressesWithGapLimit:(NSUInteger)gapLimit internal:(BOOL)internal {
    NSMutableArray * mArray = [NSMutableArray array];
    for (DSAccount * account in self.accounts) {
        [mArray addObjectsFromArray:[account registerAddressesWithGapLimit:gapLimit internal:internal]];
    }
    return [mArray copy];
}

- (DSAccount*)accountContainingTransaction:(DSTransaction *)transaction {
    for (DSAccount * account in self.accounts) {
        if ([account containsTransaction:transaction]) return account;
    }
    return FALSE;
}

// all previously generated external addresses
-(NSSet *)allReceiveAddresses {
    NSMutableSet * mSet = [NSMutableSet set];
    for (DSAccount * account in self.accounts) {
        [mSet addObjectsFromArray:[account externalAddresses]];
    }
    return [mSet copy];
}

// all previously generated internal addresses
-(NSSet *)allChangeAddresses {
    NSMutableSet * mSet = [NSMutableSet set];
    for (DSAccount * account in self.accounts) {
        [mSet addObjectsFromArray:[account internalAddresses]];
    }
    return [mSet copy];
}

-(NSArray *) allTransactions {
    NSMutableArray * mArray = [NSMutableArray array];
    for (DSAccount * account in self.accounts) {
        [mArray addObjectsFromArray:account.allTransactions];
    }
    return mArray;
}

- (DSTransaction *)transactionForHash:(UInt256)txHash {
    for (DSAccount * account in self.accounts) {
        DSTransaction * transaction = [account transactionForHash:txHash];
        if (transaction) return transaction;
    }
    return nil;
}

-(NSArray *) unspentOutputs {
    NSMutableArray * mArray = [NSMutableArray array];
    for (DSAccount * account in self.accounts) {
        [mArray addObjectsFromArray:account.unspentOutputs];
    }
    return mArray;
}

// true if the address is controlled by the wallet
- (BOOL)containsAddress:(NSString *)address {
    for (DSAccount * account in self.accounts) {
        if ([account containsAddress:address]) return TRUE;
    }
    return FALSE;
}

// true if the address was previously used as an input or output in any wallet transaction
- (BOOL)addressIsUsed:(NSString *)address {
    for (DSAccount * account in self.accounts) {
        if ([account addressIsUsed:address]) return TRUE;
    }
    return FALSE;
}

// returns the amount received by the wallet from the transaction (total outputs to change and/or receive addresses)
- (uint64_t)amountReceivedFromTransaction:(DSTransaction *)transaction {
    uint64_t received = 0;
    for (DSAccount * account in self.accounts) {
        received += [account amountReceivedFromTransaction:transaction];
    }
    return received;
}

// retuns the amount sent from the wallet by the trasaction (total wallet outputs consumed, change and fee included)
- (uint64_t)amountSentByTransaction:(DSTransaction *)transaction {
    uint64_t sent = 0;
    for (DSAccount * account in self.accounts) {
        sent += [account amountSentByTransaction:transaction];
    }
    return sent;
}

// set the block heights and timestamps for the given transactions, use a height of TX_UNCONFIRMED and timestamp of 0 to
// indicate a transaction and it's dependents should remain marked as unverified (not 0-conf safe)
- (NSArray *)setBlockHeight:(int32_t)height andTimestamp:(NSTimeInterval)timestamp forTxHashes:(NSArray *)txHashes
{
    NSMutableArray *updated = [NSMutableArray array];
    
    for (DSAccount * account in self.accounts) {
        NSArray * fromAccount = [account setBlockHeight:height andTimestamp:timestamp forTxHashes:txHashes];
        if (fromAccount)
            [updated addObjectsFromArray:fromAccount];
    }
    return updated;
}

- (DSAccount *)accountForTransactionHash:(UInt256)txHash transaction:(DSTransaction **)transaction {
    for (DSAccount * account in self.accounts) {
        DSTransaction * lTransaction = [account transactionForHash:txHash];
        if (lTransaction) {
            if (transaction) *transaction = lTransaction;
            return account;
        }
    }
    return nil;
}

- (BOOL)transactionIsValid:(DSTransaction * _Nonnull)transaction {
    for (DSAccount * account in self.accounts) {
        if (![account transactionIsValid:transaction]) return FALSE;
    }
    return TRUE;
}

// MARK: - Seed

- (NSString *)serializedPrivateMasterFromSeed:(NSData *)seed
{
    if (! seed) return nil;
    
    UInt512 I;
    
    HMAC(&I, SHA512, sizeof(UInt512), BIP32_SEED_KEY, strlen(BIP32_SEED_KEY), seed.bytes, seed.length);
    
    UInt256 secret = *(UInt256 *)&I, chain = *(UInt256 *)&I.u8[sizeof(UInt256)];
    
    return serialize(0, 0, 0, chain, [NSData dataWithBytes:&secret length:sizeof(secret)],[self.chain isMainnet]);
}

- (void)wipeBlockchainInfo {
    for (DSAccount * account in self.accounts) {
        [account wipeBlockchainInfo];
    }
}

@end
