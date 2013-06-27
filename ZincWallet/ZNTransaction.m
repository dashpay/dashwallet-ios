//
//  ZNTransaction.m
//  ZincWallet
//
//  Created by Aaron Voisine on 5/16/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import "ZNTransaction.h"
#import "NSMutableData+Bitcoin.h"
#import "NSData+Hash.h"
#import "NSString+Base58.h"
#import "ZNKey.h"

#define TX_VERSION      0x00000001u
#define TX_LOCKTIME     0x00000000u
#define TXIN_SEQUENCE   UINT32_MAX
#define TXOUT_PUBKEYLEN 25
#define SIGHASH_ALL     0x00000001u

@interface ZNTransaction ()

@property (nonatomic, strong) NSMutableArray *hashes, *indexes, *scripts;
@property (nonatomic, strong) NSMutableArray *addresses, *amounts;
@property (nonatomic, strong) NSMutableArray *signatures;

@end

@implementation ZNTransaction

- (id)init
{
    if (! (self = [super init])) return nil;
        
    self.hashes = [NSMutableArray array];
    self.indexes = [NSMutableArray array];
    self.scripts = [NSMutableArray array];
    
    self.addresses = [NSMutableArray array];
    self.amounts = [NSMutableArray array];
    
    self.signatures = [NSMutableArray array];
    
    return self;
}

- (id)initWithInputHashes:(NSArray *)hashes inputIndexes:(NSArray *)indexes inputScripts:(NSArray *)scripts
outputAddresses:(NSArray *)addresses outputAmounts:(NSArray *)amounts
{
    if (hashes.count != indexes.count || hashes.count != scripts.count || addresses.count != amounts.count) return nil;

    if (! (self = [super init])) return nil;
    
    self.hashes = [NSMutableArray arrayWithArray:hashes];
    self.indexes = [NSMutableArray arrayWithArray:indexes];
    self.scripts = [NSMutableArray arrayWithArray:scripts];
    
    self.addresses = [NSMutableArray arrayWithArray:addresses];
    self.amounts = [NSMutableArray arrayWithArray:amounts];
    
    self.signatures = [NSMutableArray arrayWithCapacity:hashes.count];
    for (int i = 0; i < hashes.count; i++) {
        [self.signatures addObject:[NSNull null]];
    }
    
    return self;
}

// hashes are expected to already be little endian
- (void)addInputHash:(NSData *)hash index:(NSUInteger)index script:(NSData *)script
{
    [self.hashes addObject:hash];
    [self.indexes addObject:@(index)];
    [self.scripts addObject:script];
    [self.signatures addObject:[NSNull null]];
}

- (void)addOutputAddress:(NSString *)address amount:(uint64_t)amount
{
    [self.addresses addObject:address];
    [self.amounts addObject:@(amount)];
}

- (NSArray *)inputAddresses
{
    NSMutableArray *addresses = [NSMutableArray arrayWithCapacity:self.scripts.count];

    [self.scripts enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        NSMutableData *addr = [NSMutableData dataWithBytes:"\0" length:1];

        [addr appendData:[obj subdataWithRange:NSMakeRange([obj length] - 22, 20)]];
        [addresses addObject:[NSString base58checkWithData:addr]];
    }];

    return addresses;
}

- (NSArray *)inputHashes
{
    return self.hashes;
}

- (NSArray *)inputScripts
{
    return self.scripts;
}

- (NSArray *)inputIndexes
{
    return self.indexes;
}

- (NSArray *)outputAddresses
{
    return self.addresses;
}

- (NSArray *)outputAmounts
{
    return self.amounts;
}

- (BOOL)signWithPrivateKeys:(NSArray *)privateKeys
{
    NSMutableArray *addresses = [NSMutableArray arrayWithCapacity:privateKeys.count],
                   *keys = [NSMutableArray arrayWithCapacity:privateKeys.count];
    
    [privateKeys enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        ZNKey *key = [ZNKey keyWithPrivateKey:obj];

        if (! key) return;
 
        [keys addObject:key];
        [addresses addObject:key.hash160];
    }];

    for (NSUInteger i = 0; i < self.hashes.count; i++) {
        NSUInteger keyIdx = [addresses indexOfObject:[self.scripts[i]
                             subdataWithRange:NSMakeRange([self.scripts[i] length] - 22, 20)]];

        if (keyIdx == NSNotFound) continue;
    
        NSData *txhash = [[self toDataWithSubscriptIndex:i] SHA256_2];
        NSMutableData *sig = [NSMutableData data];
        NSMutableData *s = [NSMutableData dataWithData:[keys[keyIdx] sign:txhash]];

        [s appendUInt8:SIGHASH_ALL];
        [sig appendScriptPushData:s];
        [sig appendScriptPushData:[keys[keyIdx] publicKey]];

        [self.signatures replaceObjectAtIndex:i withObject:sig];
    }
    
    return [self isSigned];
}

- (BOOL)isSigned
{
    return (self.signatures.count && self.signatures.count == self.hashes.count &&
            ! [self.signatures containsObject:[NSNull null]]);
}

- (NSData *)toDataWithSubscriptIndex:(NSUInteger)subscriptIndex
{
    NSMutableData *d = [NSMutableData dataWithCapacity:self.size];

    [d appendUInt32:TX_VERSION];

    [d appendVarInt:self.hashes.count];

    for (NSUInteger i = 0; i < self.hashes.count; i++) {
        [d appendData:self.hashes[i]];
        [d appendUInt32:[self.indexes[i] unsignedIntValue]];

        if ([self isSigned] && subscriptIndex == NSNotFound) {
            [d appendVarInt:[self.signatures[i] length]];
            [d appendData:self.signatures[i]];
        }
        else if (i == subscriptIndex) {// || subscriptIndex == NSNotFound) {
            //XXX to fully match the reference implementation, OP_CODESEPARATOR related checksig logic should go here
            [d appendVarInt:[self.scripts[i] length]];
            [d appendData:self.scripts[i]];
        }
        else [d appendVarInt:0];
        
        [d appendUInt32:TXIN_SEQUENCE];
    }
    
    [d appendVarInt:self.addresses.count];
    
    for (NSUInteger i = 0; i < self.addresses.count; i++) {
        [d appendUInt64:[self.amounts[i] unsignedLongLongValue]];
        
        [d appendVarInt:TXOUT_PUBKEYLEN]; //XXX this shouldn't be hard coded
        [d appendScriptPubKeyForAddress:self.addresses[i]];
    }
    
    [d appendUInt32:TX_LOCKTIME];
    
    if (subscriptIndex != NSNotFound) {
        [d appendUInt32:SIGHASH_ALL];
    }
    
    return d;
}

- (NSData *)toData
{
    return [self toDataWithSubscriptIndex:NSNotFound];
}

- (NSString *)toHex
{
    return [[self toData] toHex];
}

- (size_t)size
{
    //XXX is this correct? what about compressed vs uncompressed public keys?
    //XXX also need to take into account varint sizes
    return 10 + 148*self.hashes.count + 34*self.addresses.count;
}

// priority = sum(input_amount_in_satoshis*input_age_in_blocks)/size_in_bytes
- (uint64_t)priorityForAmounts:(NSArray *)amounts withAges:(NSArray *)ages
{
    uint64_t p = 0;
    
    if (amounts.count != self.hashes.count || ages.count != self.hashes.count) return 0;
    
    for (NSUInteger i = 0; i < self.amounts.count; i++) {    
        p += [amounts[i] unsignedLongLongValue]*[ages[i] unsignedLongLongValue];
    }
    
    return p/self.size;
}

// the block height after which the transaction can be confirmed without a fee, or NSNotFound for never
- (NSUInteger)blockHeightUntilFreeForAmounts:(NSArray *)amounts withBlockHeights:(NSArray *)heights
{
    if (amounts.count != self.hashes.count || heights.count != self.hashes.count) return NSNotFound;

    if (self.size > TX_FREE_MAX_SIZE) return NSNotFound;
    
    if ([self.amounts indexOfObjectPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
        return [obj unsignedLongLongValue] < TX_FREE_MIN_OUTPUT ? (*stop = YES) : NO;
    }] != NSNotFound) return NSNotFound;

    uint64_t amountTotal = 0, amountsByHeights = 0;
    
    for (NSUInteger i = 0; i < amounts.count; i++) {
        amountTotal += [amounts[i] unsignedLongLongValue];
        amountsByHeights += [amounts[i] unsignedLongLongValue]*[heights[i] unsignedLongLongValue];
    }
    
    //XXX this could possibly overflow a uint64 for very large input amounts and far in the future block heights,
    // however we should be okay up to the largest current bitcoin balance in existence for the next 40 years or so,
    // and the worst case is paying a transaction fee when it's not needed
    return (TX_FREE_MIN_PRIORITY*self.size + amountsByHeights + amountTotal - 1)/amountTotal;
}

- (uint64_t)standardFee
{
    return ((self.size + 999)/1000)*TX_FEE_PER_KB;
}

@end
