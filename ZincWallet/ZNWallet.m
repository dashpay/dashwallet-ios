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

#define SCRIPT_SUFFIX @"88ac" // OP_EQUALVERIFY OP_CHECKSIG

#define FUNDED_ADDRESSES_KEY       @"FUNDED_ADDRESSES"
#define SPENT_ADDRESSES_KEY        @"SPENT_ADDRESSES"
#define RECEIVE_ADDRESSES_KEY      @"RECEIVE_ADDRESSES"
#define ADDRESS_BALANCES_KEY       @"ADDRESS_BALANCES"
#define ADDRESS_TX_COUNT_KEY       @"ADDRESS_TX_COUNT"
#define UNSPENT_OUTPUTS_KEY        @"UNSPENT_OUTPUTS"
#define TRANSACTIONS_KEY           @"TRANSACTIONS"
#define UNCONFIRMED_KEY            @"UNCONFIRMED"
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

@property (nonatomic, strong) NSMutableArray *addresses, *changeAddresses;
@property (nonatomic, strong) NSMutableArray *spentAddresses, *fundedAddresses, *receiveAddresses;
@property (nonatomic, strong) NSMutableDictionary *unspentOutputs, *addressBalances, *addressTxCount;
@property (nonatomic, strong) NSMutableDictionary *transactions, *unconfirmed;
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
    
    //XXX we should be using core data for this...
    self.addresses = [NSMutableArray array];
    self.changeAddresses = [NSMutableArray array];
    self.outdatedAddresses = [NSMutableSet set];
    self.fundedAddresses = [NSMutableArray arrayWithArray:[_defs arrayForKey:FUNDED_ADDRESSES_KEY]];
    self.spentAddresses = [NSMutableArray arrayWithArray:[_defs arrayForKey:SPENT_ADDRESSES_KEY]];
    self.receiveAddresses = [NSMutableArray arrayWithArray:[_defs arrayForKey:RECEIVE_ADDRESSES_KEY]];
    self.transactions = [NSMutableDictionary dictionaryWithDictionary:[_defs dictionaryForKey:TRANSACTIONS_KEY]];
    self.unconfirmed = [NSMutableDictionary dictionaryWithDictionary:[_defs dictionaryForKey:UNCONFIRMED_KEY]];
    self.addressBalances = [NSMutableDictionary dictionaryWithDictionary:[_defs dictionaryForKey:ADDRESS_BALANCES_KEY]];
    self.addressTxCount = [NSMutableDictionary dictionaryWithDictionary:[_defs dictionaryForKey:ADDRESS_TX_COUNT_KEY]];
    self.unspentOutputs = [NSMutableDictionary dictionaryWithDictionary:[_defs dictionaryForKey:UNSPENT_OUTPUTS_KEY]];
    
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

- (instancetype)initWithSeedPhrase:(NSString *)phrase
{
    if (! (self = [self init])) return nil;
    
    self.seedPhrase = phrase;
    
    return self;
}

- (instancetype)initWithSeed:(NSData *)seed
{
    if (! (self = [self init])) return nil;
    
    self.seed = seed;
    
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
    if (! seed || ! [self.seed isEqual:seed]) {
        @synchronized(self) {
            setKeychainData(seed, SEED_KEY);
        
            _synchronizing = NO;
            self.mpk = nil;
            [self.addresses removeAllObjects];
            [self.changeAddresses removeAllObjects];
            [self.outdatedAddresses removeAllObjects];
            [self.fundedAddresses removeAllObjects];
            [self.spentAddresses removeAllObjects];
            [self.receiveAddresses removeAllObjects];
            [self.transactions removeAllObjects];
            [self.unconfirmed removeAllObjects];
            [self.addressBalances removeAllObjects];
            [self.addressTxCount removeAllObjects];
            [self.unspentOutputs removeAllObjects];
            
            // flush cached addresses and tx outputs
            [_defs removeObjectForKey:FUNDED_ADDRESSES_KEY];
            [_defs removeObjectForKey:SPENT_ADDRESSES_KEY];
            [_defs removeObjectForKey:RECEIVE_ADDRESSES_KEY];
            [_defs removeObjectForKey:ADDRESS_BALANCES_KEY];
            [_defs removeObjectForKey:ADDRESS_TX_COUNT_KEY];
            [_defs removeObjectForKey:UNSPENT_OUTPUTS_KEY];
            [_defs removeObjectForKey:TRANSACTIONS_KEY];
            [_defs removeObjectForKey:UNCONFIRMED_KEY];
            [_defs removeObjectForKey:LAST_SYNC_TIME_KEY];
        }

        [_defs synchronize];
    }
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
    if (! _mpk) self.mpk = [self.sequence masterPublicKeyFromSeed:self.seed];
    return _mpk;
}

// if any of an unconfimred transaction's inputs show up as unspent, or show up in another transaction, that means the
// tx failed to confirm and needs to be removed from the pending unconfirmed tx list
- (void)cleanUnconfirmed
{
    //XXX should we remove unconfirmed transactions after 2 days?
    //XXX we should keep a seprate list of failed transactions to display along with the successful ones
    
    if (! self.unconfirmed.count) return;

    NSMutableSet *spent = [NSMutableSet set];
    
    @synchronized(self) {
        [self.transactions enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            [obj[@"inputs"] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                NSDictionary *o = obj[@"prev_out"];
                [spent addObject:[NSString stringWithFormat:@"%@:%@", o[@"tx_index"], o[@"n"]]];
            }];
        }];
    
        [self.unconfirmed
         removeObjectsForKeys:[self.unconfirmed keysOfEntriesPassingTest:^BOOL(id key, id obj, BOOL *stop) {
            // index of any inputs of the unconfirmed tx that are also in unspentOutputs
            NSUInteger i =
                [obj[@"inputs"] indexOfObjectPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
                    NSDictionary *o = obj[@"prev_out"];
                    NSString *key1 = [o[@"hash"] stringByAppendingString:[o[@"n"] description]];
                    NSString *key2 = [NSString stringWithFormat:@"%@:%@", o[@"tx_index"], o[@"n"]];
                    
                    return (self.unspentOutputs[key1] != nil || [spent containsObject:key2]) ? (*stop = YES) : NO;
                }];
                
            return (i == NSNotFound) ? NO : YES;
        }].allObjects];
    
        [_defs setObject:self.unconfirmed forKey:UNCONFIRMED_KEY];
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
    
    NSMutableArray *newAddresses = [NSMutableArray arrayWithCapacity:GAP_LIMIT_EXTERNAL + GAP_LIMIT_INTERNAL +
                                    self.fundedAddresses.count + self.spentAddresses.count];
    
    [newAddresses addObjectsFromArray:[self addressesWithGapLimit:GAP_LIMIT_EXTERNAL internal:NO]];
    [newAddresses addObjectsFromArray:[self addressesWithGapLimit:GAP_LIMIT_INTERNAL internal:YES]];
    [newAddresses addObjectsFromArray:self.fundedAddresses];
    [newAddresses addObjectsFromArray:self.spentAddresses];
    
    // An ARC retain loop when using block recursion is avoided here by passing the block to itself as an argument
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
    
        [newAddresses removeObjectsAtIndexes:[newAddresses
        indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
            return [self.spentAddresses containsObject:obj] || [self.fundedAddresses containsObject:obj];
        }]];
        
        if (newAddresses.count < GAP_LIMIT_EXTERNAL + GAP_LIMIT_INTERNAL) {
            [newAddresses setArray:[self addressesWithGapLimit:GAP_LIMIT_EXTERNAL internal:NO]];
            [newAddresses addObjectsFromArray:[self addressesWithGapLimit:GAP_LIMIT_INTERNAL internal:YES]];
            if (newAddresses.count) {
                [self queryAddresses:newAddresses completion:^(NSError *error) {
                    ((void (^)(NSError *, id))completion)(error, completion);
                }];
            }
            return;
        }
        
        @synchronized(self) {
            // remove unconfirmed transactions that no longer appear in query results
            //XXX we should keep a seprate list of failed transactions to display along with the successful ones
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
        [self queryAddresses:newAddresses completion:^(NSError *error) { completion(error, completion); }];
    });
}

- (NSArray *)addressesWithGapLimit:(NSUInteger)gapLimit internal:(BOOL)internal
{
    NSUInteger i = 0;
    NSString *a = nil;
    NSMutableArray *addresses = [NSMutableArray array];
    NSMutableArray *newaddresses = [NSMutableArray array];
    
    @synchronized(self) {
        while (addresses.count < gapLimit) {
            a = [[ZNKey keyWithPublicKey:[self.sequence publicKey:i++ internal:internal masterPublicKey:self.mpk]]
                 address];
        
            if (! a) {
                NSLog(@"error generating keys");
                return nil;
            }
        
            if (! internal && self.addresses.count < i) {
                [self.addresses addObject:a];
                [newaddresses addObject:a];
            }
        
            if (internal && self.changeAddresses.count < i) {
                [self.changeAddresses addObject:a];
                [newaddresses addObject:a];
            }
        
            if (! [self.spentAddresses containsObject:a] && ! [self.fundedAddresses containsObject:a]) {
                [addresses addObject:a];
            }
        }
    }
    
    if (newaddresses.count) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self subscribeToAddresses:newaddresses];
        });
    }
    
    return addresses;
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
                    NSString *address = obj[@"address"];
            
                    if (! address) return;
                    
                    [self.fundedAddresses removeObject:address];
                    [self.spentAddresses removeObject:address];
                    [self.receiveAddresses removeObject:address];
            
                    if ([obj[@"n_tx"] unsignedLongLongValue] > 0) {
                        if ([obj[@"n_tx"] unsignedIntegerValue] !=
                            [self.addressTxCount[address] unsignedIntegerValue]) {
                            [self.outdatedAddresses addObject:address];
                        }
            
                        self.addressBalances[address] = obj[@"final_balance"];
                        self.addressTxCount[address] = obj[@"n_tx"];
                        
                        if ([obj[@"final_balance"] unsignedLongLongValue] > 0) {
                            [self.fundedAddresses addObject:address];
                        }
                        else [self.spentAddresses addObject:address];
                    }
                    else [self.receiveAddresses addObject:address];
                }];
                
                [JSON[@"txs"] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                    //XXXX we shouldn't be saving json without sanitizing it... security risk
                    if (obj[@"hash"]) {
                        self.transactions[obj[@"hash"]] = obj;
                        [self.updatedTransactions addObject:obj[@"hash"]];
                    }
                }];
        
                NSInteger height = [JSON[@"info"][@"latest_block"][@"height"] integerValue];
                NSTimeInterval time = [JSON[@"info"][@"latest_block"][@"time"] doubleValue];
                NSString *symbol = JSON[@"info"][@"symbol_local"][@"symbol"];
                NSString *code = JSON[@"info"][@"symbol_local"][@"code"];
                double price = [JSON[@"info"][@"symbol_local"][@"conversion"] doubleValue];
        
                [self.unconfirmed removeObjectsForKeys:self.transactions.allKeys];
                
                [_defs setObject:self.fundedAddresses forKey:FUNDED_ADDRESSES_KEY];
                [_defs setObject:self.spentAddresses forKey:SPENT_ADDRESSES_KEY];
                [_defs setObject:self.receiveAddresses forKey:RECEIVE_ADDRESSES_KEY];
                [_defs setObject:self.addressBalances forKey:ADDRESS_BALANCES_KEY];
                [_defs setObject:self.addressTxCount forKey:ADDRESS_TX_COUNT_KEY];
                [_defs setObject:self.transactions forKey:TRANSACTIONS_KEY];
                [_defs setObject:self.unconfirmed forKey:UNCONFIRMED_KEY];
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
                    NSString *s = obj[@"script"];
                
                    if (! [s hasSuffix:SCRIPT_SUFFIX] || s.length < SCRIPT_SUFFIX.length + 40) return YES;
                    
                    NSString *hash160 = [s substringWithRange:NSMakeRange(s.length - SCRIPT_SUFFIX.length - 40, 40)];
                    NSString *address = [[@"00" stringByAppendingString:hash160] hexToBase58check];
                    
                    return (! address || [addresses containsObject:address]) ? YES : NO;
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
                    NSString *s = obj[@"script"];
                    
                    if (! [s hasSuffix:SCRIPT_SUFFIX] || s.length < SCRIPT_SUFFIX.length + 40) return YES;
                    
                    NSString *hash160 = [s substringWithRange:NSMakeRange(s.length - SCRIPT_SUFFIX.length - 40, 40)];
                    NSString *address = [[@"00" stringByAppendingString:hash160] hexToBase58check];
                    
                    return (! address || [addresses containsObject:address]) ? YES : NO;
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
    
    [self.addressBalances enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        balance += [obj unsignedLongLongValue];
    }];
    
    return balance;
}

//XXXX recieve/change addresses shouldn't advance until the transaction involving it has 6 confimations

- (NSString *)receiveAddress
{
    if (! self.receiveAddresses.count || ! self.addresses.count) {
        NSUInteger i = 0;
        NSString *a = nil;
        
        @synchronized(self) {
            while (! a || [self.spentAddresses containsObject:a] || [self.fundedAddresses containsObject:a]) {
                a = [[ZNKey keyWithPublicKey:[self.sequence publicKey:i++ internal:NO masterPublicKey:self.mpk]]
                     address];
                
                if (! a) return nil;
                
                if (self.addresses.count < i) [self.addresses addObject:a];
            }
        
            if (! [self.receiveAddresses containsObject:a]) [self.receiveAddresses addObject:a];
        }
    }
    
    return [self.addresses firstObjectCommonWithArray:self.receiveAddresses];
}

- (NSString *)changeAddress
{
    if (! self.receiveAddresses.count || ! self.changeAddresses.count) {
        NSUInteger i = 0;
        NSString *a = nil;
        
        @synchronized(self) {
            while (! a || [self.spentAddresses containsObject:a] || [self.fundedAddresses containsObject:a]) {
                a = [[ZNKey keyWithPublicKey:[self.sequence publicKey:i++ internal:YES masterPublicKey:self.mpk]]
                     address];
            
                if (! a) return nil;
            
                if (self.changeAddresses.count < i) [self.changeAddresses addObject:a];
            }
        
            if (! [self.receiveAddresses containsObject:a]) [self.receiveAddresses addObject:a];
        }
    }
    
    return [self.changeAddresses firstObjectCommonWithArray:self.receiveAddresses];
}

- (NSArray *)recentTransactions
{
    // sort in descending order by timestamp (using block_height doesn't work for unconfirmed, or multiple tx per block)
    return [[self.transactions.allValues arrayByAddingObjectsFromArray:self.unconfirmed.allValues]
           sortedArrayWithOptions:0 usingComparator:^NSComparisonResult(id obj1, id obj2) {
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
    return [self.spentAddresses containsObject:address] || [self.fundedAddresses containsObject:address] ||
           [self.receiveAddresses containsObject:address];
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

//XXX as block space becomes harder to come by, we can calculate the median of the lowest fee-per-kb that made it into
// the previous 100 blocks
- (ZNTransaction *)transactionFor:(uint64_t)amount to:(NSString *)address withFee:(BOOL)fee
{
    __block uint64_t balance = 0, standardFee = 0;
    uint64_t minChange = fee ? TX_MIN_OUTPUT_AMOUNT : TX_FREE_MIN_OUTPUT;
    ZNTransaction *tx = [ZNTransaction new];

    [tx addOutputAddress:address amount:amount];

    @synchronized(self) {
        //XXX we should optimize for free transactions (watch out for performance issues, nothing O(n^2) please)
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
            if (fee) standardFee = ((tx.size + 34 + 999)/1000)*TX_FEE_PER_KB;
            
            if (balance == amount + standardFee || balance >= amount + standardFee + minChange) *stop = YES;
        }];
    
        if (balance < amount + standardFee) { // insufficent funds
            NSLog(@"Insufficient funds. %llu is less than transaction amount:%llu", balance, amount + standardFee);
            return nil;
        }
    
        //XXX we should randomly swap order of outputs so the change address isn't publicy known
        if (balance - (amount + standardFee) >= TX_MIN_OUTPUT_AMOUNT) {
            [tx addOutputAddress:self.changeAddress amount:balance - (amount + standardFee)];
        }
    }
    
    return tx;
}

// returns the estimated time in seconds until the transaction will be processed without a fee
//XXX this is based on the default satoshi client settings, but on the real network it's way off. in testing, a 0.01btc
// transaction with a 90 day time until free was confirmed in under an hour by Eligius pool.
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
            if ([self.addresses indexOfObject:obj] == NSNotFound) {
                if ([self.changeAddresses indexOfObject:obj] == NSNotFound) {
                    NSLog(@"[%s %s] line %d: missing key", object_getClassName(self), sel_getName(_cmd), __LINE__);
                    *stop = YES;
                }
                else [changeKeyIndexes addObject:@([self.changeAddresses indexOfObject:obj])];
            }
            else [keyIndexes addObject:@([self.addresses indexOfObject:obj])];
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
        NSMutableSet *updated = [NSMutableSet set];
        NSMutableDictionary *tx = [NSMutableDictionary dictionary];
        
        tx[@"hash"] = [NSString hexWithData:transaction.hash];
        tx[@"time"] = @([NSDate timeIntervalSinceReferenceDate] + NSTimeIntervalSince1970);
        tx[@"inputs"] = [NSMutableArray array];
        tx[@"out"] = [NSMutableArray array];
        
        //XXX successful response is "Transaction submitted", maybe we should check for that 
        NSLog(@"responseObject: %@", responseObject);
        NSLog(@"response:\n%@", operation.responseString);
        
        @synchronized(self) {
            [transaction.inputAddresses enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                NSString *hash = [NSString hexWithData:transaction.inputHashes[idx]];
                NSString *n = [transaction.inputIndexes[idx] description];
                NSDictionary *o = self.unspentOutputs[[hash stringByAppendingString:n]];
            
                if (o) {
                    uint64_t balance = [self.addressBalances[obj] unsignedLongLongValue] -
                                       [o[@"value"] unsignedLongLongValue];

                    self.addressBalances[obj] = @(balance);

                    [updated addObject:obj];
                    [self.unspentOutputs removeObjectForKey:[hash stringByAppendingString:n]];
                
                    if (balance == 0) {
                        [self.fundedAddresses removeObject:obj];
                        if (! [self.spentAddresses containsObject:obj]) [self.spentAddresses addObject:obj];
                    }
                
                    //XXX for now we don't need to store spent outputs because blockchain.info will not list them as
                    // unspent while there is an unconfirmed tx that spends them. This may change once we have multiple
                    // apis for publishing, and a transaction may not show up on blockchain.info immediately.
                    [tx[@"inputs"] addObject:@{@"prev_out":@{@"hash":o[@"tx_hash"], @"tx_index":o[@"tx_index"],
                                               @"n":o[@"tx_output_n"], @"value":o[@"value"], @"addr":obj}}];
                }
            }];
        
            [transaction.outputAddresses enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                [tx[@"out"] addObject:@{@"n":@(idx), @"value":transaction.outputAmounts[idx], @"addr":obj}];
            }];
        
            // don't update addressTxCount so the address's unspent outputs will be updated on next sync
            //[updated enumerateObjectsUsingBlock:^(id obj, BOOL *stop) {
            //    self.addressTxCount[obj] = @([self.addressTxCount[obj] unsignedIntegerValue] + 1);
            //}];
        
            self.unconfirmed[tx[@"hash"]] = tx;
        
            [_defs setObject:self.fundedAddresses forKey:FUNDED_ADDRESSES_KEY];
            [_defs setObject:self.spentAddresses forKey:SPENT_ADDRESSES_KEY];
            [_defs setObject:self.unspentOutputs forKey:UNSPENT_OUTPUTS_KEY];
            [_defs setObject:self.addressBalances forKey:ADDRESS_BALANCES_KEY];
            [_defs setObject:self.addressTxCount forKey:ADDRESS_TX_COUNT_KEY];
            [_defs setObject:self.unconfirmed forKey:UNCONFIRMED_KEY];
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

    //XXX also publish transactions directly to coinbase and bitpay servers for faster POS experience
}

@end
