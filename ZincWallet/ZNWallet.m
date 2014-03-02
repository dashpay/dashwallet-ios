//
//  ZNWallet.m
//  ZincWallet
//
//  Created by Aaron Voisine on 5/12/13.
//  Copyright (c) 2013 Aaron Voisine <voisine@gmail.com>
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

#import "ZNWallet.h"
#import "ZNKey.h"
#import "ZNPeer.h"
#import "ZNAddressEntity.h"
#import "ZNTransaction.h"
#import "ZNTransactionEntity.h"
#import "ZNTxInputEntity.h"
#import "ZNTxOutputEntity.h"
#import "ZNMnemonic.h"
#import "ZNZincMnemonic.h"
#import "ZNKeySequence.h"
#import "ZNBIP32Sequence.h"
#import "NSData+Hash.h"
#import "NSData+Bitcoin.h"
#import "NSMutableData+Bitcoin.h"
#import "NSString+Base58.h"
#import "NSManagedObject+Utils.h"

#define BTC           @"\xC9\x83"     // capital B with stroke (utf-8)
#define CURRENCY_SIGN @"\xC2\xA4"     // generic currency sign (utf-8)
#define NBSP          @"\xC2\xA0"     // no-break space (utf-8)
#define NARROW_NBSP   @"\xE2\x80\xAF" // narrow no-break space (utf-8)

#define LOCAL_CURRENCY_SYMBOL_KEY @"LOCAL_CURRENCY_SYMBOL"
#define LOCAL_CURRENCY_CODE_KEY   @"LOCAL_CURRENCY_CODE"
#define LOCAL_CURRENCY_PRICE_KEY  @"LOCAL_CURRENCY_PRICE"
#define SEED_KEY                  @"seed"
#define CREATION_TIME_KEY         @"creationtime"

#define SEC_ATTR_SERVICE @"cc.zinc.zincwallet"
#define DEFAULT_CURRENCY_PRICE 100000.0

#define BASE_URL    @"https://blockchain.info"
#define UNSPENT_URL BASE_URL "/unspent?active="
#define ADDRESS_URL BASE_URL "/multiaddr?active="

static BOOL setKeychainData(NSData *data, NSString *key)
{
    if (! key) return NO;
    
    NSDictionary *query = @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
                            (__bridge id)kSecAttrService:SEC_ATTR_SERVICE,
                            (__bridge id)kSecAttrAccount:key,
                            (__bridge id)kSecReturnData:(__bridge id)kCFBooleanTrue};
    
    SecItemDelete((__bridge CFDictionaryRef)query);
    
    if (! data) return YES;
    
    NSDictionary *item = @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
                           (__bridge id)kSecAttrService:SEC_ATTR_SERVICE,
                           (__bridge id)kSecAttrAccount:key,
                           (__bridge id)kSecAttrAccessible:(__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                           (__bridge id)kSecValueData:data};
    
    return (SecItemAdd((__bridge CFDictionaryRef)item, NULL) == noErr) ? YES : NO;
}

static NSData *getKeychainData(NSString *key)
{
    NSDictionary *query = @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
                            (__bridge id)kSecAttrService:SEC_ATTR_SERVICE,
                            (__bridge id)kSecAttrAccount:key,
                            (__bridge id)kSecReturnData:(__bridge id)kCFBooleanTrue};
    CFDataRef result = nil;
    
    if (SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&result) != noErr) {
        NSLog(@"SecItemCopyMatching error");
        return nil;
    }
    
    return CFBridgingRelease(result);
}

static NSData *txOutput(NSData *txHash, uint32_t n)
{
    NSMutableData *d = [NSMutableData dataWithCapacity:CC_SHA256_DIGEST_LENGTH + sizeof(uint32_t)];

    [d appendData:txHash];
    [d appendUInt32:n];
    return d;
}

//TODO: separate out keychain for easier testing

@interface ZNWallet ()

@property (nonatomic, strong) id<ZNKeySequence> sequence;
@property (nonatomic, strong) NSData *mpk;
@property (nonatomic, strong) NSMutableArray *internalAddresses, *externalAddresses;
@property (nonatomic, strong) NSMutableSet *allAddresses, *usedAddresses, *spentOutputs, *invalidTx;
@property (nonatomic, strong) NSMutableOrderedSet *transactions, *utxos;
@property (nonatomic, strong) NSMutableDictionary *allTx;
@property (nonatomic, assign) uint64_t balance;

@end

@implementation ZNWallet

+ (instancetype)sharedInstance
{
    static id singleton = nil;
    static dispatch_once_t onceToken = 0;
    
    dispatch_once(&onceToken, ^{
        singleton = [self new];
    });

    return singleton;
}

- (instancetype)init
{
    if (! (self = [super init])) return nil;

    [NSManagedObject setConcurrencyType:NSPrivateQueueConcurrencyType];

    self.sequence = [ZNBIP32Sequence new];
    self.format = [NSNumberFormatter new];
    self.format.lenient = YES;
    self.format.numberStyle = NSNumberFormatterCurrencyStyle;
    self.format.minimumFractionDigits = 0;
    self.format.negativeFormat =
        [self.format.positiveFormat stringByReplacingOccurrencesOfString:CURRENCY_SIGN withString:CURRENCY_SIGN @"-"];
    //self.format.currencySymbol = @"m" BTC NARROW_NBSP;
    //self.format.maximumFractionDigits = 5;
    //self.format.maximum = @210000000009.0;
    self.format.currencySymbol = BTC NARROW_NBSP;
    self.format.maximumFractionDigits = 8;
    // for reasons both mysterious and inscrutable, 210,000,009 is the smallest value of format.maximum that will allow
    // the user to input a value of 21,000,000
    self.format.maximum = @210000009.0;

    self.allTx = [NSMutableDictionary dictionary];
    self.transactions = [NSMutableOrderedSet orderedSet];
    self.internalAddresses = [NSMutableArray array];
    self.externalAddresses = [NSMutableArray array];
    self.allAddresses = [NSMutableSet set];
    self.usedAddresses = [NSMutableSet set];
    self.invalidTx = [NSMutableSet set];
    self.spentOutputs = [NSMutableSet set];
    self.utxos = [NSMutableOrderedSet orderedSet];

    [[NSManagedObject context] performBlockAndWait:^{
        NSFetchRequest *req = [ZNAddressEntity fetchRequest];

        req.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"index" ascending:YES]];
        req.predicate = [NSPredicate predicateWithFormat:@"internal == YES"];
        [self.internalAddresses setArray:[[ZNAddressEntity fetchObjects:req] valueForKey:@"address"]];
        req.predicate = [NSPredicate predicateWithFormat:@"internal == NO"];
        [self.externalAddresses setArray:[[ZNAddressEntity fetchObjects:req] valueForKey:@"address"]];

        [self.allAddresses addObjectsFromArray:self.internalAddresses];
        [self.allAddresses addObjectsFromArray:self.externalAddresses];

        for (ZNTransactionEntity *e in [ZNTransactionEntity allObjects]) {
            ZNTransaction *tx = e.transaction;

            self.allTx[tx.txHash] = tx;
            [self.transactions addObject:tx];
            [self.usedAddresses addObjectsFromArray:tx.outputAddresses];
        }
    }];

    [self sortTransactions];
    [self updateBalance];
    [self updateExchangeRate];

    return self;
}

- (void)dealloc
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

- (NSData *)seed
{
    NSData *seed = getKeychainData(SEED_KEY);
    
    if (seed.length != SEQUENCE_SEED_LENGTH) {
        self.seed = nil;
        return nil;
    }
    
    return seed;
}

- (void)setSeed:(NSData *)seed
{
    if (seed && [self.seed isEqual:seed]) return;
    
    self.mpk = nil; // reset master public key
    [self.allTx removeAllObjects];
    [self.transactions removeAllObjects];
    [self.internalAddresses removeAllObjects];
    [self.externalAddresses removeAllObjects];
    [self.allAddresses removeAllObjects];
    [self.usedAddresses removeAllObjects];
    [self.invalidTx removeAllObjects];
    [self.spentOutputs removeAllObjects];
    [self.utxos removeAllObjects];
    self.balance = 0;

    [[NSManagedObject context] performBlockAndWait:^{
        [ZNAddressEntity deleteObjects:[ZNAddressEntity allObjects]];
        [ZNTransactionEntity deleteObjects:[ZNTransactionEntity allObjects]];
        [NSManagedObject saveContext];
    }];

    setKeychainData(nil, CREATION_TIME_KEY);
    setKeychainData(seed, SEED_KEY);

    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:ZNWalletSeedChangedNotification object:nil];
    });
}

- (NSString *)seedPhrase
{
    id<ZNMnemonic> mnemonic = [ZNZincMnemonic sharedInstance];

    return [mnemonic encodePhrase:self.seed];
}

- (void)setSeedPhrase:(NSString *)seedPhrase
{
    id<ZNMnemonic> mnemonic = [ZNZincMnemonic sharedInstance];

    self.seed = [mnemonic decodePhrase:seedPhrase];
}

- (void)generateRandomSeed
{
    NSMutableData *seed = CFBridgingRelease(CFDataCreateMutable(SecureAllocator(), SEQUENCE_SEED_LENGTH));
    NSTimeInterval time = [NSDate timeIntervalSinceReferenceDate];
    
    seed.length = SEQUENCE_SEED_LENGTH;
    SecRandomCopyBytes(kSecRandomDefault, seed.length, seed.mutableBytes);

    self.seed = seed;
    
    // we store the wallet creation time on the keychain because keychain data persists even when an app is deleted
    setKeychainData([NSData dataWithBytes:&time length:sizeof(time)], CREATION_TIME_KEY);
}

- (NSData *)masterPublicKey
{
    if (self.mpk) return self.mpk;
    
    self.mpk = [self.sequence masterPublicKeyFromSeed:self.seed];
    return self.mpk;
}

- (NSTimeInterval)seedCreationTime
{
    NSData *d = getKeychainData(CREATION_TIME_KEY);
    
    return (d.length < sizeof(NSTimeInterval)) ? BITCOIN_REFERENCE_BLOCK_TIME : *(NSTimeInterval *)d.bytes;
}

// Wallets are composed of chains of addresses. Each chain is traversed until a gap of a certain number of addresses is
// found that haven't been used in any transactions. This method returns an array of <gapLimit> unused addresses
// following the last used address in the chain. The internal chain is used for change addresses and the external chain
// for receive addresses.
- (NSArray *)addressesWithGapLimit:(NSUInteger)gapLimit internal:(BOOL)internal
{
    NSMutableArray *a = [NSMutableArray arrayWithArray:internal ? self.internalAddresses : self.externalAddresses];
    NSUInteger i = a.count;

    // keep only the trailing contiguous block of addresses with no transactions
    while (i > 0 && ! [self.usedAddresses containsObject:a[i - 1]]) {
        i--;
    }

    if (i > 0) [a removeObjectsInRange:NSMakeRange(0, i)];
    if (a.count >= gapLimit) return [a subarrayWithRange:NSMakeRange(0, gapLimit)];

    @synchronized(self) {
        [a setArray:internal ? self.internalAddresses : self.externalAddresses];
        i = a.count;

        unsigned n = i;

        // keep only the trailing contiguous block of addresses with no transactions
        while (i > 0 && ! [self.usedAddresses containsObject:a[i - 1]]) {
            i--;
        }

        if (i > 0) [a removeObjectsInRange:NSMakeRange(0, i)];
        if (a.count >= gapLimit) return [a subarrayWithRange:NSMakeRange(0, gapLimit)];

        while (a.count < gapLimit) { // generate new addresses up to gapLimit
            NSData *pubKey = [self.sequence publicKey:n internal:internal masterPublicKey:self.masterPublicKey];
            NSString *addr = [[ZNKey keyWithPublicKey:pubKey] address];
        
            if (! addr) {
                NSLog(@"error generating keys");
                return nil;
            }

            [[ZNAddressEntity context] performBlock:^{ // store new address in core data
                ZNAddressEntity *e = [ZNAddressEntity managedObject];

                e.address = addr;
                e.index = n;
                e.internal = internal;
            }];

            [self.allAddresses addObject:addr];
            [internal ? self.internalAddresses : self.externalAddresses addObject:addr];
            [a addObject:addr];
            n++;
        }
    
        return a;
    }
}

// this sorts transactions by block height in descending order, and makes a best attempt at ordering transactions within
// each block, however correct transaction ordering cannot be relied upon for determining wallet balance or UTXO set
- (void)sortTransactions
{
    [self.transactions sortUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        if ([obj1 blockHeight] > [obj2 blockHeight]) return NSOrderedAscending;
        if ([obj1 blockHeight] < [obj2 blockHeight]) return NSOrderedDescending;
        if ([[obj1 inputHashes] containsObject:[obj2 txHash]]) return NSOrderedDescending;
        if ([[obj2 inputHashes] containsObject:[obj1 txHash]]) return NSOrderedAscending;
        return NSOrderedSame;
    }];
}

- (void)updateBalance
{
    uint64_t balance = 0;
    NSMutableOrderedSet *utxos = [NSMutableOrderedSet orderedSet];
    NSMutableSet *spentOutputs = [NSMutableSet set], *invalidTx = [NSMutableSet set];

    for (ZNTransaction *tx in [self.transactions reverseObjectEnumerator]) {
        NSMutableSet *spent = [NSMutableSet set];
        uint32_t i = 0, n = 0;

        for (NSData *hash in tx.inputHashes) {
            n = [tx.inputIndexes[i++] unsignedIntValue];
            [spent addObject:txOutput(hash, n)];
        }

        // check if any inputs are invalid or already spent
        if (tx.blockHeight == TX_UNCONFIRMED &&
            ([spent intersectsSet:spentOutputs] || [[NSSet setWithArray:tx.inputHashes] intersectsSet:invalidTx])) {
            [invalidTx addObject:tx.txHash];
            continue;
        }

        [spentOutputs unionSet:spent]; // add inputs to spent output set
        n = 0;

        for (NSString *address in tx.outputAddresses) { // add outputs to UTXO set
            if ([self containsAddress:address]) {
                [utxos addObject:txOutput(tx.txHash, n)];
                balance += [tx.outputAmounts[n] unsignedLongLongValue];
            }
            n++;
        }

        // transaction ordering is not guaranteed, so check the entire UTXO set against the entire spent output set
        [spent setSet:[utxos set]];
        [spent intersectSet:spentOutputs];
        
        for (NSData *o in spent) { // remove any spent outputs from UTXO set
            ZNTransaction *transaction = self.allTx[[o hashAtOffset:0]];
            uint32_t n = [o UInt32AtOffset:CC_SHA256_DIGEST_LENGTH];
            
            [utxos removeObject:o];
            balance -= [transaction.outputAmounts[n] unsignedLongLongValue];
        }
    }

    if (balance != self.balance) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:ZNWalletBalanceChangedNotification object:nil];
        });
    }

    self.invalidTx = invalidTx;
    self.spentOutputs = spentOutputs;
    self.utxos = utxos;
    self.balance = balance;
}

- (void)updateExchangeRate
{
    NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:ADDRESS_URL]
                         cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:10.0];

    [NSURLConnection sendAsynchronousRequest:req queue:[NSOperationQueue currentQueue]
    completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
        if (connectionError) {
            NSLog(@"%@", connectionError);
            return;
        }

        NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
        NSError *error = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];

        if (error || ! [json isKindOfClass:[NSDictionary class]] ||
            ! [json[@"info"] isKindOfClass:[NSDictionary class]] ||
            ! [json[@"info"][@"symbol_local"] isKindOfClass:[NSDictionary class]] ||
            ! [json[@"info"][@"symbol_local"][@"symbol"] isKindOfClass:[NSString class]] ||
            ! [json[@"info"][@"symbol_local"][@"code"] isKindOfClass:[NSString class]] ||
            ! [json[@"info"][@"symbol_local"][@"conversion"] isKindOfClass:[NSNumber class]]) {
            NSLog(@"unexpected response from blockchain.info:\n%@",
                  [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
            return;
        }

        [defs setObject:json[@"info"][@"symbol_local"][@"symbol"] forKey:LOCAL_CURRENCY_SYMBOL_KEY];
        [defs setObject:json[@"info"][@"symbol_local"][@"code"] forKey:LOCAL_CURRENCY_CODE_KEY];
        [defs setObject:json[@"info"][@"symbol_local"][@"conversion"] forKey:LOCAL_CURRENCY_PRICE_KEY];
        [defs synchronize];
        NSLog(@"exchange rate updated to %@/%@", [self localCurrencyStringForAmount:SATOSHIS],
              [self stringForAmount:SATOSHIS]);

        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:ZNWalletBalanceChangedNotification object:nil];
        });
    }];

    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateExchangeRate) object:nil];
    [self performSelector:@selector(updateExchangeRate) withObject:nil afterDelay:60.0];
}

#pragma mark - wallet info

- (NSString *)receiveAddress
{
    return [self addressesWithGapLimit:1 internal:NO].lastObject;
}

- (NSString *)changeAddress
{
    return [self addressesWithGapLimit:1 internal:YES].lastObject;
}

- (NSSet *)addresses
{
    return self.allAddresses;
}

- (NSArray *)unspentOutputs
{
    return [self.utxos array];
}

- (NSArray *)recentTransactions
{
    return [self.transactions array];
}

- (BOOL)containsAddress:(NSString *)address
{
    return (address && [self.allAddresses containsObject:address]) ? YES : NO;
}

#pragma mark - transactions

// returns an unsigned transaction that sends the specified amount from the wallet to the given address
- (ZNTransaction *)transactionFor:(uint64_t)amount to:(NSString *)address withFee:(BOOL)fee
{
    __block uint64_t balance = 0, standardFee = 0;
    ZNTransaction *transaction = [ZNTransaction new];

    [transaction addOutputAddress:address amount:amount];

    //TODO: implement P2SH transactions
    //TODO: make sure transaction is less than TX_MAX_SIZE
    //TODO: don't use coin generation inputs less than 100 blocks deep
    //TODO: we should use up all inputs tied to any particular address, otherwise we reveal the public key for an
    //      address that still has remaining funds
    for (NSData *o in self.utxos) {
        ZNTransaction *tx = self.allTx[[o hashAtOffset:0]];
        uint32_t n = [o UInt32AtOffset:CC_SHA256_DIGEST_LENGTH];

        if (! tx) continue;

        [transaction addInputHash:tx.txHash index:n script:tx.outputScripts[n]];
        balance += [tx.outputAmounts[n] unsignedLongLongValue];
            
        // assume we will be adding a change output (additional 34 bytes)
        //TODO: calculate the median of the lowest fee-per-kb that made it into the previous 144 blocks (24hrs)
        //NOTE: consider feedback effects if everyone uses the same algorithm to calculate fees, maybe add noise
        if (fee) standardFee = ((tx.size + 34 + 999)/1000)*TX_FEE_PER_KB;
            
        if (balance == amount + standardFee || balance >= amount + standardFee + TX_MIN_OUTPUT_AMOUNT) break;
    }
    
    if (balance < amount + standardFee) { // insufficent funds
        NSLog(@"Insufficient funds. %llu is less than transaction amount:%llu", balance, amount + standardFee);
        return nil;
    }
    
    //TODO: randomly swap order of outputs so the change address isn't publicy known
    if (balance - (amount + standardFee) >= TX_MIN_OUTPUT_AMOUNT) {
        [transaction addOutputAddress:self.changeAddress amount:balance - (amount + standardFee)];
    }
    
    return transaction;
}

// sign any inputs in given transaction that can be signed using private keys from the wallet
- (BOOL)signTransaction:(ZNTransaction *)transaction
{
    NSData *seed = self.seed;
    NSMutableArray *pkeys = [NSMutableArray array];
    NSMutableOrderedSet *externalIndexes = [NSMutableOrderedSet orderedSet],
                        *internalIndexes = [NSMutableOrderedSet orderedSet];

    for (NSString *addr in transaction.inputAddresses) {
        [internalIndexes addObject:@([self.internalAddresses indexOfObject:addr])];
        [externalIndexes addObject:@([self.externalAddresses indexOfObject:addr])];
    }

    [internalIndexes removeObject:@(NSNotFound)];
    [externalIndexes removeObject:@(NSNotFound)];
    [pkeys addObjectsFromArray:[self.sequence privateKeys:[externalIndexes array] internal:NO fromSeed:seed]];
    [pkeys addObjectsFromArray:[self.sequence privateKeys:[internalIndexes array] internal:YES fromSeed:seed]];

    [transaction signWithPrivateKeys:pkeys];
    
    seed = nil;
    pkeys = nil;
    
    return [transaction isSigned];
}

// given a private key, queries blockchain for unspent outputs and calls the completion block with a signed transaction
// that will sweep the balance into the wallet (doesn't publish the tx)
//TODO: XXXX test this
- (void)sweepPrivateKey:(NSString *)privKey withFee:(BOOL)fee
completion:(void (^)(ZNTransaction *tx, NSError *error))completion
{
    //TODO: add support for BIP38 password encrypted private keys
    NSString *address = [[ZNKey keyWithPrivateKey:privKey] address];

    if (! completion) return;

    if (! address) {
        completion(nil, [NSError errorWithDomain:@"ZincWallet" code:187
                         userInfo:@{NSLocalizedDescriptionKey:@"not a valid private key"}]);
        return;
    }
    
    if ([self containsAddress:address]) {
        completion(nil, [NSError errorWithDomain:@"ZincWallet" code:187
                         userInfo:@{NSLocalizedDescriptionKey:@"this private key is already in your wallet"}]);
        return;
    }

    NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:[UNSPENT_URL stringByAppendingString:address]]
                         cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:10.0];

    [NSURLConnection sendAsynchronousRequest:req queue:[NSOperationQueue currentQueue]
    completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
        if (connectionError) {
            completion(nil, connectionError);
            return;
        }

        NSError *error = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        uint64_t balance = 0, standardFee = 0;
        ZNTransaction *tx = [ZNTransaction new];

        if (error) {
            if ([[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] hasPrefix:@"No free outputs"]) {
                error = [NSError errorWithDomain:@"ZincWallet" code:417
                         userInfo:@{NSLocalizedDescriptionKey:@"this private key is empty"}];
            }

            completion(nil, error);
            return;
        }

        if (! [json isKindOfClass:[NSDictionary class]] ||
            ! [json[@"unspent_outputs"] isKindOfClass:[NSArray class]]) {
            completion(nil, [NSError errorWithDomain:@"ZincWallet" code:417
                             userInfo:@{NSLocalizedDescriptionKey:@"unexpected response from blockchain.info"}]);
            return;
        }

        //TODO: make sure not to create a transaction larger than TX_MAX_SIZE
        for (NSDictionary *utxo in json[@"unspent_outputs"]) {
            if (! [utxo isKindOfClass:[NSDictionary class]] ||
                ! [utxo[@"tx_hash"] isKindOfClass:[NSString class]] || ! [utxo[@"tx_hash"] hexToData] ||
                ! [utxo[@"tx_output_n"] isKindOfClass:[NSNumber class]] ||
                ! [utxo[@"script"] isKindOfClass:[NSString class]] || ! [utxo[@"script"] hexToData] ||
                ! [utxo[@"value"] isKindOfClass:[NSNumber class]]) {
                completion(nil, [NSError errorWithDomain:@"ZincWallet" code:417
                                 userInfo:@{NSLocalizedDescriptionKey:@"unexpected response from blockchain.info"}]);
                return;
            }

            [tx addInputHash:[utxo[@"tx_hash"] hexToData] index:[utxo[@"tx_output_n"] unsignedIntegerValue]
             script:[utxo[@"script"] hexToData]];
            balance += [utxo[@"value"] unsignedLongLongValue];
        }

        if (balance == 0) {
            completion(nil, [NSError errorWithDomain:@"ZincWallet" code:417
                             userInfo:@{NSLocalizedDescriptionKey:@"this private key is empty"}]);
            return;
        }

        // we will be adding a wallet output (additional 34 bytes)
        //TODO: calculate the median of the lowest fee-per-kb that made it into the previous 144 blocks (24hrs)
        if (fee) standardFee = ((tx.size + 34 + 999)/1000)*TX_FEE_PER_KB;

        if (standardFee + TX_MIN_OUTPUT_AMOUNT > balance) {
            completion(nil, [NSError errorWithDomain:@"ZincWallet" code:417
                             userInfo:@{NSLocalizedDescriptionKey:@"transaction fees would cost more than the funds "
                                        "available on this private key (due to tiny \"dust\" deposits)"}]);
            return;
        }
        
        [tx addOutputAddress:[self changeAddress] amount:balance - standardFee];

        if (! [tx signWithPrivateKeys:@[privKey]]) {
            completion(nil, [NSError errorWithDomain:@"ZincWallet" code:401
                             userInfo:@{NSLocalizedDescriptionKey:@"error signing transaction"}]);
            return;
        }
        
        completion(tx, nil);
    }];
}

// true if the given transaction is associated with the wallet, false otherwise
- (BOOL)containsTransaction:(ZNTransaction *)transaction
{
    if ([[NSSet setWithArray:transaction.outputAddresses] intersectsSet:self.allAddresses]) return YES;
    
    NSInteger i = 0;
    
    for (NSData *txHash in transaction.inputHashes) {
        ZNTransaction *tx = self.allTx[txHash];
        uint32_t n = [transaction.inputIndexes[i++] unsignedIntValue];

        if (n < tx.outputAddresses.count && [self containsAddress:tx.outputAddresses[n]]) return YES;
    }
        
    return NO;
}

// records the transaction in the wallet, or returns false if it isn't associated with the wallet
- (BOOL)registerTransaction:(ZNTransaction *)transaction
{
    if (self.allTx[transaction.txHash] != nil) return YES;
    if (! [self containsTransaction:transaction]) return NO;

    [self.usedAddresses addObjectsFromArray:transaction.outputAddresses];
    self.allTx[transaction.txHash] = transaction;
    [self.transactions insertObject:transaction atIndex:0];
    [self updateBalance];

    // when a wallet address is used in a transaction, generate a new address to replace it
    [self addressesWithGapLimit:SEQUENCE_GAP_LIMIT_EXTERNAL internal:NO];
    [self addressesWithGapLimit:SEQUENCE_GAP_LIMIT_INTERNAL internal:YES];

    [[ZNTransactionEntity context] performBlock:^{ // add the transaction to core data
        if ([ZNTransactionEntity countObjectsMatching:@"txHash == %@", transaction.txHash] == 0) {
            [[ZNTransactionEntity managedObject] setAttributesFromTx:transaction];
        };
    }];

    return YES;
}

// removes a transaction from the wallet along with any transactions that depend on its outputs
- (void)removeTransaction:(NSData *)txHash
{
    ZNTransaction *transaction = self.allTx[txHash];

    for (ZNTransaction *tx in self.transactions) { // remove dependent transactions
        if (tx.blockHeight < transaction.blockHeight) break;
        if (! [txHash isEqual:tx.txHash] && [tx.inputHashes containsObject:txHash]) [self removeTransaction:tx.txHash];
    }

    [self.allTx removeObjectForKey:txHash];
    if (transaction) [self.transactions removeObject:transaction];
    [self updateBalance];

    [[ZNTransactionEntity context] performBlock:^{ // remove transaction from core data
        [ZNTransactionEntity deleteObjects:[ZNTransactionEntity objectsMatching:@"txHash == %@", txHash]];
    }];
}

- (void)setBlockHeight:(int32_t)height forTxHashes:(NSArray *)txHashes
{
    BOOL set = NO;

    for (NSData *hash in txHashes) {
        ZNTransaction *tx = self.allTx[hash];

        if (! tx || tx.blockHeight == height) continue;
        tx.blockHeight = height;
        set = YES;
    }

    if (set) {
        [self sortTransactions];
        [self updateBalance];

        [[ZNTransactionEntity context] performBlock:^{
            for (ZNTransactionEntity *e in [ZNTransactionEntity objectsMatching:@"txHash in %@", txHashes]) {
                e.blockHeight = height;
            }
        }];
    }
}

// true if no previous wallet transactions spend any of the given transaction's inputs, and no input tx are invalid
- (BOOL)transactionIsValid:(ZNTransaction *)transaction
{
    if (transaction.blockHeight != TX_UNCONFIRMED) return YES;
    if (self.allTx[transaction.txHash] != nil) return [self.invalidTx containsObject:transaction.txHash] ? NO : YES;

    uint32_t i = 0;

    for (NSData *hash in transaction.inputHashes) {
        ZNTransaction *tx = self.allTx[hash];
        uint32_t n = [transaction.inputIndexes[i++] unsignedIntValue];

        if ((tx && ! [self transactionIsValid:tx]) || [self.spentOutputs containsObject:txOutput(hash, n)]) return NO;
    }

    return YES;
}

// returns the amount received to the wallet by the transaction (total outputs to change and/or recieve addresses)
- (uint64_t)amountReceivedFromTransaction:(ZNTransaction *)transaction
{
    uint64_t amount = 0;
    NSUInteger n = 0;

    for (NSString *address in transaction.outputAddresses) {
        if ([self containsAddress:address]) amount += [transaction.outputAmounts[n] unsignedLongLongValue];
        n++;
    }

    return amount;
}

// retuns the amount sent from the wallet by the trasaction (total wallet outputs consumed, change and fee included)
- (uint64_t)amountSentByTransaction:(ZNTransaction *)transaction
{
    uint64_t amount = 0;
    NSUInteger i = 0;

    for (NSData *hash in transaction.inputHashes) {
        ZNTransaction *tx = self.allTx[hash];
        uint32_t n = [transaction.inputIndexes[i++] intValue];

        if (n < tx.outputAddresses.count && [self containsAddress:tx.outputAddresses[n]]) {
            amount += [tx.outputAmounts[n] unsignedLongLongValue];
        }
    }

    return amount;
}

// returns the fee for the given transaction if all its inputs are from wallet transactions, UINT64_MAX otherwise
- (uint64_t)feeForTransaction:(ZNTransaction *)transaction
{
    uint64_t amount = 0;
    NSUInteger i = 0;

    for (NSData *hash in transaction.inputHashes) {
        ZNTransaction *tx = self.allTx[hash];
        uint32_t n = [transaction.inputIndexes[i++] intValue];

        if (n >= tx.outputAmounts.count) return UINT64_MAX;
        amount += [tx.outputAmounts[n] unsignedLongLongValue];
    }

    for (NSNumber *amt in transaction.outputAmounts) {
        amount -= amt.unsignedLongLongValue;
    }
    
    return amount;
}

// returns the first non-change transaction output address, or nil if there aren't any
- (NSString *)addressForTransaction:(ZNTransaction *)transaction
{
    uint64_t sent = [self amountSentByTransaction:transaction];

    for (NSString *address in transaction.outputAddresses) {
        // first non-wallet address if it's a send transaction, first wallet address if it's a receive transaction
        if ((sent > 0) != [self containsAddress:address]) return address;
    }

    return nil;
}

// Returns the block height after which the transaction is likely be processed without including a fee. This is based on
// the default satoshi client settings, but on the real network it's way off. In testing, a 0.01btc transaction that
// was expected to take an additional 90 days worth of blocks to confirm was confirmed in under an hour by Eligius pool.
- (uint32_t)blockHeightUntilFree:(ZNTransaction *)transaction
{
    // TODO: calculate estimated time based on the median priority of free transactions in last 144 blocks (24hrs)
    NSMutableArray *amounts = [NSMutableArray array], *heights = [NSMutableArray array];
    NSUInteger i = 0;

    for (NSData *hash in transaction.inputHashes) { // get the amounts and block heights of all the transaction inputs
        ZNTransaction *tx = self.allTx[hash];
        uint32_t n = [transaction.inputIndexes[i++] unsignedIntValue];

        if (n >= tx.outputAmounts.count) break;
        [amounts addObject:tx.outputAmounts[n]];
        [heights addObject:@(tx.blockHeight)];
    };

    return [transaction blockHeightUntilFreeForAmounts:amounts withBlockHeights:heights];
}

#pragma mark - string helpers

// TODO: make this work with local currency amounts
- (int64_t)amountForString:(NSString *)string
{
    return ([[self.format numberFromString:string] doubleValue] + DBL_EPSILON)*
           pow(10.0, self.format.maximumFractionDigits);
}

- (NSString *)stringForAmount:(int64_t)amount
{
    NSUInteger min = self.format.minimumFractionDigits;
    
    if (amount == 0) {
        self.format.minimumFractionDigits =
            self.format.maximumFractionDigits > 4 ? 4 : self.format.maximumFractionDigits;
    }
    
    NSString *r = [self.format stringFromNumber:@(amount/pow(10.0, self.format.maximumFractionDigits))];
    
    self.format.minimumFractionDigits = min;
    
    return r;
}

- (NSString *)localCurrencyStringForAmount:(int64_t)amount
{
    static NSNumberFormatter *format = nil;
    
    if (! format) {
        format = [NSNumberFormatter new];
        format.lenient = YES;
        format.numberStyle = NSNumberFormatterCurrencyStyle;
        format.negativeFormat =
            [format.positiveFormat stringByReplacingOccurrencesOfString:CURRENCY_SIGN withString:CURRENCY_SIGN @"-"];
    }
    
    if (! amount) return [format stringFromNumber:@(0)];
    
    NSString *symbol = [[NSUserDefaults standardUserDefaults] stringForKey:LOCAL_CURRENCY_SYMBOL_KEY];
    NSString *code = [[NSUserDefaults standardUserDefaults] stringForKey:LOCAL_CURRENCY_CODE_KEY];
    double price = [[NSUserDefaults standardUserDefaults] doubleForKey:LOCAL_CURRENCY_PRICE_KEY];
    
    if (! symbol.length || price <= DBL_EPSILON) return [format stringFromNumber:@(amount/DEFAULT_CURRENCY_PRICE)];
    
    format.currencySymbol = symbol;
    format.currencyCode = code;
    
    NSString *ret = [format stringFromNumber:@(amount/price)];
    
    // if the amount is too small to be represented in local currency (but is != 0) then return a string like "<$0.01"
    if (amount != 0 && [[format numberFromString:ret] isEqual:@(0.0)]) {
        ret = [@"<" stringByAppendingString:[format stringFromNumber:@(1.0/pow(10.0, format.maximumFractionDigits))]];
    }
    
    return ret;
}

@end
