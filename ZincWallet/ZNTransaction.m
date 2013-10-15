//
//  ZNTransaction.m
//  ZincWallet
//
//  Created by Aaron Voisine on 5/16/13.
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

#import "ZNTransaction.h"
#import "ZNKey.h"
#import "NSString+Base58.h"
#import "NSMutableData+Bitcoin.h"
#import "NSData+Bitcoin.h"
#import "NSData+Hash.h"

#define TX_VERSION    0x00000001u
#define TX_LOCKTIME   0x00000000u
#define TXIN_SEQUENCE UINT32_MAX
#define SIGHASH_ALL   0x00000001u

@interface ZNTransaction ()

@property (nonatomic, strong) NSMutableArray *hashes, *indexes, *inScripts;
@property (nonatomic, strong) NSMutableArray *amounts, *addresses, *outScripts;
@property (nonatomic, strong) NSMutableArray *signatures, *sequences;

@end

@implementation ZNTransaction

- (instancetype)init
{
    if (! (self = [super init])) return nil;
    
    _version = TX_VERSION;
    self.hashes = [NSMutableArray array];
    self.indexes = [NSMutableArray array];
    self.inScripts = [NSMutableArray array];
    self.amounts = [NSMutableArray array];
    self.addresses = [NSMutableArray array];
    self.outScripts = [NSMutableArray array];
    self.signatures = [NSMutableArray array];
    self.sequences = [NSMutableArray array];
    _lockTime = TX_LOCKTIME;
    
    return self;
}

- (instancetype)initWithInputHashes:(NSArray *)hashes inputIndexes:(NSArray *)indexes inputScripts:(NSArray *)scripts
outputAddresses:(NSArray *)addresses outputAmounts:(NSArray *)amounts
{
    if (hashes.count != indexes.count || hashes.count != scripts.count || addresses.count != amounts.count) return nil;

    if (! (self = [super init])) return nil;
    
    _version = TX_VERSION;
    self.hashes = [NSMutableArray arrayWithArray:hashes];
    self.indexes = [NSMutableArray arrayWithArray:indexes];
    self.inScripts = [NSMutableArray arrayWithArray:scripts];
    self.amounts = [NSMutableArray arrayWithArray:amounts];
    self.addresses = [NSMutableArray arrayWithArray:addresses];
    self.outScripts = [NSMutableArray arrayWithCapacity:addresses.count];
    for (int i = 0; i < addresses.count; i++) {
        [self.outScripts addObject:[NSMutableData data]];
        [self.outScripts.lastObject appendScriptPubKeyForAddress:self.addresses[i]];
    }
    
    self.signatures = [NSMutableArray arrayWithCapacity:hashes.count];
    self.sequences = [NSMutableArray arrayWithCapacity:hashes.count];
    for (int i = 0; i < hashes.count; i++) {
        [self.signatures addObject:[NSNull null]];
        [self.sequences addObject:@(TXIN_SEQUENCE)];
    }
    
    _lockTime = TX_LOCKTIME;

    return self;
}

- (instancetype)initWithData:(NSData *)data
{
    if (! (self = [super init])) return nil;
 
    NSString *address = nil;
    NSUInteger l = 0, len = 0, off = 0, count = 0;

    if (data.length < off + sizeof(uint32_t) + VARINT_MAX_LEN) return nil;
    _version = [data UInt32AtOffset:off]; // tx version
    off += sizeof(uint32_t);
    count = [data varIntAtOffset:off length:&l]; // input count
    off += l;

    for (NSUInteger i = 0; i < count; i++) { // inputs
        if (data.length < off + CC_SHA256_DIGEST_LENGTH + sizeof(uint32_t) + VARINT_MAX_LEN) return nil;
        [self.hashes addObject:[data subdataWithRange:NSMakeRange(off, CC_SHA256_DIGEST_LENGTH)]]; // input tx hash
        off += CC_SHA256_DIGEST_LENGTH;
        [self.indexes addObject:@([data UInt32AtOffset:off])]; // input index
        off += sizeof(uint32_t);
        [self.inScripts addObject:[NSNull null]]; // placeholder for input script (comes from previous transaction)
        len = [data varIntAtOffset:off length:&l]; // input signature length
        off += l;
        if (data.length < off + len + sizeof(uint32_t)) return nil;
        [self.signatures addObject:[data subdataWithRange:NSMakeRange(off, len)]]; // input signature
        off += len;
        [self.sequences addObject:@([data UInt32AtOffset:off])]; // input sequence number (for replacement transactons)
        off += sizeof(uint32_t);
    }

    if (data.length < off + VARINT_MAX_LEN) return nil;
    count = [data varIntAtOffset:off length:&l]; // output count
    off += l;
    
    for (NSUInteger i = 0; i < count; i++) { // outputs
        if (data.length < off + sizeof(uint64_t) + VARINT_MAX_LEN) return nil;
        [self.amounts addObject:@([data UInt64AtOffset:off])]; // output amount
        off += sizeof(uint64_t);
        len = [data varIntAtOffset:off length:&l]; // output script length
        off += l;
        if (data.length < off + len) return nil;
        [self.outScripts addObject:[data subdataWithRange:NSMakeRange(off, len)]]; // output script
        off += len;
        address = [NSString addressWithScript:self.outScripts.lastObject]; // address from output script if applicable
        [self.addresses addObject:address ? address : [NSNull null]];
    }
    
    if (data.length < off + sizeof(uint32_t)) return nil;
    _lockTime = [data UInt32AtOffset:off]; // tx locktime
    
    return self;
}

// hashes are expected to already be little endian
- (void)addInputHash:(NSData *)hash index:(NSUInteger)index script:(NSData *)script
{
    [self.hashes addObject:hash];
    [self.indexes addObject:@(index)];
    [self.inScripts addObject:script];
    [self.signatures addObject:[NSNull null]];
    [self.sequences addObject:@(TXIN_SEQUENCE)];
}

- (void)addOutputAddress:(NSString *)address amount:(uint64_t)amount
{
    [self.amounts addObject:@(amount)];
    [self.addresses addObject:address];
    [self.outScripts addObject:[NSMutableData data]];
    [self.outScripts.lastObject appendScriptPubKeyForAddress:address];
}

- (void)setInputAddress:(NSString *)address atIndex:(NSUInteger)index;
{
    NSMutableData *d = [NSMutableData data];

    [d appendScriptPubKeyForAddress:address];
    [self.inScripts replaceObjectAtIndex:index withObject:d];
}

- (NSArray *)inputAddresses
{
    NSMutableArray *addresses = [NSMutableArray arrayWithCapacity:self.inScripts.count];

    for (NSData *d in self.inScripts) {
        if (d != (id)[NSNull null] && d.length >= 22) {
            NSMutableData *addr = [NSMutableData dataWithBytes:"\0" length:1];

            [addr appendData:[d subdataWithRange:NSMakeRange(d.length - 22, 20)]];
            [addresses addObject:[NSString base58checkWithData:addr]];
        }
        else [addresses addObject:[NSNull null]];
    }

    return addresses;
}

- (NSArray *)inputHashes
{
    return self.hashes;
}

- (NSArray *)inputIndexes
{
    return self.indexes;
}

- (NSArray *)inputScripts
{
    return self.inScripts;
}

- (NSArray *)inputSequences
{
    return self.sequences;
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
    
    for (NSString *pk in privateKeys) {
        ZNKey *key = [ZNKey keyWithPrivateKey:pk];

        if (! key) continue;
 
        [keys addObject:key];
        [addresses addObject:key.hash160];
    }

    for (NSUInteger i = 0; i < self.hashes.count; i++) {
        NSUInteger keyIdx = [addresses indexOfObject:[self.inScripts[i]
                             subdataWithRange:NSMakeRange([self.inScripts[i] length] - 22, 20)]];

        if (keyIdx == NSNotFound) continue;
    
        NSData *txHash = [[self toDataWithSubscriptIndex:i] SHA256_2];
        NSMutableData *sig = [NSMutableData data];
        NSMutableData *s = [NSMutableData dataWithData:[keys[keyIdx] sign:txHash]];

        [s appendUInt8:SIGHASH_ALL];
        [sig appendScriptPushData:s];
        [sig appendScriptPushData:[keys[keyIdx] publicKey]];

        [self.signatures replaceObjectAtIndex:i withObject:sig];
    }
    
    if (! [self isSigned]) return NO;
    
    self.txHash = [[[self toData] SHA256_2] reverse];
        
    return YES;
}

- (BOOL)isSigned
{
    return (self.signatures.count && self.signatures.count == self.hashes.count &&
            ! [self.signatures containsObject:[NSNull null]]);
}

// Returns the binary transaction data that needs to be hashed and signed with the private key for the tx input at
// subscriptIndex. A subscriptIndex of NSNotFound will return the entire signed transaction
- (NSData *)toDataWithSubscriptIndex:(NSUInteger)subscriptIndex
{
    NSMutableData *d = [NSMutableData dataWithCapacity:self.size];

    [d appendUInt32:self.version];
    [d appendVarInt:self.hashes.count];

    for (NSUInteger i = 0; i < self.hashes.count; i++) {
        [d appendData:self.hashes[i]];
        [d appendUInt32:[self.indexes[i] unsignedIntValue]];

        if ([self isSigned] && subscriptIndex == NSNotFound) {
            [d appendVarInt:[self.signatures[i] length]];
            [d appendData:self.signatures[i]];
        }
        else if (i == subscriptIndex) {
            //TODO: to fully match the reference implementation, OP_CODESEPARATOR related checksig logic should go here
            [d appendVarInt:[self.inScripts[i] length]];
            [d appendData:self.inScripts[i]];
        }
        else [d appendVarInt:0];
        
        [d appendUInt32:[self.sequences[i] unsignedIntValue]];
    }
    
    [d appendVarInt:self.addresses.count];
    
    for (NSUInteger i = 0; i < self.addresses.count; i++) {
        [d appendUInt64:[self.amounts[i] unsignedLongLongValue]];
        [d appendVarInt:[self.outScripts[i] length]];
        [d appendData:self.outScripts[i]];
    }
    
    [d appendUInt32:self.lockTime];
    
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
    return [NSString hexWithData:[self toData]];
}

- (size_t)size
{
    //TODO: not all keys come from this wallet (private keys can be swept), might cause a lower than standard tx fee
    size_t sigSize = 149; // electrum seeds generate uncompressed keys, bip32 uses compressed
//    size_t sigSize = 181;

    return 8 + [NSMutableData sizeOfVarInt:self.hashes.count] + [NSMutableData sizeOfVarInt:self.addresses.count] +
           sigSize*self.hashes.count + 34*self.addresses.count;
}

// priority = sum(input_amount_in_satoshis*input_age_in_blocks)/size_in_bytes
- (uint64_t)priorityForAmounts:(NSArray *)amounts withAges:(NSArray *)ages
{
    uint64_t p = 0;
    
    if (amounts.count != self.hashes.count || ages.count != self.hashes.count) return 0;
    
    for (NSUInteger i = 0; i < amounts.count; i++) {    
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
    
    // this could possibly overflow a uint64 for very large input amounts and far in the future block heights,
    // however we should be okay up to the largest current bitcoin balance in existence for the next 40 years or so,
    // and the worst case is paying a transaction fee when it's not needed
    return (TX_FREE_MIN_PRIORITY*(uint64_t)self.size + amountsByHeights + amountTotal - 1llu)/amountTotal;
}

- (uint64_t)standardFee
{
    return ((self.size + 999)/1000)*TX_FEE_PER_KB;
}

@end
