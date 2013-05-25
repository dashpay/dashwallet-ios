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
#define UNSPENT_OUTPUTS_KEY @"UNSPENT_OUTPUTS"

#define TX_FEE_07 // 0.7 reference implementation tx fees

#define SEC_ATTR_SERVICE @"cc.zinc.zincwallet"

@interface ZNWallet ()

@property (nonatomic, strong) NSUserDefaults *defs;
@property (nonatomic, strong) NSMutableArray *spentAddresses;
@property (nonatomic, strong) NSMutableArray *fundedAddresses;
@property (nonatomic, strong) NSMutableArray *receiveAddresses;
@property (nonatomic, strong) NSMutableDictionary *unspentOutputs;
@property (nonatomic, strong) NSMutableDictionary *addressBalances;
@property (nonatomic, strong) NSMutableDictionary *privateKeys;

@end

@implementation ZNWallet

+ (ZNWallet *)singleton
{
    static ZNWallet *singleton = nil;
    static dispatch_once_t onceToken = 0;
    
    dispatch_once(&onceToken, ^{
        singleton = [[ZNWallet alloc] init];
    });

    return singleton;
}

- (id)init
{
    if (! (self = [super init])) return nil;
    
    self.defs = [NSUserDefaults standardUserDefaults];
    
    self.fundedAddresses = [NSMutableArray arrayWithArray:[_defs arrayForKey:FUNDED_ADDRESSES_KEY]];
    self.spentAddresses = [NSMutableArray arrayWithArray:[_defs arrayForKey:SPENT_ADDRESSES_KEY]];
    self.receiveAddresses = [NSMutableArray arrayWithArray:[_defs arrayForKey:RECEIVE_ADDRESSES_KEY]];
    self.addressBalances = [NSMutableDictionary dictionaryWithDictionary:[_defs dictionaryForKey:ADDRESS_BALANCES_KEY]];
    self.unspentOutputs = [NSMutableDictionary dictionary];
    [[_defs dictionaryForKey:UNSPENT_OUTPUTS_KEY] enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        self.unspentOutputs[key] = [NSMutableArray arrayWithArray:obj];
    }];
    
    //XXX for testing only! these should be generated from backup passphrase    
    self.privateKeys = [NSMutableDictionary dictionary];
    
    [[self getKeychainObjectForKey:@"pkeys"] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        self.privateKeys[[[ZNKey alloc] initWithPrivateKey:obj].address] = obj;
    }];
    
    [self queryAddresses:self.privateKeys.allKeys];
    
    return self;
}

- (id)initWithSeed:(NSString *)seed
{
    return [self init];
}

- (double)balance
{
    __block uint64_t balance = 0;
    
    [self.addressBalances enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        balance += [obj unsignedLongLongValue];
    }];
    
    return balance/SATOSHIS;
}

- (NSString *)receiveAddress
{
    return self.receiveAddresses.lastObject;
}

// query blockchain for the given addresses
- (void)queryAddresses:(NSArray *)addresses
{
    if (! addresses.count) return;

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

            self.addressBalances[address] = obj[@"final_balance"];
            
            if ([obj[@"n_tx"] unsignedLongLongValue] > 0) {
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
        
        [_defs setObject:self.fundedAddresses forKey:FUNDED_ADDRESSES_KEY];
        [_defs setObject:self.spentAddresses forKey:SPENT_ADDRESSES_KEY];
        [_defs setObject:self.receiveAddresses forKey:RECEIVE_ADDRESSES_KEY];
        [_defs setObject:self.addressBalances forKey:ADDRESS_BALANCES_KEY];
        [_defs synchronize];
        
        [self queryUnspentOutputs:self.fundedAddresses];
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
        NSLog(@"%@", error.localizedDescription);
    }] start];
}

// query blockchain for unspent outputs of the given addresses
- (void)queryUnspentOutputs:(NSArray *)addresses
{
    if (! addresses.count) return;
    
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

            if (! addresses) return;
              
            if (! self.unspentOutputs[address]) self.unspentOutputs[address] = [NSMutableArray arrayWithObject:obj];
            else [self.unspentOutputs[address] addObject:obj];
        }];
        
        [_defs setObject:self.unspentOutputs forKey:UNSPENT_OUTPUTS_KEY];
        [_defs synchronize];
          
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
        NSLog(@"%@", error.localizedDescription);
    }] start];
}
 
- (NSString *)transactionFor:(double)amount to:(NSString *)address
{
    __block uint64_t amt = amount*SATOSHIS, balance = 0;
    __block NSMutableSet *inKeys = [NSMutableSet set];
    __block NSMutableArray *inHashes = [NSMutableArray array], *inIndexes = [NSMutableArray array],
                           *inScripts = [NSMutableArray array];
    NSMutableArray *outAddresses = [NSMutableArray arrayWithObject:address],
                   *outAmounts = [NSMutableArray arrayWithObject:@(amt)];


    //XXX we should optimize for free transactions (watch out for performance issues, nothing O(n^2) please)
    // this is a nieve implementation to just get it functional
    [self.unspentOutputs enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        if (! self.privateKeys[key]) return;

        [inKeys addObject:self.privateKeys[key]];
        
        [obj enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            // tx_hash is already in little endian
            [inHashes addObject:[NSData dataWithHex:obj[@"tx_hash"]]];
            [inIndexes addObject:obj[@"tx_output_n"]];
            [inScripts addObject:[NSData dataWithHex:obj[@"script"]]];
            balance += [obj[@"value"] unsignedLongLongValue];
            
            if (balance == amt || balance >= amt + 0.01) *stop = YES;
        }];
        
        if (balance == amt || balance >= amt + 0.01) *stop = YES;
    }];
    
    if (balance < amt) { // insufficent funds
        NSLog(@"Insufficient funds. Balance:%llu is less than transaction amount:%llu", balance, amt);
        return nil;
    }
    
    //XXX need to calculate tx fees, especially if change is less than 0.01
    if (balance > amt) {
        [outAddresses addObject:self.receiveAddress]; // change address
        [outAmounts addObject:@(balance - amt)];
    }
    
    ZNTransaction *tx = [[ZNTransaction alloc] initWithInputHashes:inHashes inputIndexes:inIndexes
                         inputScripts:inScripts outputAddresses:outAddresses andOutputAmounts:outAmounts];
    
    [tx signWithPrivateKeys:inKeys.allObjects];
    
    if (! [tx isSigned]) {
        NSLog(@"this should never happen");
        return nil;
    }
    
    return [tx toHex];

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
