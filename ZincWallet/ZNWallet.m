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
#import "ZNPeerManager.h"
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
@property (nonatomic, strong) NSMutableSet *allTxHashes, *allAddresses;
@property (nonatomic, strong) NSUserDefaults *defs;

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
    
    self.defs = [NSUserDefaults standardUserDefaults];
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
        self.allTxHashes = [NSMutableSet setWithArray:[[ZNTransactionEntity allObjects] valueForKey:@"txHash"]];
        self.allAddresses = [NSMutableSet setWithArray:[[ZNAddressEntity allObjects] valueForKey:@"address"]];
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
    [ZNTransactionEntity deleteObjects:[ZNTransactionEntity allObjects]];
    [self.allTxHashes removeAllObjects];
    [ZNMerkleBlockEntity deleteObjects:[ZNMerkleBlockEntity allObjects]];

    [NSManagedObject saveContext];
    [_defs synchronize];
    
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

#pragma mark - synchronization

- (void)synchronize
{
    if (self.synchronizing) return;
    
    _synchronizing = YES;
    [[NSNotificationCenter defaultCenter] postNotificationName:walletSyncStartedNotification object:nil];
    
    __block NSMutableArray *gap = [NSMutableArray array];
    
    // check all the addresses in the wallet for transactions (generating new addresses as needed)
    // generating addresses is slow, but addressesWithGapLimit is thread safe, so we can do that in a separate thread
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // use external gap limit for the inernal chain to produce fewer network requests
        [gap addObjectsFromArray:[self addressesWithGapLimit:SEQUENCE_GAP_LIMIT_EXTERNAL internal:NO]];
        [gap addObjectsFromArray:[self addressesWithGapLimit:SEQUENCE_GAP_LIMIT_EXTERNAL internal:YES]];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([[ZNPeerManager sharedInstance] connected]) {
                [[NSNotificationCenter defaultCenter] postNotificationName:walletSyncFinishedNotification object:nil];
            }
            else [[ZNPeerManager sharedInstance] connect];
            
            _synchronizing = NO;
            return;
        });
    });
}

// Wallets are composed of chains of addresses. Each chain is traversed until a gap of a certain number of addresses is
// found that haven't been used in any transactions. This method returns an array of <gapLimit> unused ZNAddressEntity
// objects following the last used address in the chain. The internal chain is used for change address and the external
// chain for receive addresses.
- (NSArray *)addressesWithGapLimit:(NSUInteger)gapLimit internal:(BOOL)internal
{
    NSMutableArray *newaddresses = [NSMutableArray array];
    NSFetchRequest *req = [ZNAddressEntity fetchRequest];
    
    req.predicate = [NSPredicate predicateWithFormat:@"internal == %@", @(internal)];
    req.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"index" ascending:YES]];
    
    __block NSMutableArray *a = [NSMutableArray arrayWithArray:[ZNAddressEntity fetchObjects:req]];
    __block NSUInteger count = a.count, i = a.count;

    // keep only the trailing contiguous block of addresses with no transactions
    while (i > 0 && [ZNTxOutputEntity countObjectsMatching:@"address == %@", [a[i - 1] get:@"address"]] == 0) i--;
    
    if (i > 0) [a removeObjectsInRange:NSMakeRange(0, i)];
    
    if (a.count >= gapLimit) { // no new addresses need to be generated
        [a removeObjectsInRange:NSMakeRange(gapLimit, a.count - gapLimit)];
        return a;
    }
    
    @synchronized(self) {
        // add any new addresses that were generated while waiting for mutex lock
        req.predicate = [NSPredicate predicateWithFormat:@"internal == %@ && index >= %d", @(internal), count];
        [a addObjectsFromArray:[ZNAddressEntity fetchObjects:req]];
    
        while (a.count < gapLimit) { // generate new addresses up to gapLimit
            unsigned int index = a.count ? [a.lastObject index] + 1 : (unsigned int)count;
            NSData *pubKey = [self.sequence publicKey:index internal:internal masterPublicKey:self.masterPublicKey];
            NSString *addr = [[ZNKey keyWithPublicKey:pubKey] address];

            if (! addr) {
                NSLog(@"error generating keys");
                return nil;
            }

            // store new address in core data
            ZNAddressEntity *address = [ZNAddressEntity entityWithAddress:addr index:index internal:internal];
            
            [self.allAddresses addObject:addr];
            [a addObject:address];
            [newaddresses addObject:address];
        }
    }
    
#if SPV_MODE
    if (newaddresses.count > 0) [[ZNPeerManager sharedInstance] subscribeToAddresses:newaddresses];
#else
    if (newaddresses.count > 0) [[ZNSocketListener sharedInstance] subscribeToAddresses:newaddresses];
#endif
    
    return [a subarrayWithRange:NSMakeRange(0, gapLimit)];
}

#pragma mark - wallet info

- (uint64_t)balance
{
    // the outputs of unconfirmed transactions will show up in the unspent outputs list even with 0 confirmations
    __block uint64_t balance = 0;
    
    [[NSManagedObject context] performBlockAndWait:^{
        for (ZNTxOutputEntity *o in [ZNTxOutputEntity objectsMatching:@"spent == NO"]) {
            balance += o.value;
        }
    }];
    
    return balance;
}

// returns the next unused address on the requested chain
- (NSString *)addressFromInternal:(BOOL)internal
{
    __block NSString *address = nil;

    [[NSManagedObject context] performBlockAndWait:^{
        ZNAddressEntity *addr = [self addressesWithGapLimit:1 internal:internal].lastObject;
        int32_t i = addr.index, height = 0;
    
        while (i > 0) { // consider an address still unused if none of its transactions have more than 6 confimations
            ZNAddressEntity *a =
                [ZNAddressEntity objectsMatching:@"internal == %@ && index == %d", @(internal), --i].lastObject;
        
            for (ZNTxOutputEntity *o in [ZNTxOutputEntity objectsMatching:@"address == %@", a.address]) {
                height = o.transaction.blockHeight;
                if (height == TX_UNCONFIRMED || self.lastBlockHeight - height < 6) continue;
                addr = a;
                break;
            }
        }
        
        address = addr.address;
    }];
    
    return address;
}

- (NSString *)receiveAddress
{
    return [self addressFromInternal:NO];
}

- (NSString *)changeAddress
{
    return [self addressFromInternal:YES];
}

- (NSArray *)recentTransactions
{
    // sort in descending order by timestamp (using block_height doesn't work for unconfirmed, or multiple tx per block)
    return [ZNTransactionEntity objectsSortedBy:@"timeStamp" ascending:NO];
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
                            get:@"timestamp"] intValue];
    
    if (time < 1.0) time = BITCOIN_REFERENCE_BLOCK_TIME;
    
    // average one block every 600 seconds
    return self.lastBlockHeight + ([NSDate timeIntervalSinceReferenceDate] - time)/600;
}

- (BOOL)containsAddress:(NSString *)address
{
    return [ZNAddressEntity countObjectsMatching:@"address == %@", address] > 0;
}

#pragma mark - transactions

- (ZNTransaction *)transactionFor:(uint64_t)amount to:(NSString *)address withFee:(BOOL)fee
{
    __block uint64_t balance = 0, standardFee = 0;
    uint64_t minChange = fee ? TX_MIN_OUTPUT_AMOUNT : TX_FREE_MIN_OUTPUT;
    ZNTransaction *tx = [ZNTransaction new];

    [tx addOutputAddress:address amount:amount];

    //TODO: make sure transaction is less than TX_MAX_SIZE
    //TODO: optimize for free transactions (watch out for performance issues, nothing O(n^2) please)
    // this is a nieve implementation to just get it functional, sorts unspent outputs by oldest first
    [[NSManagedObject context] performBlockAndWait:^{
        for (ZNTxOutputEntity *o in [ZNTxOutputEntity objectsSortedBy:@"transaction.blockHeight" ascending:YES]) {
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

- (void)publishTransaction:(ZNTransaction *)transaction completion:(void (^)(NSError *error))completion
{
    if (! [transaction isSigned]) {
        if (completion) {
            completion([NSError errorWithDomain:@"ZincWallet" code:401
                        userInfo:@{NSLocalizedDescriptionKey:@"bitcoin transaction not signed"}]);
        }
        return;
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:walletSyncStartedNotification object:nil];

    [self registerTransaction:transaction];

    [[ZNPeerManager sharedInstance] publishTransaction:transaction completion:^(NSError *error) {
        if (error) {
            [[NSNotificationCenter defaultCenter] postNotificationName:walletSyncFailedNotification
             object:@{@"error":error}];
        }
        else [[NSNotificationCenter defaultCenter] postNotificationName:walletSyncFinishedNotification object:nil];
        
        if (completion) completion(error);
    }];

    //TODO: also publish transactions directly to coinbase and bitpay servers for faster POS experience
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
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:walletBalanceNotification object:nil];
    return YES;
}

@end
