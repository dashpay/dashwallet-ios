//
//  ZNWallet.m
//  ZincWallet
//
//  Created by Aaron Voisine on 5/12/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import "ZNWallet.h"
#import "ZNTransaction.h"
#import "ZNKey.h"
#import "ZNElectrumSequence.h"
#import "NSData+Hash.h"
#import "NSString+Base58.h"
#import "AFNetworking.h"
#import <Security/Security.h>

#define UNSPENT_URL @"http://blockchain.info/unspent?active="
#define ADDRESS_URL @"http://blockchain.info/multiaddr?active="

#define SCRIPT_SUFFIX @"88ac" // OP_EQUALVERIFY OP_CHECKSIG

#define FUNDED_ADDRESSES_KEY @"FUNDED_ADDRESSES"
#define SPENT_ADDRESSES_KEY @"SPENT_ADDRESSES"
#define RECEIVE_ADDRESSES_KEY @"RECEIVE_ADDRESSES"
#define ADDRESS_BALANCES_KEY @"ADDRESS_BALANCES"
#define ADDRESS_TX_COUNT_KEY @"ADDRESS_TX_COUNT"
#define UNSPENT_OUTPUTS_KEY @"UNSPENT_OUTPUTS"
#define TRANSACTIONS_KEY @"TRANSACTIONS"
#define SEED_KEY @"seed"

#define SEC_ATTR_SERVICE @"cc.zinc.zincwallet"

@interface ZNWallet ()

@property (nonatomic, strong) NSUserDefaults *defs;
@property (nonatomic, strong) NSMutableArray *addresses, *changeAddresses;
@property (nonatomic, strong) NSMutableArray *spentAddresses, *fundedAddresses, *receiveAddresses;
@property (nonatomic, strong) NSMutableDictionary *unspentOutputs;
@property (nonatomic, strong) NSMutableDictionary *addressBalances;
@property (nonatomic, strong) NSMutableDictionary *addressTxCount;
@property (nonatomic, strong) NSMutableDictionary *transactions;
@property (nonatomic, strong) NSMutableSet *outdatedAddresses;
@property (nonatomic, strong) NSMutableDictionary *privateKeys;
@property (nonatomic, strong) ZNElectrumSequence *sequence;
@property (nonatomic, strong) NSData *mpk;

@end

@implementation ZNWallet

+ (ZNWallet *)sharedInstance
{
    static ZNWallet *singleton = nil;
    static dispatch_once_t onceToken = 0;
    
    dispatch_once(&onceToken, ^{
        singleton = [ZNWallet new];
    });

    return singleton;
}

- (id)init
{
    if (! (self = [super init])) return nil;
    
    self.defs = [NSUserDefaults standardUserDefaults];
    
    //XXX we should be using core data for this... ugh
    self.addresses = [NSMutableArray array];
    self.changeAddresses = [NSMutableArray array];
    self.fundedAddresses = [NSMutableArray arrayWithArray:[_defs arrayForKey:FUNDED_ADDRESSES_KEY]];
    self.spentAddresses = [NSMutableArray arrayWithArray:[_defs arrayForKey:SPENT_ADDRESSES_KEY]];
    self.receiveAddresses = [NSMutableArray arrayWithArray:[_defs arrayForKey:RECEIVE_ADDRESSES_KEY]];
    self.transactions = [NSMutableDictionary dictionaryWithDictionary:[_defs dictionaryForKey:TRANSACTIONS_KEY]];
    self.addressBalances = [NSMutableDictionary dictionaryWithDictionary:[_defs dictionaryForKey:ADDRESS_BALANCES_KEY]];
    self.addressTxCount = [NSMutableDictionary dictionaryWithDictionary:[_defs dictionaryForKey:ADDRESS_TX_COUNT_KEY]];
    self.unspentOutputs = [NSMutableDictionary dictionary];
    [[_defs dictionaryForKey:UNSPENT_OUTPUTS_KEY] enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        self.unspentOutputs[key] = [NSMutableArray arrayWithArray:obj];
    }];
    
    self.outdatedAddresses = [NSMutableSet set];
    
    self.sequence = [ZNElectrumSequence new];
    
    self.format = [NSNumberFormatter new];
    self.format.numberStyle = NSNumberFormatterCurrencyStyle;
    self.format.currencySymbol = @"m"BTC@" ";
    self.format.minimumFractionDigits = 0;
    self.format.maximumFractionDigits = 5;
    self.format.maximum = @21000000000.0;
    [self.format setLenient:YES];
    
    return self;
}

- (id)initWithSeedPhrase:(NSString *)phrase
{
    if (! (self = [self init])) return nil;
    
    self.seedPhrase = phrase;
    
    return self;
}

- (id)initWithSeed:(NSData *)seed
{
    if (! (self = [self init])) return nil;
    
    self.seed = seed;
    
    return self;
}

- (NSData *)seed
{
    return [self getKeychainObjectForKey:SEED_KEY];
}

- (void)setSeed:(NSData *)seed
{
    if (! [self.seed isEqual:seed]) {        
        [self setKeychainObject:seed forKey:SEED_KEY];
        
        // flush cached addresses and tx outputs
        [_defs removeObjectForKey:FUNDED_ADDRESSES_KEY];
        [_defs removeObjectForKey:SPENT_ADDRESSES_KEY];
        [_defs removeObjectForKey:RECEIVE_ADDRESSES_KEY];
        [_defs removeObjectForKey:ADDRESS_BALANCES_KEY];
        [_defs removeObjectForKey:ADDRESS_TX_COUNT_KEY];
        [_defs removeObjectForKey:UNSPENT_OUTPUTS_KEY];
        [_defs removeObjectForKey:TRANSACTIONS_KEY];
        [_defs synchronize];
    }
}

- (NSString *)seedPhrase
{
    NSData *seed = [NSData dataWithHex:[[NSString alloc] initWithData:self.seed encoding:NSUTF8StringEncoding]];

    return [self encodePhrase:seed];
}

- (void)setSeedPhrase:(NSString *)seedPhrase
{
    // Electurm uses a hex representation of the decoded seed instead of the seed itself
    self.seed = [[[self decodePhrase:seedPhrase] toHex] dataUsingEncoding:NSUTF8StringEncoding];
}

//# Note about US patent no 5892470: Here each word does not represent a given digit.
//# Instead, the digit represented by a word is variable, it depends on the previous word.
//
//def mn_encode( message ):
//    out = []
//    for i in range(len(message)/8):
//        word = message[8*i:8*i + 8]
//        x = int(word, 16)
//        w1 = (x % n)
//        w2 = ((x/n) + w1) % n
//        w3 = ((x/n/n) + w2) % n
//        out += [ words[w1], words[w2], words[w3] ]
//    return out
//
- (NSString *)encodePhrase:(NSData *)d
{
    NSMutableArray *list = [NSMutableArray arrayWithCapacity:d.length*3/4];
    NSArray *words = [NSArray arrayWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"ElectrumSeedWords"
                      ofType:@"plist"]];
    uint32_t n = words.count;
    
    for (int i = 0; i*sizeof(uint32_t) < d.length; i++) {
        uint32_t x = CFSwapInt32BigToHost(*((uint32_t *)d.bytes + i));
        uint32_t w1 = x % n;
        uint32_t w2 = ((x/n) + w1) % n;
        uint32_t w3 = ((x/n/n) + w2) % n;
        
        [list addObject:words[w1]];
        [list addObject:words[w2]];
        [list addObject:words[w3]];
    }
    
    words = nil;
    
    return [list componentsJoinedByString:@" "];
}

//def mn_decode( wlist ):
//    out = ''
//    for i in range(len(wlist)/3):
//        word1, word2, word3 = wlist[3*i:3*i + 3]
//        w1 =  words.index(word1)
//        w2 = (words.index(word2)) % n
//        w3 = (words.index(word3)) % n
//        x = w1 + n*((w2 - w1) % n) + n*n*((w3 - w2) % n)
//        out += '%08x'%x
//    return out
//
- (NSData *)decodePhrase:(NSString *)phrase
{
    NSArray *list = [phrase componentsSeparatedByString:@" "];
    NSArray *words = [NSArray arrayWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"ElectrumSeedWords"
                      ofType:@"plist"]];
    NSMutableData *d = [NSMutableData dataWithCapacity:list.count*4/3];
    int32_t n = words.count;
    
    if (list.count != 12) {
        NSLog(@"phrase should be 12 words, found %d instead", list.count);
        return nil;
    }
    
    for (NSUInteger i = 0; i < list.count; i += 3) {
        int32_t w1 = [words indexOfObject:list[i]], w2 = [words indexOfObject:list[i + 1]],
        w3 = [words indexOfObject:list[i + 2]];
        
        if (w1 == NSNotFound || w2 == NSNotFound || w3 == NSNotFound) {
            NSLog(@"phrase contained unknown word: %@", list[i + (w1 == NSNotFound ? 0 : w2 == NSNotFound ? 1 : 2)]);
            return nil;
        }
        
        // python's modulo behaves differently than C when dealing with negative numbers
        // the equivalent of python's (n % M) in C is (((n % M) + M) % M)
        int32_t x = w1 + n*((((w2 - w1) % n) + n) % n) + n*n*((((w3 - w2) % n) + n) % n);
        
        x = CFSwapInt32HostToBig(x);
        
        [d appendBytes:&x length:sizeof(x)];
    }
    
    words = nil;
    
    return d;
}

- (void)generateRandomSeed
{
    NSMutableData *seed = [NSMutableData dataWithLength:ELECTRUM_SEED_LENGTH];
    
    SecRandomCopyBytes(kSecRandomDefault, seed.length, seed.mutableBytes);
    
    // Electurm uses a hex representation of the seed value instead of the seed itself
    self.seed = [[seed toHex] dataUsingEncoding:NSUTF8StringEncoding];
}

- (uint64_t)balance
{
    __block uint64_t balance = 0;
    
    [self.addressBalances enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        balance += [obj unsignedLongLongValue];
    }];
    
    return balance;
}

- (NSString *)receiveAddress
{
    if (! self.receiveAddresses.count) {
        NSUInteger i = 0;
        NSString *a = nil;
        
        while (! a || [self.spentAddresses containsObject:a] || [self.fundedAddresses containsObject:a]) {
            a = [(ZNKey *)[ZNKey keyWithPublicKey:[self.sequence publicKey:i++ forChange:NO masterPublicKey:self.mpk]]
                 address];
        
            if (! a) return nil;
            
            if (self.addresses.count < i) {
                [self.addresses addObject:a];
            }
        }
   
        [self.receiveAddresses addObject:a];
    }

    return [self.addresses firstObjectCommonWithArray:self.receiveAddresses];
}

- (NSArray *)recentTransactions
{
    // sort in descending order by timestamp (using block_height doesn't work for unconfirmed, or multiple tx per block)
    return [self.transactions.allValues sortedArrayWithOptions:0 usingComparator:^NSComparisonResult(id obj1, id obj2) {
        return [@([obj2[@"time"] unsignedLongLongValue]) compare:@([obj1[@"time"] unsignedLongLongValue])];
    }];
}

- (NSData *)mpk
{
    if (! _mpk) {
        _mpk = [self.sequence masterPublicKeyFromSeed:self.seed];
    }
    
    return _mpk;
}

- (void)synchronize
{
    //XXX after the gap limit is hit, we should go back and check all spent and funded addresses for new transactions
    //XXX also need to throttle to avoid blockchain.info api limits
    
    if (_synchronizing) return;
    
    _synchronizing = YES;
    [[NSNotificationCenter defaultCenter] postNotificationName:walletSyncStartedNotification object:self];
    
    [self synchronizeWithGapLimit:ELECTURM_GAP_LIMIT forChange:NO completion:^(NSError *error) {
        if (! error) {
            [self synchronizeWithGapLimit:ELECTURM_GAP_LIMIT_FOR_CHANGE forChange:YES completion:^(NSError *error) {
                _synchronizing = NO;
                if (! error) {
                    [[NSNotificationCenter defaultCenter] postNotificationName:walletSyncFinishedNotification
                     object:self];
                }
                else {
                    [[NSNotificationCenter defaultCenter] postNotificationName:walletSyncFailedNotification
                     object:self userInfo:@{@"error":error}];
                }
            }];
        }
        else {
            _synchronizing = NO;
            [[NSNotificationCenter defaultCenter] postNotificationName:walletSyncFailedNotification object:self
             userInfo:@{@"error":error}];
        }
    }];
}

- (void)synchronizeWithGapLimit:(NSUInteger)gapLimit forChange:(BOOL)forChange
completion:(void (^)(NSError *error))completion
{    
    NSUInteger i = 0;
    NSMutableArray *newAddresses = [NSMutableArray array];
    
    while (newAddresses.count < gapLimit) {
        NSString *a = [(ZNKey *)[ZNKey keyWithPublicKey:[self.sequence publicKey:i++ forChange:forChange
                       masterPublicKey:self.mpk]] address];

        if (! a) {
            NSLog(@"error generating keys");
            if (completion) completion(NO);
            return;
        }
        
        if (! forChange && self.addresses.count < i) {
            [self.addresses addObject:a];
        }

        if (forChange && self.changeAddresses.count < i) {
            [self.changeAddresses addObject:a];
        }
        
        if (! [self.spentAddresses containsObject:a] && ! [self.fundedAddresses containsObject:a]) {
            [newAddresses addObject:a];
        }
    }
    
    [self queryAddresses:newAddresses completion:^(NSError *error) {
        [newAddresses removeObjectsAtIndexes:[newAddresses
        indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
            return [self.spentAddresses containsObject:obj] || [self.fundedAddresses containsObject:obj];
        }]];
        
        if (newAddresses.count < gapLimit) {
            [self synchronizeWithGapLimit:gapLimit forChange:forChange completion:completion];
        }
        else if (self.outdatedAddresses.count) {
            //XXX need to break this up into chunks if too large
            [self queryUnspentOutputs:[self.outdatedAddresses allObjects] completion:completion];
        }
        else if (completion) completion(error);
    }];    
}

// query blockchain for the given addresses
- (void)queryAddresses:(NSArray *)addresses completion:(void (^)(NSError *error))completion
{
    if (! addresses.count) {
        if (completion) completion(nil);
        return;
    }

    NSURL *url = [NSURL URLWithString:[ADDRESS_URL stringByAppendingString:[[addresses componentsJoinedByString:@"|"]
                  stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]]];
    
    [[AFJSONRequestOperation JSONRequestOperationWithRequest:[NSURLRequest requestWithURL:url]
    success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        [JSON[@"addresses"] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            NSString *address = obj[@"address"];
            
            if (! address) return;

            [self.fundedAddresses removeObject:address];
            [self.spentAddresses removeObject:address];
            [self.receiveAddresses removeObject:address];
            
            if ([obj[@"n_tx"] unsignedLongLongValue] > 0) {
                if ([obj[@"n_tx"] unsignedIntegerValue] != [self.addressTxCount[address] unsignedIntegerValue]) {
                    [self.outdatedAddresses addObject:address];
                }
            
                self.addressBalances[address] = obj[@"final_balance"];
                self.addressTxCount[address] = obj[@"n_tx"];

                if ([obj[@"final_balance"] unsignedLongLongValue] > 0) {
                    [self.fundedAddresses addObject:address];
                }
                else {
                    [self.spentAddresses addObject:address];
                }
            }
            else {
                [self.receiveAddresses addObject:address];
            }
        }];
        
        [JSON[@"txs"] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {            
            if (obj[@"hash"]) self.transactions[obj[@"hash"]] = obj;
        }];
        
        [_defs setObject:self.fundedAddresses forKey:FUNDED_ADDRESSES_KEY];
        [_defs setObject:self.spentAddresses forKey:SPENT_ADDRESSES_KEY];
        [_defs setObject:self.receiveAddresses forKey:RECEIVE_ADDRESSES_KEY];
        [_defs setObject:self.addressBalances forKey:ADDRESS_BALANCES_KEY];
        [_defs setObject:self.addressTxCount forKey:ADDRESS_TX_COUNT_KEY];
        [_defs setObject:self.transactions forKey:TRANSACTIONS_KEY];
        [_defs synchronize];
        
        //[self queryUnspentOutputs:self.fundedAddresses];
        
        if (completion) completion(nil);
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
        NSLog(@"%@", error.localizedDescription);
        
        if (completion) completion(error);
    }] start];
}

// query blockchain for unspent outputs of the given addresses
//
//{
//  "unspent_outputs": [
//    {
//      "tx_hash": "5a94b62fc68b6c158dafa327b6a61606e18f093c421b64ddb617267c430d13dd",
//      "tx_index": 56887126,
//      "tx_output_n": 1,
//      "script": "76a91404f05543b270f96547c950a2b3ed3afe83d0386988ac",
//      "value": 600000,
//      "value_hex": "0927c0",
//      "confirmations": 14946
//    }
//  ]
//}
//
- (void)queryUnspentOutputs:(NSArray *)addresses completion:(void (^)(NSError *error))completion
{
    if (! addresses.count) {
        if (completion) completion(nil);
        return;
    }
    
    NSURL *url = [NSURL URLWithString:[UNSPENT_URL stringByAppendingString:[[addresses componentsJoinedByString:@"|"]
                  stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]]];
    
    [[AFJSONRequestOperation JSONRequestOperationWithRequest:[NSURLRequest requestWithURL:url]
    success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        //XXX verify response success before clearing out previous unspent outputs
        [self.unspentOutputs removeObjectsForKeys:addresses];
        
        [JSON[@"unspent_outputs"] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            NSString *script = obj[@"script"];
            
            if (! [script hasSuffix:SCRIPT_SUFFIX] || script.length < SCRIPT_SUFFIX.length + 40) return;

            NSString *address = [[@"00" stringByAppendingString:[script
                                  substringWithRange:NSMakeRange(script.length - SCRIPT_SUFFIX.length - 40, 40)]]
                                 hexToBase58check];

            if (! address) return;
            
            if (! self.unspentOutputs[address]) self.unspentOutputs[address] = [NSMutableArray arrayWithObject:obj];
            else [self.unspentOutputs[address] addObject:obj];
            
            [self.outdatedAddresses removeObject:address];
        }];
        
        [_defs setObject:self.unspentOutputs forKey:UNSPENT_OUTPUTS_KEY];
        [_defs synchronize];

        if (completion) completion(nil);
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
        NSLog(@"%@", error.localizedDescription);
        if (completion) completion(error);
    }] start];
}

- (NSString *)transactionFor:(uint64_t)amount to:(NSString *)address
{
    __block uint64_t balance = 0;
    __block NSMutableSet *inKeys = [NSMutableSet set];
    __block NSMutableArray *inHashes = [NSMutableArray array], *inIndexes = [NSMutableArray array],
                           *inScripts = [NSMutableArray array];
    NSMutableArray *outAddresses = [NSMutableArray arrayWithObject:address],
                   *outAmounts = [NSMutableArray arrayWithObject:@(amount)];


    //XXX we should optimize for free transactions (watch out for performance issues, nothing O(n^2) please)
    // this is a nieve implementation to just get it functional
    [self.unspentOutputs enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        //XXX calculate private keys on the fly
        if (! self.privateKeys[key]) return;

        [inKeys addObject:self.privateKeys[key]];
        
        [obj enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            // tx_hash is already in little endian
            [inHashes addObject:[NSData dataWithHex:obj[@"tx_hash"]]];
            [inIndexes addObject:obj[@"tx_output_n"]];
            [inScripts addObject:[NSData dataWithHex:obj[@"script"]]];
            balance += [obj[@"value"] unsignedLongLongValue];
            
            if (balance == amount || balance >= amount + TX_FREE_MIN_OUTPUT) *stop = YES;
        }];
        
        if (balance == amount || balance >= amount + TX_FREE_MIN_OUTPUT) *stop = YES;
    }];
    
    if (balance < amount) { // insufficent funds
        NSLog(@"Insufficient funds. Balance:%llu is less than transaction amount:%llu", balance, amount);
        return nil;
    }
    
    //XXX need to calculate tx fees, especially if change is less than 0.01
    if (balance > amount) {
        [outAddresses addObject:self.receiveAddress]; // change address
        [outAmounts addObject:@(balance - amount)];
    }
    
    ZNTransaction *tx = [[ZNTransaction alloc] initWithInputHashes:inHashes inputIndexes:inIndexes
                         inputScripts:inScripts outputAddresses:outAddresses andOutputAmounts:outAmounts];
    
    //XXX check if tx.size >= TX_MAX_SIZE
    
    [tx signWithPrivateKeys:inKeys.allObjects];
    
    if (! [tx isSigned]) {
        NSAssert(FALSE, @"[%s %s] line %d: tx signing failed", object_getClassName(self), sel_getName(_cmd), __LINE__);
        return nil;
    }
    
    return [tx toHex];
}

- (BOOL)containsAddress:(NSString *)address
{
    return [self.spentAddresses containsObject:address] || [self.fundedAddresses containsObject:address] ||
           [self.receiveAddresses containsObject:address];
}

- (NSString *)stringForAmount:(uint64_t)amount
{
    return [self.format stringFromNumber:@(amount/pow(10, self.format.maximumFractionDigits))];
}

#pragma mark - keychain services

- (BOOL)setKeychainObject:(id)obj forKey:(NSString *)key
{
    NSDictionary *query = @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
                            (__bridge id)kSecAttrService:SEC_ATTR_SERVICE,
                            (__bridge id)kSecAttrAccount:key,
                            (__bridge id)kSecReturnData:(__bridge id)kCFBooleanTrue};
    
    NSDictionary *item = @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
                           (__bridge id)kSecAttrService:SEC_ATTR_SERVICE,
                           (__bridge id)kSecAttrAccount:key,
                           (__bridge id)kSecAttrAccessible:(__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                           (__bridge id)kSecValueData:[NSKeyedArchiver archivedDataWithRootObject:obj]};
    
    SecItemDelete((__bridge CFDictionaryRef)query);
    
    if (SecItemAdd((__bridge CFDictionaryRef)item, NULL) != noErr) {
        NSLog(@"SecItemAdd error");
        return NO;
    }

    return YES;
}

- (id)getKeychainObjectForKey:(NSString *)key
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

    return [NSKeyedUnarchiver unarchiveObjectWithData:(__bridge_transfer NSData*)result];
}

@end
