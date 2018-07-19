//
//  DSTransaction.m
//  DashSync
//
//  Created by Aaron Voisine on 5/16/13.
//  Copyright (c) 2013 Aaron Voisine <voisine@gmail.com>
//  Updated by Quantum Explorer on 05/11/18.
//  Copyright (c) 2018 Quantum Explorer <quantum@dash.org>
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

#import "DSTransaction.h"
#import "DSKey.h"
#import "NSString+Dash.h"
#import "NSData+Dash.h"
#import "NSString+Bitcoin.h"
#import "NSMutableData+Dash.h"
#import "NSData+Bitcoin.h"
#import "DSAddressEntity+CoreDataClass.h"
#import "NSManagedObject+Sugar.h"
#import "DSChain.h"

#define TX_VERSION    0x00000001u
#define TX_LOCKTIME   0x00000000u
#define TXIN_SEQUENCE UINT32_MAX
#define SIGHASH_ALL   0x00000001u

@interface DSTransaction ()

@property (nonatomic, strong) NSMutableArray *hashes, *indexes, *inScripts, *signatures, *sequences;
@property (nonatomic, strong) NSMutableArray *amounts, *addresses, *outScripts;
@property (nonatomic, strong) DSChain * chain;
@property (nonatomic, strong) NSData * coinbaseData;

@end

@implementation DSTransaction

+ (instancetype)transactionWithMessage:(NSData *)message onChain:(DSChain *)chain
{
    return [[self alloc] initWithMessage:message onChain:chain];
}

+ (instancetype)devnetGenesisCoinbaseWithIdentifier:(NSString*)identifier forChain:(DSChain *)chain {
    DSTransaction * transaction = [[self alloc] initOnChain:chain];
    NSMutableData * coinbaseData = [NSMutableData data];
    [coinbaseData appendDevnetGenesisCoinbaseMessage:identifier];
    //transaction.inputIndexes
    [transaction addInputHash:UINT256_ZERO index:UINT32_MAX script:nil];
    [transaction setCoinbaseData:coinbaseData];
    NSMutableData * outputScript = [NSMutableData data];
    [outputScript appendUInt8:OP_RETURN];
    [transaction addOutputScript:outputScript amount:chain.baseReward];
    NSLog(@"we are hashing %@",transaction.toData);
    transaction.txHash = transaction.toData.SHA256_2;
    return transaction;
}

- (instancetype)init {
    if (! (self = [super init])) return nil;
    NSAssert(FALSE, @"this method is not supported");
    return self;
}

- (instancetype)initOnChain:(DSChain*)chain
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
    self.chain = chain;
    _lockTime = TX_LOCKTIME;
    _blockHeight = TX_UNCONFIRMED;
    return self;
}

- (instancetype)initWithMessage:(NSData *)message onChain:(DSChain *)chain
{
    if (! (self = [self initOnChain:chain])) return nil;
 
    NSString *address = nil;
    NSNumber * l = 0;
    uint32_t off = 0;
    uint64_t count = 0;
    NSData *d = nil;
    
    @autoreleasepool {
        self.chain = chain;
        _version = [message UInt32AtOffset:off]; // tx version
        off += sizeof(uint32_t);
        count = [message varIntAtOffset:off length:&l]; // input count
        if (count == 0) return nil; // at least one input is required
        off += l.unsignedIntegerValue;

        for (NSUInteger i = 0; i < count; i++) { // inputs
            [self.hashes addObject:uint256_obj([message hashAtOffset:off])];
            off += sizeof(UInt256);
            [self.indexes addObject:@([message UInt32AtOffset:off])]; // input index
            off += sizeof(uint32_t);
            [self.inScripts addObject:[NSNull null]]; // placeholder for input script (comes from input transaction)
            d = [message dataAtOffset:off length:&l];
            [self.signatures addObject:(d.length > 0) ? d : [NSNull null]]; // input signature
            off += l.unsignedIntegerValue;
            [self.sequences addObject:@([message UInt32AtOffset:off])]; // input sequence number (for replacement tx)
            off += sizeof(uint32_t);
        }

        count = (NSUInteger)[message varIntAtOffset:off length:&l]; // output count
        off += l.unsignedIntegerValue;

        for (NSUInteger i = 0; i < count; i++) { // outputs
            [self.amounts addObject:@([message UInt64AtOffset:off])]; // output amount
            off += sizeof(uint64_t);
            d = [message dataAtOffset:off length:&l];
            [self.outScripts addObject:(d) ? d : [NSNull null]]; // output script
            off += l.unsignedIntegerValue;
            address = [NSString addressWithScriptPubKey:d onChain:self.chain]; // address from output script if applicable
            [self.addresses addObject:(address) ? address : [NSNull null]];
        }
        _payloadOffset = off;

        _lockTime = [message UInt32AtOffset:off]; // tx locktime
        _txHash = self.data.SHA256_2;
    }
    
    NSString * outboundShapeshiftAddress = [self shapeshiftOutboundAddress];
    if (outboundShapeshiftAddress) {
        self.associatedShapeshift = [DSShapeshiftEntity shapeshiftHavingWithdrawalAddress:outboundShapeshiftAddress];
        if (self.associatedShapeshift && [self.associatedShapeshift.shapeshiftStatus integerValue] == eShapeshiftAddressStatus_Unused) {
            self.associatedShapeshift.shapeshiftStatus = @(eShapeshiftAddressStatus_NoDeposits);
        }
        if (!self.associatedShapeshift) {
            NSString * possibleOutboundShapeshiftAddress = [self shapeshiftOutboundAddressForceScript];
            self.associatedShapeshift = [DSShapeshiftEntity shapeshiftHavingWithdrawalAddress:possibleOutboundShapeshiftAddress];
            if (self.associatedShapeshift && [self.associatedShapeshift.shapeshiftStatus integerValue] == eShapeshiftAddressStatus_Unused) {
                self.associatedShapeshift.shapeshiftStatus = @(eShapeshiftAddressStatus_NoDeposits);
            }
        }
        if (!self.associatedShapeshift && [self.outputAddresses count]) {
            NSString * mainOutputAddress = nil;
            NSMutableArray * allAddresses = [NSMutableArray array];
            for (DSAddressEntity *e in [DSAddressEntity allObjects]) {
                [allAddresses addObject:e.address];
            }
            for (NSString * outputAddress in self.outputAddresses) {
                if (outputAddress && [allAddresses containsObject:address]) continue;
                if ([outputAddress isEqual:[NSNull null]]) continue;
                mainOutputAddress = outputAddress;
            }
            //NSAssert(mainOutputAddress, @"there should always be an output address");
            if (mainOutputAddress){
                self.associatedShapeshift = [DSShapeshiftEntity registerShapeshiftWithInputAddress:mainOutputAddress andWithdrawalAddress:outboundShapeshiftAddress withStatus:eShapeshiftAddressStatus_NoDeposits];
            }
        }
    }
    

    return self;
}

- (instancetype)initWithInputHashes:(NSArray *)hashes inputIndexes:(NSArray *)indexes inputScripts:(NSArray *)scripts
outputAddresses:(NSArray *)addresses outputAmounts:(NSArray *)amounts onChain:(DSChain *)chain
{
    if (hashes.count == 0 || hashes.count != indexes.count) return nil;
    if (scripts.count > 0 && hashes.count != scripts.count) return nil;
    if (addresses.count != amounts.count) return nil;

    if (! (self = [super init])) return nil;

    self.chain = chain;
    _version = TX_VERSION;
    self.hashes = [NSMutableArray arrayWithArray:hashes];
    self.indexes = [NSMutableArray arrayWithArray:indexes];

    if (scripts.count > 0) {
        self.inScripts = [NSMutableArray arrayWithArray:scripts];
    }
    else self.inScripts = [NSMutableArray arrayWithCapacity:hashes.count];

    while (self.inScripts.count < hashes.count) {
        [self.inScripts addObject:[NSNull null]];
    }

    self.amounts = [NSMutableArray arrayWithArray:amounts];
    self.addresses = [NSMutableArray arrayWithArray:addresses];
    self.outScripts = [NSMutableArray arrayWithCapacity:addresses.count];

    for (int i = 0; i < addresses.count; i++) {
        [self.outScripts addObject:[NSMutableData data]];
        [self.outScripts.lastObject appendScriptPubKeyForAddress:self.addresses[i] forChain:chain];
    }

    self.signatures = [NSMutableArray arrayWithCapacity:hashes.count];
    self.sequences = [NSMutableArray arrayWithCapacity:hashes.count];

    for (int i = 0; i < hashes.count; i++) {
        [self.signatures addObject:[NSNull null]];
        [self.sequences addObject:@(TXIN_SEQUENCE)];
    }

    _lockTime = TX_LOCKTIME;
    _blockHeight = TX_UNCONFIRMED;
    return self;
}

-(DSAccount*)account {
    return [self.chain accountContainingTransaction:self];
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

- (NSArray *)inputSignatures
{
    return self.signatures;
}

- (NSArray *)inputSequences
{
    return self.sequences;
}

- (NSArray *)outputAmounts
{
    return self.amounts;
}

- (NSArray *)outputAddresses
{
    return self.addresses;
}

- (NSArray *)outputScripts
{
    return self.outScripts;
}

- (NSString *)description
{
    NSString *txid = [NSString hexWithData:[NSData dataWithBytes:self.txHash.u8 length:sizeof(UInt256)].reverse];
    return [NSString stringWithFormat:@"%@(id=%@)", [self class], txid];
}

- (NSString *)longDescription
{
    NSString *txid = [NSString hexWithData:[NSData dataWithBytes:self.txHash.u8 length:sizeof(UInt256)].reverse];
    return [NSString stringWithFormat:
            @"%@(id=%@, inputHashes=%@, inputIndexes=%@, inputScripts=%@, inputSignatures=%@, inputSequences=%@, "
                           "outputAmounts=%@, outputAddresses=%@, outputScripts=%@)",
            [[self class] description], txid,
            self.inputHashes, self.inputIndexes, self.inputScripts, self.inputSignatures, self.inputSequences,
            self.outputAmounts, self.outputAddresses, self.outputScripts];
}

// size in bytes if signed, or estimated size assuming compact pubkey sigs
- (size_t)size
{
    if (! uint256_is_zero(_txHash)) return self.data.length;
    return 8 + [NSMutableData sizeOfVarInt:self.hashes.count] + [NSMutableData sizeOfVarInt:self.addresses.count] +
           TX_INPUT_SIZE*self.hashes.count + TX_OUTPUT_SIZE*self.addresses.count;
}

- (uint64_t)standardFee
{
    return ((self.size + 999)/1000)*TX_FEE_PER_KB;
}

- (uint64_t)standardInstantFee
{
    return TX_FEE_PER_INPUT*[self.inputHashes count];
}

// checks if all signatures exist, but does not verify them
- (BOOL)isSigned
{
    return (self.signatures.count > 0 && self.signatures.count == self.hashes.count &&
            ! [self.signatures containsObject:[NSNull null]]) ? YES : NO;
}

- (NSData *)toData
{
    return [self toDataWithSubscriptIndex:NSNotFound];
}

- (void)addInputHash:(UInt256)hash index:(NSUInteger)index script:(NSData *)script
{
    [self addInputHash:hash index:index script:script signature:nil sequence:TXIN_SEQUENCE];
}

- (void)addInputHash:(UInt256)hash index:(NSUInteger)index script:(NSData *)script signature:(NSData *)signature
sequence:(uint32_t)sequence
{
    [self.hashes addObject:uint256_obj(hash)];
    [self.indexes addObject:@(index)];
    [self.inScripts addObject:(script) ? script : [NSNull null]];
    [self.signatures addObject:(signature) ? signature : [NSNull null]];
    [self.sequences addObject:@(sequence)];
}

- (void)addOutputAddress:(NSString *)address amount:(uint64_t)amount
{
    [self.amounts addObject:@(amount)];
    [self.addresses addObject:address];
    [self.outScripts addObject:[NSMutableData data]];
    [self.outScripts.lastObject appendScriptPubKeyForAddress:address forChain:self.chain];
}

- (void)addOutputShapeshiftAddress:(NSString *)address
{
    [self.amounts addObject:@(0)];
    [self.addresses addObject:[NSNull null]];
    [self.outScripts addObject:[NSMutableData data]];
    [self.outScripts.lastObject appendShapeshiftMemoForAddress:address];
}

- (void)addOutputScript:(NSData *)script amount:(uint64_t)amount;
{
    NSString *address = [NSString addressWithScriptPubKey:script onChain:self.chain];

    [self.amounts addObject:@(amount)];
    [self.outScripts addObject:script];
    [self.addresses addObject:(address) ? address : [NSNull null]];
}

- (void)setInputAddress:(NSString *)address atIndex:(NSUInteger)index;
{
    NSMutableData *d = [NSMutableData data];

    [d appendScriptPubKeyForAddress:address forChain:self.chain];
    self.inScripts[index] = d;
}

- (NSArray *)inputAddresses
{
    NSMutableArray *addresses = [NSMutableArray arrayWithCapacity:self.inScripts.count];
    NSInteger i = 0;

    for (NSData *script in self.inScripts) {
        NSString *addr = [NSString addressWithScriptPubKey:script onChain:self.chain];

        if (! addr) addr = [NSString addressWithScriptSig:self.signatures[i] onChain:self.chain];
        [addresses addObject:(addr) ? addr : [NSNull null]];
        i++;
    }

    return addresses;
}

- (void)shuffleOutputOrder
{    
    for (NSUInteger i = 0; i + 1 < self.amounts.count; i++) { // fischer-yates shuffle
        NSUInteger j = i + arc4random_uniform((uint32_t)(self.amounts.count - i));
        
        if (j == i) continue;
        [self.amounts exchangeObjectAtIndex:i withObjectAtIndex:j];
        [self.outScripts exchangeObjectAtIndex:i withObjectAtIndex:j];
        [self.addresses exchangeObjectAtIndex:i withObjectAtIndex:j];
    }
}

// Returns the binary transaction data that needs to be hashed and signed with the private key for the tx input at
// subscriptIndex. A subscriptIndex of NSNotFound will return the entire signed transaction.
- (NSData *)toDataWithSubscriptIndex:(NSUInteger)subscriptIndex
{
    UInt256 hash = UINT256_ZERO;
    NSMutableData *d = [NSMutableData dataWithCapacity:10 + TX_INPUT_SIZE*self.hashes.count +
                        TX_OUTPUT_SIZE*self.addresses.count];

    [d appendUInt32:self.version];
    [d appendVarInt:self.hashes.count];
    
    if ([self isCoinbase]) {
        [d appendBytes:&hash length:sizeof(hash)];
        [d appendUInt32:UINT32_MAX];
        [d appendData:self.coinbaseData];
        [d appendUInt32:UINT32_MAX];
    } else {

    for (NSUInteger i = 0; i < self.hashes.count; i++) {
        [self.hashes[i] getValue:&hash];
        [d appendBytes:&hash length:sizeof(hash)];
        [d appendUInt32:[self.indexes[i] unsignedIntValue]];

        if (subscriptIndex == NSNotFound && self.signatures[i] != [NSNull null]) {
            [d appendVarInt:[self.signatures[i] length]];
            [d appendData:self.signatures[i]];
        }
        else if (subscriptIndex == i && self.inScripts[i] != [NSNull null]) {
            //TODO: to fully match the reference implementation, OP_CODESEPARATOR related checksig logic should go here
            [d appendVarInt:[self.inScripts[i] length]];
            [d appendData:self.inScripts[i]];
        }
        else [d appendVarInt:0];
        
        [d appendUInt32:[self.sequences[i] unsignedIntValue]];
    }
    }
    
    [d appendVarInt:self.amounts.count];
    
    for (NSUInteger i = 0; i < self.amounts.count; i++) {
        [d appendUInt64:[self.amounts[i] unsignedLongLongValue]];
        [d appendVarInt:[self.outScripts[i] length]];
        [d appendData:self.outScripts[i]];
    }
    
    [d appendUInt32:self.lockTime];
    if (subscriptIndex != NSNotFound) [d appendUInt32:SIGHASH_ALL];
    return d;
}

- (BOOL)signWithPrivateKeys:(NSArray *)privateKeys
{
    NSMutableArray *addresses = [NSMutableArray arrayWithCapacity:privateKeys.count],
                   *keys = [NSMutableArray arrayWithCapacity:privateKeys.count];
    
    for (NSString *pk in privateKeys) {
        DSKey *key = [DSKey keyWithPrivateKey:pk onChain:self.chain];
        
        if (! key) continue;
        [keys addObject:key];
        [addresses addObject:[key addressForChain:self.chain]];
    }
    
    for (NSUInteger i = 0; i < self.hashes.count; i++) {
        NSString *addr = [NSString addressWithScriptPubKey:self.inScripts[i] onChain:self.chain];
        NSUInteger keyIdx = (addr) ? [addresses indexOfObject:addr] : NSNotFound;
        
        if (keyIdx == NSNotFound) continue;
        
        NSMutableData *sig = [NSMutableData data];
        UInt256 hash = [self toDataWithSubscriptIndex:i].SHA256_2;
        NSMutableData *s = [NSMutableData dataWithData:[keys[keyIdx] sign:hash]];
        NSArray *elem = [self.inScripts[i] scriptElements];
        
        [s appendUInt8:SIGHASH_ALL];
        [sig appendScriptPushData:s];
        
        if (elem.count >= 2 && [elem[elem.count - 2] intValue] == OP_EQUALVERIFY) { // pay-to-pubkey-hash scriptSig
            [sig appendScriptPushData:[keys[keyIdx] publicKey]];
        }
        
        self.signatures[i] = sig;
    }
    
    if (! self.isSigned) return NO;
    _txHash = self.data.SHA256_2;
    return YES;
}

// priority = sum(input_amount_in_satoshis*input_age_in_blocks)/size_in_bytes
- (uint64_t)priorityForAmounts:(NSArray *)amounts withAges:(NSArray *)ages
{
    uint64_t p = 0;
    
    if (amounts.count != self.hashes.count || ages.count != self.hashes.count || [ages containsObject:@(0)]) return 0;
    
    for (NSUInteger i = 0; i < amounts.count; i++) {    
        p += [amounts[i] unsignedLongLongValue]*[ages[i] unsignedLongLongValue];
    }
    
    return p/self.size;
}

// the block height after which the transaction can be confirmed without a fee, or TX_UNCONFIRMRED for never
- (uint32_t)blockHeightUntilFreeForAmounts:(NSArray *)amounts withBlockHeights:(NSArray *)heights
{
    if (amounts.count != self.hashes.count || heights.count != self.hashes.count ||
        self.size > TX_FREE_MAX_SIZE || [heights containsObject:@(TX_UNCONFIRMED)]) {
        return TX_UNCONFIRMED;
    }

    for (NSNumber *amount in self.amounts) {
        if (amount.unsignedLongLongValue < TX_MIN_OUTPUT_AMOUNT) return TX_UNCONFIRMED;
    }

    uint64_t amountTotal = 0, amountsByHeights = 0;
    
    for (NSUInteger i = 0; i < amounts.count; i++) {
        amountTotal += [amounts[i] unsignedLongLongValue];
        amountsByHeights += [amounts[i] unsignedLongLongValue]*[heights[i] unsignedLongLongValue];
    }
    
    if (amountTotal == 0) return TX_UNCONFIRMED;
    
    // this could possibly overflow a uint64 for very large input amounts and far in the future block heights,
    // however we should be okay up to the largest current bitcoin balance in existence for the next 40 years or so,
    // and the worst case is paying a transaction fee when it's not needed
    return (uint32_t)((TX_FREE_MIN_PRIORITY*(uint64_t)self.size + amountsByHeights + amountTotal - 1ULL)/amountTotal);
}

-(BOOL)isCoinbase {
    if (([self.hashes count] == 1)) {
        UInt256 firstInputHash;
        [self.hashes[0] getValue:&firstInputHash];
        if (uint256_is_zero(firstInputHash) && [[self.inputIndexes objectAtIndex:0] integerValue] == UINT32_MAX) return TRUE;
    }
    return FALSE;
}

- (NSUInteger)hash
{
    if (uint256_is_zero(_txHash)) return super.hash;
    return *(const NSUInteger *)&_txHash;
}

- (BOOL)isEqual:(id)object
{
    return self == object || ([object isKindOfClass:[DSTransaction class]] && uint256_eq(_txHash, [object txHash]));
}

#pragma mark - Extra shapeshift methods

- (NSString*)shapeshiftOutboundAddress {
    for (NSData * script in self.outputScripts) {
        NSString * outboundAddress = [DSTransaction shapeshiftOutboundAddressForScript:script];
        if (outboundAddress) return outboundAddress;
    }
    return nil;
}

- (NSString*)shapeshiftOutboundAddressForceScript {
    for (NSData * script in self.outputScripts) {
        NSString * outboundAddress = [DSTransaction shapeshiftOutboundAddressForceScript:script];
        if (outboundAddress) return outboundAddress;
    }
    return nil;
}

+ (NSString*)shapeshiftOutboundAddressForceScript:(NSData*)script {
    if ([script UInt8AtOffset:0] == OP_RETURN) {
        UInt8 length = [script UInt8AtOffset:1];
        if ([script UInt8AtOffset:2] == OP_SHAPESHIFT) {
            NSMutableData * data = [NSMutableData data];
            uint8_t v = BITCOIN_SCRIPT_ADDRESS;
            [data appendBytes:&v length:1];
            NSData * addressData = [script subdataWithRange:NSMakeRange(3, length - 1)];
            
            [data appendData:addressData];
            return [NSString base58checkWithData:data];
        }
    }
    return nil;
}

+ (NSString*)shapeshiftOutboundAddressForScript:(NSData*)script {
    if ([script UInt8AtOffset:0] == OP_RETURN) {
        UInt8 length = [script UInt8AtOffset:1];
        if ([script UInt8AtOffset:2] == OP_SHAPESHIFT) {
            NSMutableData * data = [NSMutableData data];
            uint8_t v = BITCOIN_PUBKEY_ADDRESS;
            [data appendBytes:&v length:1];
            NSData * addressData = [script subdataWithRange:NSMakeRange(3, length - 1)];
            
            [data appendData:addressData];
            return [NSString base58checkWithData:data];
        } else if ([script UInt8AtOffset:2] == OP_SHAPESHIFT_SCRIPT) {
            NSMutableData * data = [NSMutableData data];
            uint8_t v = BITCOIN_SCRIPT_ADDRESS;
            [data appendBytes:&v length:1];
            NSData * addressData = [script subdataWithRange:NSMakeRange(3, length - 1)];
            
            [data appendData:addressData];
            return [NSString base58checkWithData:data];
        }
    }
    return nil;
}

@end
