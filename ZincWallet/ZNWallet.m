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
#import "ZNMerkleBlockEntity.h"
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

@property (nonatomic, strong) NSMutableSet *updatedTxHashes;
@property (nonatomic, strong) id<ZNKeySequence> sequence;
@property (nonatomic, strong) NSData *mpk;
@property (nonatomic, strong) NSMutableArray *internalAddresses, *externalAddresses;
@property (nonatomic, strong) NSMutableSet *allTxHashes, *allAddresses, *usedAddresses;

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

        self.allTxHashes = [NSMutableSet setWithArray:[[ZNTransactionEntity allObjects] valueForKey:@"txHash"]];
        self.allAddresses = [NSMutableSet setWithArray:[[ZNAddressEntity allObjects] valueForKey:@"address"]];
        self.usedAddresses = [NSMutableSet setWithArray:[[ZNTxOutputEntity allObjects] valueForKey:@"address"]];
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
    
    _synchronizing = NO;
    self.mpk = nil; // reset master public key

    // remove all core data wallet data
    [ZNAddressEntity deleteObjects:[ZNAddressEntity allObjects]];
    [self.allAddresses removeAllObjects];
    [self.usedAddresses removeAllObjects];
    [ZNTransactionEntity deleteObjects:[ZNTransactionEntity allObjects]];
    [self.allTxHashes removeAllObjects];
    [ZNMerkleBlockEntity deleteObjects:[ZNMerkleBlockEntity allObjects]];

    [NSManagedObject saveContext];
    
    setKeychainData(nil, CREATION_TIME_KEY);
    setKeychainData(seed, SEED_KEY);
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
    while (i > 0 && ! [self.usedAddresses containsObject:a[i - 1]]) i--;
    
    if (i > 0) [a removeObjectsInRange:NSMakeRange(0, i)];
    
    if (a.count >= gapLimit) { // no new addresses need to be generated
        [a removeObjectsInRange:NSMakeRange(gapLimit, a.count - gapLimit)];
        return a;
    }
    
    @synchronized(self) {
        [a setArray:internal ? self.internalAddresses : self.externalAddresses];
        i = a.count;
        
        unsigned index = (unsigned)i;
        
        while (i > 0 && ! [self.usedAddresses containsObject:a[i - 1]]) i--;
        
        if (i > 0) [a removeObjectsInRange:NSMakeRange(0, i)];

        while (a.count < gapLimit) { // generate new addresses up to gapLimit
            NSData *pubKey = [self.sequence publicKey:index internal:internal masterPublicKey:self.masterPublicKey];
            NSString *addr = [[ZNKey keyWithPublicKey:pubKey] address];

            if (! addr) {
                NSLog(@"error generating keys");
                return nil;
            }

            [ZNAddressEntity entityWithAddress:addr index:index internal:internal]; // store new address in core data

            [(internal ? self.internalAddresses : self.externalAddresses) addObject:addr];
            [self.allAddresses addObject:addr];
            [a addObject:addr];
            index++;
        }
    }
    
    return [a subarrayWithRange:NSMakeRange(0, gapLimit)];
}

#pragma mark - wallet info

- (uint64_t)balance
{
    // the outputs of unconfirmed transactions will show up in the unspent outputs list even with 0 confirmations
    __block uint64_t balance = 0;
    
    [[NSManagedObject context] performBlockAndWait:^{
        for (ZNTxOutputEntity *o in [ZNTxOutputEntity objectsMatching:@"spent == NO"]) {
            if ([self containsAddress:o.address]) balance += o.value;
        }
    }];
    
    return balance;
}

- (NSString *)receiveAddress
{
    return [self addressesWithGapLimit:1 internal:NO].lastObject;
}

- (NSString *)changeAddress
{
    return [self addressesWithGapLimit:1 internal:YES].lastObject;
}

- (NSArray *)recentTransactions
{
    NSMutableArray *a = [NSMutableArray array];

    //TODO: XXXX need a secondary sort based on (reverse) db insert order
    for (ZNTransactionEntity *e in [ZNTransactionEntity objectsSortedBy:@"blockHeight" ascending:NO]) {
        [a addObject:e.transaction];
    }

    return a;
}

- (uint32_t)lastBlockHeight
{
    uint32_t height = [[[ZNMerkleBlockEntity objectsSortedBy:@"height" ascending:NO offset:0 limit:1].lastObject
                        get:@"height"] intValue];
    
    if (! height) height = BITCOIN_REFERENCE_BLOCK_HEIGHT;
    
    return height;
}

- (uint32_t)estimatedCurrentBlockHeight
{
    NSTimeInterval time = [[[ZNMerkleBlockEntity objectsSortedBy:@"height" ascending:NO offset:0 limit:1].lastObject
                            get:@"timestamp"] timeIntervalSinceReferenceDate];
    
    if (time < 1.0) time = BITCOIN_REFERENCE_BLOCK_TIME;
    
    // average one block every 600 seconds
    return self.lastBlockHeight + ([NSDate timeIntervalSinceReferenceDate] - time)/600;
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
    uint64_t minChange = fee ? TX_MIN_OUTPUT_AMOUNT : TX_FREE_MIN_OUTPUT;
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
            
            if (balance == amount + standardFee || balance >= amount + standardFee + minChange) break;
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
    
    if (self.synchronizing) {
        completion(nil, [NSError errorWithDomain:@"ZincWallet" code:1
                         userInfo:@{NSLocalizedDescriptionKey:@"wait for wallet sync to finish"}]);
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
    if (! [[NSSet setWithArray:transaction.inputHashes] intersectsSet:self.allTxHashes]) return NO;
    
    NSInteger i = -1;
    
    for (NSData *txHash in transaction.inputHashes) {
        i++;
        if (! [self.allTxHashes containsObject:txHash]) continue;
    
        NSOrderedSet *o = [[ZNTransactionEntity objectsMatching:@"txHash == %@", txHash].lastObject get:@"outputs"];
        NSUInteger idx = [transaction.inputIndexes[i] unsignedIntegerValue];
        
        if (idx < o.count && [self.allAddresses containsObject:[o[idx] get:@"address"]]) return YES;
    }
        
    return NO;
}

// returns false if the transaction wasn't associated with the wallet
- (BOOL)registerTransaction:(ZNTransaction *)transaction
{
    if (! [self containsTransaction:transaction]) return NO;

    // add the transaction to the tx list
    if ([ZNTransactionEntity countObjectsMatching:@"txHash == %@", transaction.txHash] == 0) {
        [[ZNTransactionEntity managedObject] setAttributesFromTx:transaction];
        [self.allTxHashes addObject:transaction.txHash];
        [self.usedAddresses addObjectsFromArray:transaction.outputAddresses];
    }

    // when a wallet address is used in a transaction, generate a new address to replace it
    [self addressesWithGapLimit:SEQUENCE_GAP_LIMIT_EXTERNAL internal:NO];
    [self addressesWithGapLimit:SEQUENCE_GAP_LIMIT_INTERNAL internal:YES];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:balanceChangedNotification object:nil];
    });

    return YES;
}

// returns the estimated time in seconds until the transaction will be processed without a fee.
// this is based on the default satoshi client settings, but on the real network it's way off. in testing, a 0.01btc
// transaction with a 90 day time until free was confirmed in under an hour by Eligius pool.
- (NSTimeInterval)timeUntilFree:(ZNTransaction *)transaction
{
    // TODO: calculate estimated time based on the median priority of free transactions in last 144 blocks (24hrs)
    NSMutableArray *amounts = [NSMutableArray array], *heights = [NSMutableArray array];
    NSUInteger currentHeight = self.lastBlockHeight, idx = 0;
    
    if (! currentHeight) return DBL_MAX;
    
    // get the heights (which block in the blockchain it's in) of all the transaction inputs
    for (NSData *hash in transaction.inputHashes) {
        ZNTxOutputEntity *o = [ZNTxOutputEntity objectsMatching:@"spent == NO && txHash == %@ && n == %d", hash,
                               [transaction.inputIndexes[idx++] intValue]].lastObject;
        
        if (! o) break;
        
        [[o managedObjectContext] performBlockAndWait:^{
            [amounts addObject:@(o.value)];
            [heights addObject:@(o.transaction.blockHeight)];
        }];
    }
    
    NSUInteger height = [transaction blockHeightUntilFreeForAmounts:amounts withBlockHeights:heights];
    
    if (height == TX_UNCONFIRMED) return DBL_MAX;
    
    currentHeight = [self estimatedCurrentBlockHeight];
    
    return height > currentHeight + 1 ? (height - currentHeight)*600 : 0;
}

// retuns the total amount tendered in the trasaction (total unspent outputs consumed, change included)
- (uint64_t)transactionAmount:(ZNTransaction *)transaction
{
    uint64_t amount = 0;
    NSUInteger idx = 0;
    
    for (NSData *hash in transaction.inputHashes) {
        ZNTxOutputEntity *o = [ZNTxOutputEntity objectsMatching:@"spent == NO && txHash == %@ && n == %d", hash,
                               [transaction.inputIndexes[idx++] intValue]].lastObject;
        
        if (! o) {
            amount = 0;
            break;
        }
        else amount += [[o get:@"value"] longLongValue];
    }
    
    return amount;
}

// returns the transaction fee for the given transaction
- (uint64_t)transactionFee:(ZNTransaction *)transaction
{
    uint64_t amount = [self transactionAmount:transaction];
    
    if (amount == 0) return UINT64_MAX;
    
    for (NSNumber *amt in transaction.outputAmounts) {
        amount -= amt.unsignedLongLongValue;
    }
    
    return amount;
}

// returns the amount that the given transaction returns to a change address
- (uint64_t)transactionChange:(ZNTransaction *)transaction
{
    uint64_t amount = 0;
    NSUInteger idx = 0;
    
    for (NSString *address in transaction.outputAddresses) {
        if ([self containsAddress:address]) amount += [transaction.outputAmounts[idx] unsignedLongLongValue];
        idx++;
    }
    
    return amount;
}

// returns the first trasnaction output address not contained in the wallet
- (NSString *)transactionTo:(ZNTransaction *)transaction
{
    NSString *address = nil;
    
    for (NSString *addr in transaction.outputAddresses) {
        if ([self containsAddress:addr]) continue;
        address = addr;
        break;
    }
    
    return address;
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
