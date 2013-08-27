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
#import "ZNWallet+WebSocket.h"
#import "NSData+Hash.h"
#import "NSMutableData+Bitcoin.h"
#import "NSString+Base58.h"
#import "AFNetworking.h"

#import "ZNMnemonic.h"
#if WALLET_BIP39
#import "ZNBIP39Mnemonic.h"
#else
#import "ZNElecturmMnemonic.h"
#endif

#import "ZNKeySequence.h"
#if WALLET_BIP32
#import "ZNBIP32Sequence.h"
#else
#import "ZNElectrumSequence.h"
#endif

#define BASE_URL    @"https://blockchain.info"
#define UNSPENT_URL BASE_URL "/unspent?active="
#define ADDRESS_URL BASE_URL "/multiaddr?active="
#define PUSHTX_PATH @"/pushtx"

#define TRANSACTIONS_KEY           @"TRANSACTIONS"
#define UNSPENT_OUTPUTS_KEY        @"UNSPENT_OUTPUTS"
#define ADDRESS_TX_COUNT_KEY       @"ADDRESS_TX_COUNT"

#define LATEST_BLOCK_HEIGHT_KEY    @"LATEST_BLOCK_HEIGHT"
#define LATEST_BLOCK_TIMESTAMP_KEY @"LATEST_BLOCK_TIMESTAMP"
#define LOCAL_CURRENCY_SYMBOL_KEY  @"LOCAL_CURRENCY_SYMBOL"
#define LOCAL_CURRENCY_CODE_KEY    @"LOCAL_CURRENCY_CODE"
#define LOCAL_CURRENCY_PRICE_KEY   @"LOCAL_CURRENCY_PRICE"
#define LAST_SYNC_TIME_KEY         @"LAST_SYNC_TIME"
#define SEED_KEY                   @"seed"

#define REFERENCE_BLOCK_HEIGHT 243295
#define REFERENCE_BLOCK_TIME   1372190977.0

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

@property (nonatomic, strong) NSMutableArray *externalAddresses, *internalAddresses;
@property (nonatomic, strong) NSMutableDictionary *transactions, *unspentOutputs, *addressTxCount;
@property (nonatomic, strong) NSMutableSet *outdatedAddresses, *updatedTransactions;

@property (nonatomic, strong) id<ZNKeySequence> sequence;
@property (nonatomic, strong) NSData *mpk;
@property (nonatomic, strong) NSUserDefaults *defs;
@property (nonatomic, strong) NSNumberFormatter *localFormat;

@property (nonatomic, strong) SRWebSocket *webSocket;
@property (nonatomic, assign) int connectFailCount;
@property (nonatomic, strong) id reachabilityObserver, activeObserver;

@end

@implementation ZNWallet

+ (instancetype)sharedInstance
{
    static id singleton = nil;
    static dispatch_once_t onceToken = 0;
    
    dispatch_once(&onceToken, ^{ singleton = [self new]; });
    return singleton;
}

- (instancetype)init
{
    if (! (self = [super init])) return nil;
    
    self.defs = [NSUserDefaults standardUserDefaults];
    
    self.externalAddresses = [NSMutableArray array];
    self.internalAddresses = [NSMutableArray array];
    self.outdatedAddresses = [NSMutableSet set];
    self.transactions = [NSMutableDictionary dictionaryWithDictionary:[_defs dictionaryForKey:TRANSACTIONS_KEY]];
    self.unspentOutputs = [NSMutableDictionary dictionaryWithDictionary:[_defs dictionaryForKey:UNSPENT_OUTPUTS_KEY]];
    self.addressTxCount = [NSMutableDictionary dictionaryWithDictionary:[_defs dictionaryForKey:ADDRESS_TX_COUNT_KEY]];

#if WALLET_BIP32
    self.sequence = [ZNBIP32Sequence new];
#else
     self.sequence = [ZNElectrumSequence new];
#endif
    
    self.format = [NSNumberFormatter new];
    self.format.lenient = YES;
    self.format.numberStyle = NSNumberFormatterCurrencyStyle;
    self.format.minimumFractionDigits = 0;
    //self.format.currencySymbol = @"m"BTC@" ";
    //self.format.maximumFractionDigits = 5;
    //self.format.maximum = @21000000000.0;
    self.format.currencySymbol = BTC;
    self.format.negativeFormat =
        [self.format.positiveFormat stringByReplacingOccurrencesOfString:@"¤" withString:@"¤ -"];
    self.format.positiveFormat =
        [self.format.positiveFormat stringByReplacingOccurrencesOfString:@"¤" withString:@"¤ "];
    self.format.maximumFractionDigits = 8;
    self.format.maximum = @21000000.0;
    
    self.localFormat = [NSNumberFormatter new];
    self.localFormat.lenient = YES;
    self.localFormat.numberStyle = NSNumberFormatterCurrencyStyle;
    self.localFormat.negativeFormat =
        [self.localFormat.positiveFormat stringByReplacingOccurrencesOfString:@"¤" withString:@"¤-"];
    
    return self;
}

- (NSData *)seed
{
    NSData *seed = getKeychainData(SEED_KEY);
    
    if (seed.length != 128/8) {
        self.seed = nil;
        return nil;
    }
    
    return seed;
}

- (void)setSeed:(NSData *)seed
{
    if (seed && [self.seed isEqual:seed]) return;
    
    @synchronized(self) {
        setKeychainData(seed, SEED_KEY);
        
        _synchronizing = NO;
        self.mpk = nil;
        [self.externalAddresses removeAllObjects];
        [self.internalAddresses removeAllObjects];
        [self.outdatedAddresses removeAllObjects];
        [self.transactions removeAllObjects];
        [self.addressTxCount removeAllObjects];
        [self.unspentOutputs removeAllObjects];
        
        // flush cached addresses and tx outputs
        [_defs removeObjectForKey:TRANSACTIONS_KEY];
        [_defs removeObjectForKey:UNSPENT_OUTPUTS_KEY];
        [_defs removeObjectForKey:ADDRESS_TX_COUNT_KEY];
        [_defs removeObjectForKey:LAST_SYNC_TIME_KEY];
        
        [self addressesWithGapLimit:GAP_LIMIT_EXTERNAL internal:NO];
        [self addressesWithGapLimit:GAP_LIMIT_INTERNAL internal:YES];
    }

    [_defs synchronize];
}

- (NSString *)seedPhrase
{
#if WALLET_BIP39
    id<ZNMnemonic> mnemonic = [ZNBIP39Mnemonic sharedInstance];
#else
    id<ZNMnemonic> mnemonic = [ZNElecturmMnemonic sharedInstance];
#endif

    return [mnemonic encodePhrase:self.seed];
}

- (void)setSeedPhrase:(NSString *)seedPhrase
{
#if WALLET_BIP39
    id<ZNMnemonic> mnemonic = [ZNBIP39Mnemonic sharedInstance];
#else
    id<ZNMnemonic> mnemonic = [ZNElecturmMnemonic sharedInstance];
#endif

    self.seed = [mnemonic decodePhrase:seedPhrase];
}

- (void)generateRandomSeed
{
    NSMutableData *seed = CFBridgingRelease(CFDataCreateMutable(SecureAllocator(), SEED_LENGTH));
        
    seed.length = SEED_LENGTH;
    SecRandomCopyBytes(kSecRandomDefault, seed.length, seed.mutableBytes);

    self.seed = seed;
}

- (NSData *)mpk
{
    if (_mpk) return _mpk;
    
    self.mpk = [self.sequence masterPublicKeyFromSeed:self.seed];
    return _mpk;
}

// if any of an unconfimred transaction's inputs show up as unspent, or show up in confirmed transaction, that means the
// tx failed to confirm and needs to be removed from the tx list
- (void)cleanUnconfirmed
{
    //TODO: remove unconfirmed transactions after 2 days?
    //TODO: keep a seprate list of failed transactions to display along with the successful ones
    
    NSMutableSet *s = [NSMutableSet set];
    __block NSUInteger unconfirmed = 0;

    [self.transactions enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        if (obj[@"block_height"] != nil) {
            [obj[@"inputs"] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                NSDictionary *o = obj[@"prev_out"];

                [s addObject:[NSString stringWithFormat:@"%@:%@", o[@"tx_index"], o[@"n"]]];
            }];
        }
        else unconfirmed++;
    }];
    
    if (! unconfirmed) return;
    
    @synchronized(self) {
        [self.unspentOutputs enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            [s addObject:[NSString stringWithFormat:@"%@:%@", obj[@"tx_index"], obj[@"tx_output_n"]]];
        }];
    
        [self.transactions
        removeObjectsForKeys:[self.transactions keysOfEntriesPassingTest:^BOOL(id key, id obj, BOOL *stop) {
            if (obj[@"block_height"] != nil) return NO;

            // index of any inputs of the unconfirmed tx that are already spent or in unspentOutputs
            NSUInteger i =
                [obj[@"inputs"] indexOfObjectPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
                    NSDictionary *o = obj[@"prev_out"];
                    NSString *key = [NSString stringWithFormat:@"%@:%@", o[@"tx_index"], o[@"n"]];
                    
                    return [s containsObject:key] ? (*stop = YES) : NO;
                }];
                
            return (i == NSNotFound) ? NO : YES;
        }].allObjects];
        
        [_defs setObject:self.transactions forKey:TRANSACTIONS_KEY];
    }
}

#pragma mark - synchronization

- (void)synchronize
{
    if (_synchronizing) return;
    
    _synchronizing = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:walletSyncStartedNotification object:self];
    });
        
    NSMutableArray *a = [NSMutableArray array];
    
    [a addObjectsFromArray:[self addressesWithGapLimit:GAP_LIMIT_EXTERNAL internal:NO]];

    // use external gap limit when syncing inernal chain to produce fewer api calls
    [a addObjectsFromArray:[self addressesWithGapLimit:GAP_LIMIT_EXTERNAL internal:YES]];

    [self.externalAddresses enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        if ([a indexOfObject:obj] == NSNotFound) [a addObject:obj];
    }];

    [self.internalAddresses enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        if ([a indexOfObject:obj] == NSNotFound) [a addObject:obj];
    }];
    
    // An ARC retain loop is avoided here when using block recursion by passing the block to itself as an argument...
    // just shoot me now... please
    void (^completion)(NSError *, id) = ^(NSError *error, id completion) {
        if (error) {
            _synchronizing = NO;
            [_defs synchronize];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:walletSyncFailedNotification object:self
                 userInfo:@{@"error":error}];
            });
            return;
        }
    
        [a removeObjectsAtIndexes:[a indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
            return [self.addressTxCount[obj] unsignedIntegerValue] > 0;
        }]];
        
        if (a.count < GAP_LIMIT_EXTERNAL + GAP_LIMIT_EXTERNAL) {
            [a setArray:[self addressesWithGapLimit:GAP_LIMIT_EXTERNAL internal:NO]];
            [a addObjectsFromArray:[self addressesWithGapLimit:GAP_LIMIT_EXTERNAL internal:YES]];
            if (a.count) {
                [self queryAddresses:a completion:^(NSError *error) {
                    ((void (^)(NSError *, id))completion)(error, completion);
                }];
            }
            return;
        }
        
        @synchronized(self) {
            // remove unconfirmed transactions that no longer appear in query results
            //TODO: keep a seprate list of failed transactions to display along with the successful ones
            [self.transactions
            removeObjectsForKeys:[self.transactions keysOfEntriesPassingTest:^BOOL(id key, id obj, BOOL *stop) {
                return ! obj[@"block_height"] && ! [self.updatedTransactions containsObject:obj[@"hash"]];
            }].allObjects];
            
            [_defs setObject:self.transactions forKey:TRANSACTIONS_KEY];
        }

        [self queryUnspentOutputs:self.outdatedAddresses.allObjects completion:^(NSError *error) {
            _synchronizing = NO;
            
            if (error) {
                [_defs synchronize];
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[NSNotificationCenter defaultCenter] postNotificationName:walletSyncFailedNotification object:self
                     userInfo:@{@"error":error}];
                });
                return;
            }
            
            [self cleanUnconfirmed];
            
            [_defs setDouble:[NSDate timeIntervalSinceReferenceDate] forKey:LAST_SYNC_TIME_KEY];
            [_defs synchronize];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:walletSyncFinishedNotification object:self];
                
                // send balance notification every time since exchnage rates might have changed
                [[NSNotificationCenter defaultCenter] postNotificationName:walletBalanceNotification object:self];
            });
        }];
    };
    
    self.updatedTransactions = [NSMutableSet set];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self queryAddresses:a completion:^(NSError *error) { completion(error, completion); }];
    });
}

- (NSArray *)addressesWithGapLimit:(NSUInteger)gapLimit internal:(BOOL)internal
{
    NSMutableArray *a = [NSMutableArray arrayWithArray:internal ? self.internalAddresses : self.externalAddresses];
    NSMutableArray *newaddresses = [NSMutableArray array];
    NSUInteger i = a.count;
    NSString *addr = nil;
    
    [a removeObjectsAtIndexes:[a indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
        return [self.addressTxCount[obj] unsignedIntegerValue] > 0 ? YES : NO;
    }]];
    
    if (a.count >= gapLimit) {
        [a removeObjectsInRange:NSMakeRange(gapLimit, a.count - gapLimit)];
        return a;
    }
    
    // TODO: generating addresses is noticably slow, cache them in coredata
    @synchronized(self) {
        while (a.count < gapLimit) {
            addr = [[ZNKey keyWithPublicKey:[self.sequence publicKey:i++ internal:internal masterPublicKey:self.mpk]]
                    address];
        
            if (! addr) {
                NSLog(@"error generating keys");
                return nil;
            }
            
            if ([self.addressTxCount[addr] unsignedIntegerValue] == 0) [a addObject:addr];
            
            if (! internal && self.externalAddresses.count < i) {
                [self.externalAddresses addObject:addr];
                [newaddresses addObject:addr];
            }
            else if (internal && self.internalAddresses.count < i) {
                [self.internalAddresses addObject:addr];
                [newaddresses addObject:addr];
            }
        }
    }
    
    if (newaddresses.count) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self subscribeToAddresses:newaddresses];
        });
    }
    
    return a;
}

// query blockchain for the given addresses
- (void)queryAddresses:(NSArray *)addresses completion:(void (^)(NSError *error))completion
{
    if (! addresses.count) {
        if (completion) completion(nil);
        return;
    }
    
    if (addresses.count > ADDRESSES_PER_QUERY) {
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
    
    NSURL *url = [NSURL URLWithString:[ADDRESS_URL stringByAppendingString:[[addresses componentsJoinedByString:@"|"]
                  stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]]];
    __block dispatch_queue_t q = dispatch_get_current_queue();
    __block AFJSONRequestOperation *requestOp =
        [AFJSONRequestOperation JSONRequestOperationWithRequest:[NSURLRequest requestWithURL:url]
        success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
            if (! _synchronizing) return;
        
            @synchronized(self) {
                [JSON[@"addresses"] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                    if (obj[@"address"] && [obj[@"n_tx"] unsignedLongLongValue] > 0) {
                        if ([obj[@"n_tx"] unsignedIntegerValue] !=
                            [self.addressTxCount[obj[@"address"]] unsignedIntegerValue]) {
                            [self.outdatedAddresses addObject:obj[@"address"]];
                        }
            
                        self.addressTxCount[obj[@"address"]] = obj[@"n_tx"];
                    }
                }];
                
                [JSON[@"txs"] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                    //XXXX we shouldn't be saving json without sanitizing it... security risk
                    if (obj[@"hash"]) {
                        self.transactions[obj[@"hash"]] = obj;
                        [self.updatedTransactions addObject:obj[@"hash"]];
                    }
                }];
        
                // remove unconfirmed transactions that didn't show up in the updated list, they failed to confirm
                [self.transactions
                removeObjectsForKeys:[self.transactions keysOfEntriesPassingTest:^BOOL(id key, id obj, BOOL *stop) {
                    return (! [self.updatedTransactions containsObject:obj[@"hash"]] && ! obj[@"block_height"]);
                }].allObjects];
        
                NSInteger height = [JSON[@"info"][@"latest_block"][@"height"] integerValue];
                NSTimeInterval time = [JSON[@"info"][@"latest_block"][@"time"] doubleValue];
                NSString *symbol = JSON[@"info"][@"symbol_local"][@"symbol"];
                NSString *code = JSON[@"info"][@"symbol_local"][@"code"];
                double price = [JSON[@"info"][@"symbol_local"][@"conversion"] doubleValue];
                
                [_defs setObject:self.addressTxCount forKey:ADDRESS_TX_COUNT_KEY];
                [_defs setObject:self.transactions forKey:TRANSACTIONS_KEY];
                if (height) [_defs setInteger:height forKey:LATEST_BLOCK_HEIGHT_KEY];
                if (time > 1.0) [_defs setDouble:time forKey:LATEST_BLOCK_TIMESTAMP_KEY];
                if (symbol.length) [_defs setObject:symbol forKey:LOCAL_CURRENCY_SYMBOL_KEY];
                if (code.length) [_defs setObject:code forKey:LOCAL_CURRENCY_CODE_KEY];
                if (price > DBL_EPSILON) [_defs setDouble:price forKey:LOCAL_CURRENCY_PRICE_KEY];
            }
            
            if (completion) dispatch_async(q, ^{ completion(nil); });
        } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
            NSLog(@"%@", error.localizedDescription);
        
            if (completion) dispatch_async(q, ^{ completion(error); });
        }];
    
    NSLog(@"%@", url.absoluteString);
    requestOp.successCallbackQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    requestOp.failureCallbackQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    [requestOp start];
}

// query blockchain for unspent outputs of the given addresses
- (void)queryUnspentOutputs:(NSArray *)addresses completion:(void (^)(NSError *error))completion
{
    if (! addresses.count) {
        if (completion) completion(nil);
        return;
    }
    
    if (addresses.count > ADDRESSES_PER_QUERY) {
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
    
    NSURL *url = [NSURL URLWithString:[UNSPENT_URL stringByAppendingString:[[addresses componentsJoinedByString:@"|"]
                  stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]]];
    __block dispatch_queue_t q = dispatch_get_current_queue();
    __block AFJSONRequestOperation *requestOp =
        [AFJSONRequestOperation JSONRequestOperationWithRequest:[NSURLRequest requestWithURL:url]
        success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
            if (! _synchronizing) return;
            
            if (! [requestOp.responseString.lowercaseString hasPrefix:@"no free outputs"] &&
                JSON[@"unspent_outputs"] == nil) {
                NSError *error = [NSError errorWithDomain:@"ZincWallet" code:500 userInfo:@{
                                  NSLocalizedDescriptionKey:@"Unexpeted server response from blockchain.info"}];

                if (completion) dispatch_async(q, ^{ completion(error); });
                return;
            }

            @synchronized(self) {
                [self.unspentOutputs
                removeObjectsForKeys:[self.unspentOutputs keysOfEntriesPassingTest:^BOOL(id key, id obj, BOOL *stop) {
                    NSString *addr = [NSString addressWithScript:[obj[@"script"] hexToData]];
                    
                    return (! addr || [addresses containsObject:addr]) ? YES : NO;
                }].allObjects];

                [self.outdatedAddresses minusSet:[NSSet setWithArray:addresses]];
            
                [JSON[@"unspent_outputs"] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                    NSString *key = [obj[@"tx_hash"] stringByAppendingString:[obj[@"tx_output_n"] description]];

                    //XXXX we shouldn't be storing json without sanitizing it... security risk
                    if (key && [obj[@"value"] unsignedLongLongValue] > 0) self.unspentOutputs[key] = obj;
                }];
            
                [_defs setObject:self.unspentOutputs forKey:UNSPENT_OUTPUTS_KEY];
            }

            if (completion) dispatch_async(q, ^{ completion(nil); });
        } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
            if (! [requestOp.responseString.lowercaseString hasPrefix:@"no free outputs"]) {
                NSLog(@"%@", error.localizedDescription);
                if (completion) dispatch_async(q, ^{ completion(error); });
                return;
            }
            
            @synchronized(self) {
                [self.unspentOutputs
                removeObjectsForKeys:[self.unspentOutputs keysOfEntriesPassingTest:^BOOL(id key, id obj, BOOL *stop) {
                    NSString *addr = [NSString addressWithScript:[obj[@"script"] hexToData]];
                    
                    return (! addr || [addresses containsObject:addr]) ? YES : NO;
                }].allObjects];
            
                [self.outdatedAddresses minusSet:[NSSet setWithArray:addresses]];
                
                [_defs setObject:self.unspentOutputs forKey:UNSPENT_OUTPUTS_KEY];
            }
            
            if (completion) dispatch_async(q, ^{ completion(nil); });
        }];

    NSLog(@"%@", url.absoluteString);
    requestOp.successCallbackQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    requestOp.failureCallbackQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
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
    
    [self.unspentOutputs enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        balance += [obj[@"value"] unsignedLongLongValue];
    }];
    
    return balance;
}

- (NSString *)receiveAddress
{
    __block NSString *addr = [self addressesWithGapLimit:1 internal:NO].lastObject;

    [self.externalAddresses enumerateObjectsWithOptions:NSEnumerationReverse
    usingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        if ([self.addressTxCount[obj] unsignedIntegerValue] > 0) {
            NSMutableSet *txIndexes = [NSMutableSet set];
            
            [self.unspentOutputs enumerateKeysAndObjectsUsingBlock:^(id k, id o, BOOL *stop) {
                NSString *a = [NSString addressWithScript:[o[@"script"] hexToData]];

                if ([a isEqual:obj] && [o[@"confirmations"] unsignedIntegerValue] < 6) {
                    [txIndexes addObject:o[@"tx_index"]];
                }
            }];
            
            if (txIndexes.count < [self.addressTxCount[obj] unsignedIntegerValue]) {
                *stop = YES;
                return;
            }
        }
        
        addr = obj;
    }];

    return addr;
}

- (NSString *)changeAddress
{
    __block NSString *addr = [self addressesWithGapLimit:1 internal:YES].lastObject;
    
    [self.internalAddresses enumerateObjectsWithOptions:NSEnumerationReverse
    usingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        if ([self.addressTxCount[obj] unsignedIntegerValue] > 0) {
            NSMutableSet *txIndexes = [NSMutableSet set];
            
            [self.unspentOutputs enumerateKeysAndObjectsUsingBlock:^(id k, id o, BOOL *stop) {
                NSString *a = [NSString addressWithScript:[o[@"script"] hexToData]];
                
                if ([a isEqual:obj] && [o[@"confirmations"] unsignedIntegerValue] < 6) {
                    [txIndexes addObject:o[@"tx_index"]];
                }
            }];
            
            if (txIndexes.count < [self.addressTxCount[obj] unsignedIntegerValue]) {
                *stop = YES;
                return;
            }
        }
        
        addr = obj;
    }];

    return addr;
}

- (NSArray *)recentTransactions
{
    // sort in descending order by timestamp (using block_height doesn't work for unconfirmed, or multiple tx per block)
    return [self.transactions.allValues sortedArrayWithOptions:0 usingComparator:^NSComparisonResult(id obj1, id obj2) {
               return [@([obj2[@"time"] doubleValue]) compare:@([obj1[@"time"] doubleValue])];
           }];
}

- (NSUInteger)lastBlockHeight
{
    NSUInteger height = [_defs integerForKey:LATEST_BLOCK_HEIGHT_KEY];
    
    if (! height) height = REFERENCE_BLOCK_HEIGHT;
    
    return height;
}

- (NSUInteger)estimatedCurrentBlockHeight
{
    NSTimeInterval time = [_defs doubleForKey:LATEST_BLOCK_TIMESTAMP_KEY];
    
    if (time < 1.0) time = REFERENCE_BLOCK_TIME;
    
    // average one block every 600 seconds
    return self.lastBlockHeight + ([NSDate timeIntervalSinceReferenceDate] + NSTimeIntervalSince1970 - time)/600;
}

- (BOOL)containsAddress:(NSString *)address
{
    if (self.externalAddresses.count < GAP_LIMIT_EXTERNAL) [self addressesWithGapLimit:GAP_LIMIT_EXTERNAL internal:NO];
    if (self.internalAddresses.count < GAP_LIMIT_INTERNAL) [self addressesWithGapLimit:GAP_LIMIT_INTERNAL internal:YES];

    return [self.externalAddresses containsObject:address] || [self.internalAddresses containsObject:address];
}

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
    if (! amount) return [self.localFormat stringFromNumber:@(0)];

    NSString *symbol = [_defs stringForKey:LOCAL_CURRENCY_SYMBOL_KEY];
    NSString *code = [_defs stringForKey:LOCAL_CURRENCY_CODE_KEY];
    double price = [_defs doubleForKey:LOCAL_CURRENCY_PRICE_KEY];
    
    if (! symbol.length || price <= DBL_EPSILON) return nil;
    
    self.localFormat.currencySymbol = symbol;
    self.localFormat.currencyCode = code;
    
    return [self.localFormat stringFromNumber:@(amount/price)];
}

#pragma mark - ZNTransaction helpers

- (ZNTransaction *)transactionFor:(uint64_t)amount to:(NSString *)address withFee:(BOOL)fee
{
    __block uint64_t balance = 0, standardFee = 0;
    uint64_t minChange = fee ? TX_MIN_OUTPUT_AMOUNT : TX_FREE_MIN_OUTPUT;
    ZNTransaction *tx = [ZNTransaction new];

    [tx addOutputAddress:address amount:amount];

    @synchronized(self) {
        //TODO: optimize for free transactions (watch out for performance issues, nothing O(n^2) please)
        // this is a nieve implementation to just get it functional, sorts unspent outputs by oldest first
        NSArray *keys =
            [self.unspentOutputs keysSortedByValueUsingComparator:^NSComparisonResult(id obj1, id obj2) {
                return [obj1[@"tx_index"] compare:obj2[@"tx_index"]];
            }];
    
        [keys enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            NSDictionary *o = self.unspentOutputs[obj];
        
            // tx_hash is already in little endian
            [tx addInputHash:[o[@"tx_hash"] hexToData] index:[o[@"tx_output_n"] unsignedIntegerValue]
                      script:[o[@"script"] hexToData]];
            
            balance += [o[@"value"] unsignedLongLongValue];

            // assume we will be adding a change output (additional 34 bytes)
            //TODO: calculate the median of the lowest fee-per-kb that made it into the previous 144 blocks (24hrs)
            if (fee) standardFee = ((tx.size + 34 + 999)/1000)*TX_FEE_PER_KB;
            
            if (balance == amount + standardFee || balance >= amount + standardFee + minChange) *stop = YES;
        }];
    
        if (balance < amount + standardFee) { // insufficent funds
            NSLog(@"Insufficient funds. %llu is less than transaction amount:%llu", balance, amount + standardFee);
            return nil;
        }
    
        //TODO: randomly swap order of outputs so the change address isn't publicy known
        if (balance - (amount + standardFee) >= TX_MIN_OUTPUT_AMOUNT) {
            [tx addOutputAddress:self.changeAddress amount:balance - (amount + standardFee)];
        }
    }
    
    return tx;
}

// returns the estimated time in seconds until the transaction will be processed without a fee.
// this is based on the default satoshi client settings, but on the real network it's way off. in testing, a 0.01btc
// transaction with a 90 day time until free was confirmed in under an hour by Eligius pool.
// TODO: calculate estimated time based on the median priority of free transactions in last 144 blocks (24hrs)
- (NSTimeInterval)timeUntilFree:(ZNTransaction *)transaction
{
    NSMutableArray *amounts = [NSMutableArray array], *heights = [NSMutableArray array];
    NSUInteger currentHeight = [_defs integerForKey:LATEST_BLOCK_HEIGHT_KEY];
    
    if (! currentHeight) return DBL_MAX;
    
    @synchronized(self) {
        [transaction.inputAddresses enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            NSString *hash = [NSString hexWithData:transaction.inputHashes[idx]];
            NSString *n = [transaction.inputIndexes[idx] description];
            NSDictionary *o = self.unspentOutputs[[hash stringByAppendingString:n]];

            if (o) {
                [amounts addObject:o[@"value"]];
                [heights addObject:@(currentHeight - [o[@"confirmations"] unsignedIntegerValue])];
            }
            else *stop = YES;
        }];
    }

    NSUInteger height = [transaction blockHeightUntilFreeForAmounts:amounts withBlockHeights:heights];
    
    if (height == NSNotFound) return DBL_MAX;
    
    currentHeight = [self estimatedCurrentBlockHeight];
    
    return height > currentHeight + 1 ? (height - currentHeight)*600 : 0;
}

- (uint64_t)transactionFee:(ZNTransaction *)transaction
{
    __block uint64_t balance = 0, amount = 0;

    @synchronized(self) {
        [transaction.inputAddresses enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            NSString *hash = [NSString hexWithData:transaction.inputHashes[idx]];
            NSString *n = [transaction.inputIndexes[idx] description];
            NSDictionary *o = self.unspentOutputs[[hash stringByAppendingString:n]];
        
            if (! o) {
                balance = UINT64_MAX;
                *stop = YES;
            }
            else balance += [o[@"value"] unsignedLongLongValue];
        }];
    }

    if (balance == UINT64_MAX) return UINT64_MAX;
    
    [transaction.outputAmounts enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        amount += [obj unsignedLongLongValue];
    }];
    
    return balance - amount;
}

- (BOOL)signTransaction:(ZNTransaction *)transaction
{
    NSMutableSet *keyIndexes = [NSMutableSet set], *changeKeyIndexes = [NSMutableSet set];

    @synchronized(self) {
        [transaction.inputAddresses enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            if ([self.externalAddresses indexOfObject:obj] == NSNotFound) {
                if ([self.internalAddresses indexOfObject:obj] == NSNotFound) {
                    NSLog(@"[%s %s] line %d: missing key", object_getClassName(self), sel_getName(_cmd), __LINE__);
                    *stop = YES;
                }
                else [changeKeyIndexes addObject:@([self.internalAddresses indexOfObject:obj])];
            }
            else [keyIndexes addObject:@([self.externalAddresses indexOfObject:obj])];
        }];
    }
    
    NSMutableArray *pkeys = [NSMutableArray arrayWithCapacity:keyIndexes.count + changeKeyIndexes.count];
    NSData *seed = self.seed;
    
    [pkeys addObjectsFromArray:[self.sequence privateKeys:keyIndexes.allObjects internal:NO fromSeed:seed]];
    [pkeys addObjectsFromArray:[self.sequence privateKeys:changeKeyIndexes.allObjects internal:YES fromSeed:seed]];
    
    [transaction signWithPrivateKeys:pkeys];
    
    seed = nil;
    pkeys = nil;
    
    return [transaction isSigned];
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
    
    dispatch_queue_t q = dispatch_get_current_queue();
    AFHTTPClient *client = [AFHTTPClient clientWithBaseURL:[NSURL URLWithString:BASE_URL]];

    [client postPath:PUSHTX_PATH parameters:@{@"tx":[transaction toHex]}
    success:^(AFHTTPRequestOperation *operation, id responseObject) {
        NSMutableDictionary *tx = [NSMutableDictionary dictionary];
        
        tx[@"hash"] = [NSString hexWithData:transaction.hash];
        tx[@"time"] = @([NSDate timeIntervalSinceReferenceDate] + NSTimeIntervalSince1970);
        tx[@"inputs"] = [NSMutableArray array];
        tx[@"out"] = [NSMutableArray array];
        
        //NOTE: successful response is "Transaction submitted", maybe we should check for that
        NSLog(@"responseObject: %@", responseObject);
        NSLog(@"response:\n%@", operation.responseString);
        
        @synchronized(self) {
            [transaction.inputAddresses enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                NSString *hash = [NSString hexWithData:transaction.inputHashes[idx]];
                NSString *n = [transaction.inputIndexes[idx] description];
                NSDictionary *o = self.unspentOutputs[[hash stringByAppendingString:n]];
            
                if (o) {
                    [self.unspentOutputs removeObjectForKey:[hash stringByAppendingString:n]];
                
                    //NOTE: for now we don't need to store spent outputs because blockchain.info will not list them as
                    // unspent while there is an unconfirmed tx that spends them. This may change once we have multiple
                    // apis for publishing, and a transaction may not show up on blockchain.info immediately.
                    [tx[@"inputs"] addObject:@{@"prev_out":@{@"tx_index":o[@"tx_index"], @"n":o[@"tx_output_n"],
                                                             @"value":o[@"value"], @"addr":obj}}];
                }
            }];
        
            [transaction.outputAddresses enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                [tx[@"out"] addObject:@{@"n":@(idx), @"value":transaction.outputAmounts[idx], @"addr":obj}];
            }];
        
            // don't update addressTxCount so the address's unspent outputs will be updated on next sync
            //[updated enumerateObjectsUsingBlock:^(id obj, BOOL *stop) {
            //    self.addressTxCount[obj] = @([self.addressTxCount[obj] unsignedIntegerValue] + 1);
            //}];
        
            self.transactions[tx[@"hash"]] = tx;
        
            [_defs setObject:self.unspentOutputs forKey:UNSPENT_OUTPUTS_KEY];
            [_defs setObject:self.addressTxCount forKey:ADDRESS_TX_COUNT_KEY];
            [_defs setObject:self.transactions forKey:TRANSACTIONS_KEY];
        }
        
        [_defs synchronize];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:walletBalanceNotification object:self];
        });
        
        if (completion) dispatch_async(q, ^{ completion(nil); });
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"%@", operation.responseString);
        if (completion) dispatch_async(q, ^{ completion(error); });
    }];

    //TODO: also publish transactions directly to coinbase and bitpay servers for faster POS experience
}

@end
