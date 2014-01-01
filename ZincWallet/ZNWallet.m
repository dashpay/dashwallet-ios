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
#import "NSMutableData+Bitcoin.h"
#import "NSString+Base58.h"
#import "NSManagedObject+Utils.h"

//#define BASE_URL      @"https://blockchain.info"
//#define UNSPENT_URL   BASE_URL "/unspent?active="
//#define ADDRESS_URL   BASE_URL "/multiaddr?active="
//#define PUSHTX_PATH   @"/pushtx"

#define BTC           @"\xC9\x83"     // capital B with stroke (utf-8)
#define CURRENCY_SIGN @"\xC2\xA4"     // generic currency sign (utf-8)
#define NBSP          @"\xC2\xA0"     // no-break space (utf-8)
#define NARROW_NBSP   @"\xE2\x80\xAF" // narrow no-break space (utf-8)

#define LOCAL_CURRENCY_SYMBOL_KEY  @"LOCAL_CURRENCY_SYMBOL"
#define LOCAL_CURRENCY_CODE_KEY    @"LOCAL_CURRENCY_CODE"
#define LOCAL_CURRENCY_PRICE_KEY   @"LOCAL_CURRENCY_PRICE"
#define SEED_KEY                   @"seed"
#define CREATION_TIME_KEY          @"creationtime"

#define SEC_ATTR_SERVICE @"cc.zinc.zincwallet"

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

@interface ZNWallet ()

@property (nonatomic, strong) id<ZNKeySequence> sequence;
@property (nonatomic, strong) NSData *mpk;
@property (nonatomic, strong) NSMutableSet *allAddresses;
@property (nonatomic, strong) NSMutableArray *internalAddresses, *externalAddresses, *transactions, *utxos;
@property (nonatomic, strong) NSMutableDictionary *allTxOutAddresses, *allTxOutValues;
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

    [[NSManagedObject context] performBlockAndWait:^{
        NSFetchRequest *req = [ZNAddressEntity fetchRequest];

        req.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"index" ascending:YES]];
        req.predicate = [NSPredicate predicateWithFormat:@"internal == YES"];
        self.internalAddresses = [[[ZNAddressEntity fetchObjects:req] valueForKey:@"address"] mutableCopy];
        req.predicate = [NSPredicate predicateWithFormat:@"internal == NO"];
        self.externalAddresses = [[[ZNAddressEntity fetchObjects:req] valueForKey:@"address"] mutableCopy];
        self.allAddresses = [NSMutableSet setWithArray:[[ZNAddressEntity allObjects] valueForKey:@"address"]];
        self.allTxOutAddresses = [NSMutableDictionary dictionary];
        self.allTxOutValues = [NSMutableDictionary dictionary];
        self.transactions = [NSMutableArray array];

        for (ZNTransactionEntity *e in [ZNTransactionEntity objectsSortedBy:@"blockHeight" ascending:NO]) {
            [self.transactions addObject:e.transaction];
            self.allTxOutAddresses[e.txHash] = [[e.outputs array] valueForKey:@"address"];
            self.allTxOutValues[e.txHash] = [[e.outputs array] valueForKey:@"value"];
        }

        [self updateBalance];
    }];
    
    return self;
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

    // remove all core data wallet data
    [ZNAddressEntity deleteObjects:[ZNAddressEntity allObjects]];
    [self.allAddresses removeAllObjects];
    [ZNTransactionEntity deleteObjects:[ZNTransactionEntity allObjects]];
    [self.transactions removeAllObjects];
    [self.allTxOutAddresses removeAllObjects];
    [self.allTxOutValues removeAllObjects];
    [self updateBalance];

    [NSManagedObject saveContext];
    
    setKeychainData(nil, CREATION_TIME_KEY);
    setKeychainData(seed, SEED_KEY);

    //BUG: notify that bloom filters need to be rebuilt, earliestKeyTime updated
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
    NSMutableSet *used = [NSMutableSet set];

    for (NSArray *addresses in self.allTxOutAddresses.allValues) {
        [used addObjectsFromArray:addresses];
    }

    // keep only the trailing contiguous block of addresses with no transactions
    while (i > 0 && ! [used containsObject:a[i - 1]]) {
        i--;
    }

    if (i > 0) [a removeObjectsInRange:NSMakeRange(0, i)];

    if (a.count >= gapLimit) {
        [a removeObjectsInRange:NSMakeRange(gapLimit, a.count - gapLimit)];
        return a;
    }

    @synchronized(self) {
        [a setArray:internal ? self.internalAddresses : self.externalAddresses];
        i = a.count;

        unsigned index = (unsigned)i;
    
        // keep only the trailing contiguous block of addresses with no transactions
        while (i > 0 && ! [used containsObject:a[i - 1]]) {
            i--;
        }
    
        if (i > 0) [a removeObjectsInRange:NSMakeRange(0, i)];
        if (a.count >= gapLimit) [a removeObjectsInRange:NSMakeRange(gapLimit, a.count - gapLimit)];
    
        while (a.count < gapLimit) { // generate new addresses up to gapLimit
            NSData *pubKey = [self.sequence publicKey:index internal:internal masterPublicKey:self.masterPublicKey];
            NSString *addr = [[ZNKey keyWithPublicKey:pubKey] address];
        
            if (! addr) {
                NSLog(@"error generating keys");
                return nil;
            }

            [[ZNAddressEntity context] performBlock:^{ // store new address in core data
                [ZNAddressEntity entityWithAddress:addr index:index internal:internal];
            }];

            [self.allAddresses addObject:addr];
            [internal ? self.internalAddresses : self.externalAddresses addObject:addr];
            [a addObject:addr];
            index++;
        }
    
        return a;
    }
}

- (void)updateBalance
{
    [[ZNTxOutputEntity context] performBlockAndWait:^{
        NSMutableArray *utxos = [NSMutableArray array];
        uint64_t balance = 0;

        for (ZNTxOutputEntity *e in [ZNTxOutputEntity objectsMatching:@"spent == NO"]) {
            if (! [self containsAddress:e.address]) continue;

            NSMutableData *d = [NSMutableData dataWithData:e.txHash];

            [d appendUInt32:e.n];
            [utxos addObject:d];
            balance += e.value;
        }

        _unspentOutputs = utxos;
        _balance = balance;
    }];
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

- (NSArray *)recentTransactions
{
    return self.transactions;
}

- (BOOL)containsAddress:(NSString *)address
{
    return (address && [self.allAddresses containsObject:address]) ? YES : NO;
}

#pragma mark - transactions

- (ZNTransaction *)transactionFor:(uint64_t)amount to:(NSString *)address withFee:(BOOL)fee
{
    //TODO: implement P2SH transactions
    //TODO: remove TX_FREE_MIN_OUTPUT per 0.8.6 changes: https://gist.github.com/gavinandresen/7670433#086-relaying

    __block uint64_t balance = 0, standardFee = 0;
    ZNTransaction *tx = [ZNTransaction new];

    [tx addOutputAddress:address amount:amount];

    //TODO: make sure transaction is less than TX_MAX_SIZE
    //TODO: we should use up all inputs tied to any particular address
    //      otherwise we reveal the public key for an address that still has remaining funds
    //TODO: optimize for free transactions (watch out for performance issues, nothing O(n^2) please)
    // this is a nieve implementation to just get it functional, sorts unspent outputs by oldest first
    [[NSManagedObject context] performBlockAndWait:^{
        for (ZNTxOutputEntity *o in [ZNTxOutputEntity objectsSortedBy:@"transaction.blockHeight" ascending:YES]) {
            if (! [self containsAddress:o.address]) continue;
            [tx addInputHash:o.txHash index:o.n script:o.script]; // txHash is already in little endian
            
            balance += o.value;
            
            // assume we will be adding a change output (additional 34 bytes)
            //TODO: calculate the median of the lowest fee-per-kb that made it into the previous 144 blocks (24hrs)
            //NOTE: consider feedback effects if everyone uses the same algorithm to calculate fees, maybe add noise
            if (fee) standardFee = ((tx.size + 34 + 999)/1000)*TX_FEE_PER_KB;
            
            if (balance == amount + standardFee || balance >= amount + standardFee + TX_MIN_OUTPUT_AMOUNT) break;
        }
    }];
    
    if (balance < amount + standardFee) { // insufficent funds
        NSLog(@"Insufficient funds. %llu is less than transaction amount:%llu", balance, amount + standardFee);
        return nil;
    }
    
    //TODO: randomly swap order of outputs so the change address isn't publicy known
    if (balance - (amount + standardFee) >= TX_MIN_OUTPUT_AMOUNT) {
        [tx addOutputAddress:self.changeAddress amount:balance - (amount + standardFee)];
    }
    
    return tx;
}

- (BOOL)signTransaction:(ZNTransaction *)transaction
{
    NSMutableArray *pkeys = [NSMutableArray array];
    NSData *seed = self.seed;
    
    [[NSManagedObject context] performBlockAndWait:^{
        NSArray *externalIndexes = [[ZNAddressEntity objectsMatching:@"internal == NO && address in %@",
                                     transaction.inputAddresses] valueForKey:@"index"];
        NSArray *internalIndexes = [[ZNAddressEntity objectsMatching:@"internal == YES && address in %@",
                                     transaction.inputAddresses] valueForKey:@"index"];
    
        [pkeys addObjectsFromArray:[self.sequence privateKeys:externalIndexes internal:NO fromSeed:seed]];
        [pkeys addObjectsFromArray:[self.sequence privateKeys:internalIndexes internal:YES fromSeed:seed]];
    }];
    
    [transaction signWithPrivateKeys:pkeys];
    
    seed = nil;
    pkeys = nil;
    
    return [transaction isSigned];
}

// given a private key, queries blockchain for unspent outputs and calls the completion block with a signed transaction
// that will sweep the balance into wallet (doesn't publish the tx)
- (void)sweepPrivateKey:(NSString *)privKey withFee:(BOOL)fee
completion:(void (^)(ZNTransaction *tx, NSError *error))completion
{
    //TODO: add support for BIP38 password encrypted private keys
    NSString *address = [[ZNKey keyWithPrivateKey:privKey] address];

    if (! address || ! completion) return;
    
    if ([self containsAddress:address]) {
        completion(nil, [NSError errorWithDomain:@"ZincWallet" code:187
                         userInfo:@{NSLocalizedDescriptionKey:@"this private key is already in your wallet"}]);
        return;
    }
        
    //TODO: XXX implement sweep key... probably use blockchain.info in first version, then do a real blockchain scan
//    _synchronizing = YES;
//    // pass in a mutable dictionary in place of a ZNAddressEntity to avoid storing the address in core data
//    [self queryUnspentOutputs:@[[@{@"address":address} mutableCopy]] completion:^(NSError *error) {
//        _synchronizing = NO;
//        
//        if (error) {
//            completion(nil, error);
//            return;
//        }
//        
//        //TODO: make sure not to create a transaction larger than TX_MAX_SIZE
//        __block uint64_t balance = 0, standardFee = 0;
//        ZNTransaction *tx = [ZNTransaction new];
//        
//        [[NSManagedObject context] performBlockAndWait:^{
//            for (ZNUnspentOutputEntity *o in [ZNUnspentOutputEntity objectsMatching:@"address == %@", address]) {
//                [tx addInputHash:o.txHash index:o.n script:o.script]; // txHash is already in little endian
//            
//                balance += o.value;
//                
//                [o deleteObject]; // immediately remove unspent output from core data, they are not yet in the wallet
//            }
//        }];
//        
//        if (balance == 0) {
//            completion(nil, [NSError errorWithDomain:@"ZincWallet" code:417
//                             userInfo:@{NSLocalizedDescriptionKey:@"this private key is empty"}]);
//            return;
//        }
//
//        // we will be adding a wallet output (additional 34 bytes)
//        //TODO: calculate the median of the lowest fee-per-kb that made it into the previous 144 blocks (24hrs)
//        if (fee) standardFee = ((tx.size + 34 + 999)/1000)*TX_FEE_PER_KB;
//
//        if (standardFee + TX_MIN_OUTPUT_AMOUNT > balance) {
//            completion(nil, [NSError errorWithDomain:@"ZincWallet" code:417
//                             userInfo:@{NSLocalizedDescriptionKey:@"transaction fees would cost more than the funds "
//                             "available on this private key to transfer (due to tiny \"dust\" deposits)"}]);
//            return;
//        }
//        
//        [tx addOutputAddress:[self changeAddress] amount:balance - standardFee];
//
//        if (! [tx signWithPrivateKeys:@[privKey]]) {
//            completion(nil, [NSError errorWithDomain:@"ZincWallet" code:401
//                       userInfo:@{NSLocalizedDescriptionKey:@"error signing transaction"}]);
//            return;
//        }
//        
//        completion(tx, nil);
//    }];
}

// true if the given transaction is associated with the wallet, false otherwise
- (BOOL)containsTransaction:(ZNTransaction *)transaction
{
    if ([[NSSet setWithArray:transaction.outputAddresses] intersectsSet:self.allAddresses]) return YES;
    
    NSInteger i = 0;
    
    for (NSData *txHash in transaction.inputHashes) {
        NSUInteger n = [transaction.inputIndexes[i++] unsignedIntegerValue];
        NSArray *addresses = self.allTxOutAddresses[txHash];

        if (n < addresses.count && [self containsAddress:addresses[n]]) return YES;
    }
        
    return NO;
}

// returns false if the transaction wasn't associated with the wallet
// BUG: XXXX get this to return immediately even if core data blocks
- (BOOL)registerTransaction:(ZNTransaction *)transaction
{
    if (! [self containsTransaction:transaction]) return NO;

    NSMutableArray *utxos = [NSMutableArray arrayWithArray:self.unspentOutputs];
    uint32_t i = 0, n = 0;

    for (NSData *txHash in transaction.inputHashes) { // remove inputs from unspentOutputs
        NSMutableData *d = [NSMutableData dataWithData:txHash];

        [d appendUInt32:[transaction.inputIndexes[i++] unsignedIntValue]];
        [utxos removeObject:d];
    }

    for (NSString *address in  transaction.outputAddresses) { // add outputs to unspentOutputs
        n++;
        if (! [self containsAddress:address]) continue;

        NSMutableData *d = [NSMutableData dataWithData:transaction.txHash];

        [d appendUInt32:n - 1];
        [utxos addObject:d];
    }

    _unspentOutputs = utxos;
    self.allTxOutAddresses[transaction.txHash] = transaction.outputAddresses;
    self.allTxOutValues[transaction.txHash] = transaction.outputAmounts;

    // when a wallet address is used in a transaction, generate a new address to replace it
    [self addressesWithGapLimit:SEQUENCE_GAP_LIMIT_EXTERNAL internal:NO];
    [self addressesWithGapLimit:SEQUENCE_GAP_LIMIT_INTERNAL internal:YES];

    // add the transaction to core data
    [[ZNTransactionEntity context] performBlock:^{
        if ([ZNTransactionEntity countObjectsMatching:@"txHash == %@", transaction.txHash] == 0) {
            [[ZNTransactionEntity managedObject] setAttributesFromTx:transaction];
            [self.transactions addObject:transaction];
        };

        [self updateBalance];

        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:ZNWalletBalanceChangedNotification object:nil];
        });
    }];

    return YES;
}

- (void)setBlockHeight:(int32_t)height forTxHashes:(NSArray *)txHashes
{
    if (txHashes.count == 0) return;

    for (ZNTransaction *tx in self.transactions) {
        if ([txHashes containsObject:tx.txHash]) tx.blockHeight = height;
    }

    [[ZNTransactionEntity context] performBlock:^{
        for (ZNTransactionEntity *e in [ZNTransactionEntity objectsMatching:@"txHash in %@", txHashes]) {
            e.blockHeight = height;
        }
    }];
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
        uint32_t n = [transaction.inputIndexes[i++] intValue];
        NSArray *addresses = self.allTxOutAddresses[hash], *values = self.allTxOutValues[hash];

        if (n < addresses.count && [self containsAddress:addresses[n]]) amount += [values[n] unsignedLongLongValue];
    }

    return amount;
}

// returns the fee for the given transaction if all its inputs are from wallet transactions, UINT64_MAX otherwise
- (uint64_t)feeForTransaction:(ZNTransaction *)transaction
{
    uint64_t amount = 0;
    NSUInteger i = 0;

    for (NSData *hash in transaction.inputHashes) {
        uint32_t n = [transaction.inputIndexes[i++] intValue];
        NSArray *values = self.allTxOutValues[hash];

        if (n >= values.count) return UINT64_MAX;
        amount += [values[n] unsignedLongLongValue];
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

    // get the block heights of all the transaction inputs
    [[ZNTransactionEntity context] performBlockAndWait:^{
        NSUInteger i = 0;

        for (NSData *hash in transaction.inputHashes) {
            ZNTxOutputEntity *o = [ZNTxOutputEntity objectsMatching:@"txHash == %@ && n == %d", hash,
                                   [transaction.inputIndexes[i++] intValue]].lastObject;
            
            if (! o) break;
            [amounts addObject:@(o.value)];
            [heights addObject:@(o.transaction.blockHeight)];
        }
    }];

    return [transaction blockHeightUntilFreeForAmounts:amounts withBlockHeights:heights];
}

#pragma mark - string helpers

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
    
    if (! symbol.length || price <= DBL_EPSILON) return nil;
    
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
