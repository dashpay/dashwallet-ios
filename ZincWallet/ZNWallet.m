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
#import "ZNTransaction.h"
#import "ZNKey.h"
#import "ZNPeerManager.h"
#import "ZNSocketListener.h"
#import "ZNAddressEntity.h"
#import "ZNTransactionEntity.h"
#import "ZNTxInputEntity.h"
#import "ZNTxOutputEntity.h"
#import "ZNUnspentOutputEntity.h"
#import "ZNMnemonic.h"
#import "ZNZincMnemonic.h"
#import "ZNKeySequence.h"
#import "ZNBIP32Sequence.h"
#import "NSData+Hash.h"
#import "NSMutableData+Bitcoin.h"
#import "NSString+Base58.h"
#import "NSManagedObject+Utils.h"
#import "AFNetworking.h"

#define BASE_URL      @"https://blockchain.info"
#define UNSPENT_URL   BASE_URL "/unspent?active="
#define ADDRESS_URL   BASE_URL "/multiaddr?active="
#define PUSHTX_PATH   @"/pushtx"
#define BTC           @"\xC9\x83"     // capital B with stroke (utf-8)
#define CURRENCY_SIGN @"\xC2\xA4"     // generic currency sign (utf-8)
#define NBSP          @"\xC2\xA0"     // no-break space (utf-8)
#define NARROW_NBSP   @"\xE2\x80\xAF" // narrow no-break space (utf-8)

#define LOCAL_CURRENCY_SYMBOL_KEY  @"LOCAL_CURRENCY_SYMBOL"
#define LOCAL_CURRENCY_CODE_KEY    @"LOCAL_CURRENCY_CODE"
#define LOCAL_CURRENCY_PRICE_KEY   @"LOCAL_CURRENCY_PRICE"
#define LATEST_BLOCK_HEIGHT_KEY    @"LATEST_BLOCK_HEIGHT"
#define LATEST_BLOCK_TIMESTAMP_KEY @"LATEST_BLOCK_TIMESTAMP"
#define LAST_SYNC_TIME_KEY         @"LAST_SYNC_TIME"
#define SEED_KEY                   @"seed"

#define REFERENCE_BLOCK_HEIGHT 250000
#define REFERENCE_BLOCK_TIME   1375533383.0

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
    
    return SecItemAdd((__bridge CFDictionaryRef)item, NULL) == noErr ? YES : NO;
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
    
    return self;
}

- (NSData *)seed
{
    NSData *seed = getKeychainData(SEED_KEY);
    
    if (seed.length != SEED_LENGTH) {
        self.seed = nil;
        return nil;
    }
    
    return seed;
}

- (void)setSeed:(NSData *)seed
{
    if (seed && [self.seed isEqual:seed]) return;
    
    setKeychainData(seed, SEED_KEY);
    
    _synchronizing = NO;
    self.mpk = nil; // reset master public key

    // remove all core data wallet data
    [[ZNAddressEntity allObjects] makeObjectsPerformSelector:@selector(deleteObject)];
    [[ZNTransactionEntity allObjects] makeObjectsPerformSelector:@selector(deleteObject)];
    [[ZNUnspentOutputEntity allObjects] makeObjectsPerformSelector:@selector(deleteObject)];
    
    [_defs removeObjectForKey:LAST_SYNC_TIME_KEY]; // clean out wallet values in user defaults

    [NSManagedObject saveContext];
    [_defs synchronize];
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
    NSMutableData *seed = CFBridgingRelease(CFDataCreateMutable(SecureAllocator(), SEED_LENGTH));
        
    seed.length = SEED_LENGTH;
    SecRandomCopyBytes(kSecRandomDefault, seed.length, seed.mutableBytes);

    self.seed = seed;
}

- (NSData *)masterPublicKey
{
    if (self.mpk) return self.mpk;
    
    self.mpk = [self.sequence masterPublicKeyFromSeed:self.seed];
    return self.mpk;
}

// if any of an unconfimred transaction's inputs show up as unspent, or spent by a confirmed transaction,
// that means the tx failed to confirm and needs to be removed from the tx list
- (void)cleanUnconfirmed
{
    //TODO: remove unconfirmed transactions after 2 days?
    //TODO: keep a seprate list of failed transactions to display along with the successful ones
    for (ZNTransactionEntity *tx in [ZNTransactionEntity objectsMatching:@"blockHeight == 0"]) {
        for (ZNTxInputEntity *i in tx.inputs) { // check each tx input
            // if the input is unspent, or spent by a confirmed transaction, delete the unconfirmed tx
            if ([ZNUnspentOutputEntity countObjectsMatching:@"txIndex == %lld && n == %d", i.txIndex, i.n] > 0 ||
                [ZNTxInputEntity countObjectsMatching:@"txIndex == %lld && n == %d && transaction.blockHeight > 0",
                 i.txIndex, i.n] > 0) {
                NSArray *addrs = [[[tx.inputs valueForKey:@"address"] array]
                                  arrayByAddingObjectsFromArray:[[tx.outputs valueForKey:@"address"] array]];
                
                [[ZNAddressEntity objectsMatching:@"address IN %@", addrs] setValue:@(YES) forKey:@"newTx"];
                [tx deleteObject];
                break;
            }
        }
    }
}

#pragma mark - synchronization

- (void)synchronize:(BOOL)fullSync
{
    if (self.synchronizing) return;
    
    _synchronizing = YES;
    [[NSNotificationCenter defaultCenter] postNotificationName:walletSyncStartedNotification object:nil];
    
    __block NSMutableArray *gap = [NSMutableArray array];
    
    // a recursive block ARC retain loop is avoided by passing the block as an argument to itself... just shoot me now
    __block void (^completion)(NSError *, id) = ^(NSError *error, void (^completion)(NSError *, id)) {
        if (error) {
            _synchronizing = NO;
            [NSManagedObject saveContext];
            [_defs synchronize];
            
            [[NSNotificationCenter defaultCenter] postNotificationName:walletSyncFailedNotification object:nil
             userInfo:@{@"error":error}];
            return;
        }
        
        // check for previously empty addresses that now have transactions
        [gap filterUsingPredicate:[NSPredicate predicateWithFormat:@"txCount > 0"]];
        
        if (gap.count > 0) { // take the next set of empty addresses and check them for transactions
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [gap setArray:[self addressesWithGapLimit:GAP_LIMIT_EXTERNAL internal:NO]];
                [gap addObjectsFromArray:[self addressesWithGapLimit:GAP_LIMIT_EXTERNAL internal:YES]];
                if (gap.count == 0) return;

                dispatch_async(dispatch_get_main_queue(), ^{
                    [self queryAddresses:gap completion:^(NSError *error) {
                        completion(error, completion);
                    }];
                });
            });
            return;
        }
        
        // remove unconfirmed transactions that no longer appear in query results
        //TODO: keep a seprate list of failed transactions to display along with the successful ones
        for (ZNTransactionEntity *tx in
             [ZNTransactionEntity objectsMatching:@"blockHeight == 0 && ! (txHash IN %@)", self.updatedTxHashes]) {
            NSArray *addrs = [[[tx.inputs valueForKey:@"address"] array]
                              arrayByAddingObjectsFromArray:[[tx.outputs valueForKey:@"address"] array]];

            [[ZNAddressEntity objectsMatching:@"address IN %@", addrs] setValue:@(YES) forKey:@"newTx"];
            [tx deleteObject];
        }

        // update the unspent outputs for addresses that have new transactions, or all addresses in case of fullSync
        NSArray *addrs = fullSync ? [ZNAddressEntity allObjects] : [ZNAddressEntity objectsMatching:@"newTx == YES"];

        [self queryUnspentOutputs:addrs completion:^(NSError *error) {
            _synchronizing = NO;
            
            if (error) {
                [NSManagedObject saveContext];
                [_defs synchronize];
                
                [[NSNotificationCenter defaultCenter] postNotificationName:walletSyncFailedNotification object:nil
                 userInfo:@{@"error":error}];
                return;
            }
            
            // remove any transactions that failed
            [self cleanUnconfirmed];
            
            [NSManagedObject saveContext];
            [_defs setDouble:[NSDate timeIntervalSinceReferenceDate] forKey:LAST_SYNC_TIME_KEY];
            [_defs synchronize];
            
            [[NSNotificationCenter defaultCenter] postNotificationName:walletSyncFinishedNotification object:nil];
                
            // send balance notification every time since exchange rates might have changed
            [[NSNotificationCenter defaultCenter] postNotificationName:walletBalanceNotification object:nil];
        }];
    };

    // check all the addresses in the wallet for transactions (generating new addresses as needed)
    // generating addresses is slow, but addressesWithGapLimit is thread safe, so we can do that in a separate thread
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // use external gap limit for the inernal chain to produce fewer network requests
        [gap addObjectsFromArray:[self addressesWithGapLimit:GAP_LIMIT_EXTERNAL internal:NO]];
        [gap addObjectsFromArray:[self addressesWithGapLimit:GAP_LIMIT_EXTERNAL internal:YES]];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            NSArray *used = [ZNAddressEntity objectsMatching:@"! (address IN %@)", [gap valueForKey:@"address"]];
            
            self.updatedTxHashes = [NSMutableSet set]; // reset the updated tx set

#if SPV_MODE
            if ([[ZNPeerManager sharedInstance] connected]) {
                [_defs setDouble:[NSDate timeIntervalSinceReferenceDate] forKey:LAST_SYNC_TIME_KEY];
                [_defs synchronize];

                [[NSNotificationCenter defaultCenter] postNotificationName:walletSyncFinishedNotification object:nil];
            }
            else [[ZNPeerManager sharedInstance] connect];
            
            _synchronizing = NO;
            return;
#endif

#if BITCOIN_TESTNET
            [_defs setDouble:[NSDate timeIntervalSinceReferenceDate] forKey:LAST_SYNC_TIME_KEY];
            [_defs synchronize];

            _synchronizing = NO;
            [[NSNotificationCenter defaultCenter] postNotificationName:walletSyncFinishedNotification object:nil];
            return;
#endif
            // query addresses for transactons, unused addresses first
            [self queryAddresses:[gap arrayByAddingObjectsFromArray:used] completion:^(NSError *error) {
                completion(error, completion);
            }];
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
    [[NSManagedObject context] performBlockAndWait:^{
        while (i > 0 && [a[i - 1] txCount] == 0) i--;
    }];

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

// query blockchain for transactions involving the given addresses
- (void)queryAddresses:(NSArray *)addresses completion:(void (^)(NSError *error))completion
{
    if (addresses.count == 0) {
        if (completion) completion(nil);
        return;
    }
    
    if (addresses.count > ADDRESSES_PER_QUERY) { // break up into multiple network queries if needed
        [self queryAddresses:[addresses subarrayWithRange:NSMakeRange(0, ADDRESSES_PER_QUERY)]
        completion:^(NSError *error) {
            if (error) {
                if (completion) completion(error);
                return;
            }
            
            [self queryAddresses:[addresses
             subarrayWithRange:NSMakeRange(ADDRESSES_PER_QUERY, addresses.count - ADDRESSES_PER_QUERY)]
             completion:completion];
        }];
        return;
    }
    
    NSURL *url = [NSURL URLWithString:[ADDRESS_URL stringByAppendingString:[[[addresses valueForKey:@"address"]
                  componentsJoinedByString:@"|"] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]]];
    __block AFJSONRequestOperation *requestOp =
        [AFJSONRequestOperation JSONRequestOperationWithRequest:[NSURLRequest requestWithURL:url]
        success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
            if (! self.synchronizing) return;
            
            if (! [JSON isKindOfClass:[NSDictionary class]] || ! [JSON[@"addresses"] isKindOfClass:[NSArray class]] ||
                ! [JSON[@"txs"] isKindOfClass:[NSArray class]]) {
                NSError *error = [NSError errorWithDomain:@"ZincWallet" code:500 userInfo:@{
                                  NSLocalizedDescriptionKey:@"Unexpected server response from blockchain.info"}];

                if (completion) completion(error);
            }
        
            for (NSDictionary *d in JSON[@"addresses"]) {
                [ZNAddressEntity updateWithJSON:d]; // update core data address objects
            }
            
            for (NSDictionary *d in JSON[@"txs"]) {
                ZNTransactionEntity *tx = [ZNTransactionEntity updateOrCreateWithJSON:d]; // update core data tx objs
                
                if (tx.txHash) [self.updatedTxHashes addObject:tx.txHash];
            }
            
            // store other useful information from the query result in user defaults
            if ([JSON[@"info"] isKindOfClass:[NSDictionary class]] &&
                [JSON[@"info"][@"latest_block"] isKindOfClass:[NSDictionary class]] &&
                [JSON[@"info"][@"symbol_local"] isKindOfClass:[NSDictionary class]]) {
                
                NSDictionary *b = JSON[@"info"][@"latest_block"];
                NSDictionary *l = JSON[@"info"][@"symbol_local"];
                int height = [b[@"height"] isKindOfClass:[NSNumber class]] ? [b[@"height"] intValue] : 0;
                NSTimeInterval time = [b[@"time"] isKindOfClass:[NSNumber class]] ? [b[@"time"] doubleValue] : 0;
                NSString *symbol = [l[@"symbol"] isKindOfClass:[NSString class]] ? l[@"symbol"] : nil;
                NSString *code = [l[@"code"] isKindOfClass:[NSString class]] ? l[@"code"] : nil;
                double price = [l[@"conversion"] isKindOfClass:[NSNumber class]] ? [l[@"conversion"] doubleValue] : 0;
                    
                if (height > 0) [_defs setInteger:height forKey:LATEST_BLOCK_HEIGHT_KEY];
                if (time > 1.0) [_defs setDouble:time forKey:LATEST_BLOCK_TIMESTAMP_KEY];
                if (symbol.length > 0) [_defs setObject:symbol forKey:LOCAL_CURRENCY_SYMBOL_KEY];
                if (code.length > 0) [_defs setObject:code forKey:LOCAL_CURRENCY_CODE_KEY];
                if (price > DBL_EPSILON) [_defs setDouble:price forKey:LOCAL_CURRENCY_PRICE_KEY];
            }

            if (completion) completion(nil);
        } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
            NSLog(@"%@", error);        
            if (completion) completion(error);
        }];
    
    NSLog(@"%@", url.absoluteString);
    [requestOp start];
}

// query blockchain for unspent outputs for the given addresses
- (void)queryUnspentOutputs:(NSArray *)addresses completion:(void (^)(NSError *error))completion
{
    if (addresses.count == 0) {
        if (completion) completion(nil);
        return;
    }
    
    if (addresses.count > ADDRESSES_PER_QUERY) { // break up into multiple network queries if needed
        [self queryUnspentOutputs:[addresses subarrayWithRange:NSMakeRange(0, ADDRESSES_PER_QUERY)]
        completion:^(NSError *error) {
            if (error) {
                if (completion) completion(error);
                return;
            }
            
            [self queryUnspentOutputs:[addresses
             subarrayWithRange:NSMakeRange(ADDRESSES_PER_QUERY, addresses.count - ADDRESSES_PER_QUERY)]
             completion:completion];
        }];
        return;
    }
    
    NSURL *url = [NSURL URLWithString:[UNSPENT_URL stringByAppendingString:[[[addresses valueForKey:@"address"]
                  componentsJoinedByString:@"|"] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]]];
    __block AFJSONRequestOperation *requestOp =
        [AFJSONRequestOperation JSONRequestOperationWithRequest:[NSURLRequest requestWithURL:url]
        success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
            if (! self.synchronizing) return;
            
            // if all outputs have been spent, blockchain.info returns the non-JSON string "no free outputs"
            if (! [requestOp.responseString.lowercaseString hasPrefix:@"no free outputs"] &&
                ! [JSON[@"unspent_outputs"] isKindOfClass:[NSArray class]]) {
                NSError *error = [NSError errorWithDomain:@"ZincWallet" code:500 userInfo:@{
                                  NSLocalizedDescriptionKey:@"Unexpeted server response from blockchain.info"}];

                if (completion) completion(error);
                return;
            }

            NSArray *addrs = [addresses valueForKey:@"address"];
            
            // remove any previously stored unspent outputs for the queried addresses
            [[ZNUnspentOutputEntity objectsMatching:@"address IN %@", addrs]
             makeObjectsPerformSelector:@selector(deleteObject)];
            
            // store any unspent outputs in core data
            for (NSDictionary *d in JSON[@"unspent_outputs"]) {
                ZNUnspentOutputEntity *o = [ZNUnspentOutputEntity entityWithJSON:d];
                    
                if (o.value == 0 || ! [addrs containsObject:o.address]) [o deleteObject];
            }
            
            [addresses setValue:@(NO) forKey:@"newTx"]; // tx successfully synced, reset new tx flag

            if (completion) completion(nil);
        } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
            // if the error is "no free outputs", that's not actually an error
            if (! [requestOp.responseString.lowercaseString hasPrefix:@"no free outputs"]) {
                NSLog(@"%@", error);
                if (completion) completion(error);
                return;
            }
            
            // all outputs have been spent for the requested addresses
            [[ZNUnspentOutputEntity objectsMatching:@"address IN %@", [addresses valueForKey:@"address"]]
             makeObjectsPerformSelector:@selector(deleteObject)];

            [addresses setValue:@(NO) forKey:@"newTx"]; // tx successfully synced, reset new tx flag
            
            if (completion) completion(nil);
        }];

    NSLog(@"%@", url.absoluteString);
    [requestOp start];
}

- (NSTimeInterval)timeSinceLastSync
{
    return [NSDate timeIntervalSinceReferenceDate] - [_defs doubleForKey:LAST_SYNC_TIME_KEY];
}

#pragma mark - wallet info

- (uint64_t)balance
{
    // the outputs of unconfirmed transactions will show up in the unspent outputs list even with 0 confirmations
    __block uint64_t balance = 0;
    
    for (ZNUnspentOutputEntity *o in [ZNUnspentOutputEntity allObjects]) {
        balance += o.value;
    }
    
    return balance;
}

// returns the next unused address on the requested chain
- (NSString *)addressFromInternal:(BOOL)internal
{
    ZNAddressEntity *addr = [self addressesWithGapLimit:1 internal:internal].lastObject;
    int32_t i = addr.index;
    
    while (i > 0) { // consider an address still unused if none of its transactions have at least 6 confimations
        ZNAddressEntity *a =
            [ZNAddressEntity objectsMatching:@"internal == %@ && index == %d", @(internal), --i].lastObject;
        
        if (a.txCount > 0) {
            NSArray *unspent = [ZNUnspentOutputEntity objectsMatching:@"address == %@ && confirmations < 6", a.address];
    
            // if number of unique txIndexes with < 6 confirms is less than txCount, at least one tx has > 6 confirms
            if ([[NSSet setWithArray:[unspent valueForKey:@"txIndex"]] count] < a.txCount) break;
        }

        if (a) addr = a;
    }
    
    return addr.address;
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
    uint32_t height = (uint32_t)[_defs integerForKey:LATEST_BLOCK_HEIGHT_KEY];
    
    if (! height) height = REFERENCE_BLOCK_HEIGHT;
    
    return height;
}

- (uint32_t)estimatedCurrentBlockHeight
{
    NSTimeInterval time = [_defs doubleForKey:LATEST_BLOCK_TIMESTAMP_KEY];
    
    if (time < 1.0) time = REFERENCE_BLOCK_TIME;
    
    // average one block every 600 seconds
    return self.lastBlockHeight + ([NSDate timeIntervalSinceReferenceDate] + NSTimeIntervalSince1970 - time)/600;
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
    for (ZNUnspentOutputEntity *o in [ZNUnspentOutputEntity objectsSortedBy:@"txIndex" ascending:YES]) {
        [tx addInputHash:o.txHash index:o.n script:o.script]; // txHash is already in little endian
            
        balance += o.value;

        // assume we will be adding a change output (additional 34 bytes)
        //TODO: calculate the median of the lowest fee-per-kb that made it into the previous 144 blocks (24hrs)
        //NOTE: consider feedback effects if everyone uses the same algorithm to calculate fees, maybe introduce noise
        if (fee) standardFee = ((tx.size + 34 + 999)/1000)*TX_FEE_PER_KB;
            
        if (balance == amount + standardFee || balance >= amount + standardFee + minChange) break;
    }
    
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
    NSArray *externalIndexes = [[ZNAddressEntity objectsMatching:@"internal == NO && address IN %@",
                                 transaction.inputAddresses] valueForKey:@"index"];
    NSArray *internalIndexes = [[ZNAddressEntity objectsMatching:@"internal == YES && address IN %@",
                                 transaction.inputAddresses] valueForKey:@"index"];
    NSMutableArray *pkeys = [NSMutableArray arrayWithCapacity:externalIndexes.count + internalIndexes.count];
    NSData *seed = self.seed;
    
    [pkeys addObjectsFromArray:[self.sequence privateKeys:externalIndexes internal:NO fromSeed:seed]];
    [pkeys addObjectsFromArray:[self.sequence privateKeys:internalIndexes internal:YES fromSeed:seed]];
    
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
    
    _synchronizing = YES;
    // pass in a mutable dictionary in place of a ZNAddressEntity to avoid storing the address in core data
    [self queryUnspentOutputs:@[[@{@"address":address} mutableCopy]] completion:^(NSError *error) {
        _synchronizing = NO;
        
        if (error) {
            completion(nil, error);
            return;
        }
        
        //TODO: make sure not to create a transaction larger than TX_MAX_SIZE
        __block uint64_t balance = 0, standardFee = 0;
        ZNTransaction *tx = [ZNTransaction new];
        
        for (ZNUnspentOutputEntity *o in [ZNUnspentOutputEntity objectsMatching:@"address == %@", address]) {
            [tx addInputHash:o.txHash index:o.n script:o.script]; // txHash is already in little endian
            
            balance += o.value;

            [o deleteObject]; // immediately remove unspent output from core data, they are not yet in the wallet
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
                             "available on this private key to transfer (due to tiny \"dust\" deposits)"}]);
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

    [[AFHTTPClient clientWithBaseURL:[NSURL URLWithString:BASE_URL]] postPath:PUSHTX_PATH
    parameters:@{@"tx":[transaction toHex]} success:^(AFHTTPRequestOperation *operation, id responseObject) {
        NSLog(@"responseObject: %@", responseObject);
        NSLog(@"response:\n%@", operation.responseString);
        
        if ([operation.responseString.lowercaseString rangeOfString:@"error"].location != NSNotFound) {
            NSError *error = [NSError errorWithDomain:@"ZincWallet" code:500
                              userInfo:@{NSLocalizedDescriptionKey:operation.responseString}];
            
            [[NSNotificationCenter defaultCenter] postNotificationName:walletSyncFailedNotification object:nil
             userInfo:@{@"error":error}];
            
            if (completion) completion(error);
            return;
        }
        
        [self registerTransaction:transaction];
        [_defs synchronize];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:walletSyncFinishedNotification object:nil];
        if (completion) completion(nil);
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        [[NSNotificationCenter defaultCenter] postNotificationName:walletSyncFailedNotification object:nil
         userInfo:@{@"error":error}];

        NSLog(@"%@", operation.responseString);
        if (completion) completion(error);
    }];

    //TODO: also publish transactions directly to coinbase and bitpay servers for faster POS experience
}

- (void)registerTransaction:(ZNTransaction *)transaction
{
    NSUInteger idx = 0;
    NSArray *addresses = [ZNAddressEntity objectsMatching:@"address IN %@",
                          [transaction.outputAddresses arrayByAddingObjectsFromArray:transaction.inputAddresses]];
    
    if (addresses.count == 0) return; // at least one address in the tx must be contained in the wallet

    // add the transaction to the tx list
    if ([ZNTransactionEntity countObjectsMatching:@"txHash == %@", transaction.txHash] == 0) {
        [[ZNTransactionEntity managedObject] setAttributesFromTx:transaction];
    }
    
    [addresses setValue:@(YES) forKey:@"newTx"]; // mark addresses to be updated on next wallet sync

    // delete any unspent outputs that are now spent
    for (NSData *hash in transaction.inputHashes) {
        [[ZNUnspentOutputEntity objectsMatching:@"txHash == %@ && n == %d", hash,
          [transaction.inputIndexes[idx++] intValue]].lastObject deleteObject];
    }
    
    // add change to unspent outputs
    idx = 0;
    
    for (NSString *address in transaction.outputAddresses) {
        if ([self containsAddress:address] &&
            [ZNUnspentOutputEntity countObjectsMatching:@"txHash == %@ && n == %d", transaction.txHash, idx] == 0) {
            [ZNUnspentOutputEntity entityWithAddress:address txHash:transaction.txHash n:(int)idx
             value:[transaction.outputAmounts[idx] longLongValue]];
        }
        
        idx++;
    }
    
    [NSManagedObject saveContext];
    [[NSNotificationCenter defaultCenter] postNotificationName:walletBalanceNotification object:nil];
}

@end
