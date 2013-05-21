//
//  ZNTransaction.mm
//  ZincWallet
//
//  Created by Aaron Voisine on 5/16/13.
//  Copyright (c) 2013 zinc. All rights reserved.
//

#import "ZNTransaction.h"
#import "NSMutableData+Bitcoin.h"

//#include "bitcoinrpc.h"

#define TX_VERSION      0x00000001u
#define TX_LOCKTIME     0x00000000u
#define TXIN_SEQUENCE   UINT32_MAX
#define TXOUT_PUBKEYLEN 25

@interface ZNTransaction ()

@property (nonatomic, strong) NSArray *inputHashes, *inputIndexes, *inputScripts, *outputAddresses, *outputAmounts;
@property (nonatomic, strong) NSMutableArray *signatures;

@end

@implementation ZNTransaction

- (id)initWithInputHashes:(NSArray *)inputHashes inputIndexes:(NSArray *)inputIndexes
inputScripts:(NSArray *)inputScripts outputAddresses:(NSArray *)outputAddresses
andOutputAmounts:(NSArray *)outputAmounts
{
    if (! inputHashes.count || inputHashes.count != inputIndexes.count || inputHashes.count != inputScripts.count ||
        ! outputAddresses.count || outputAddresses.count != outputAmounts.count) return nil;

    if (! (self = [self init])) return nil;
        
    self.inputHashes = inputHashes;
    self.inputIndexes = inputIndexes;
    self.inputScripts = inputScripts;
    self.signatures = [NSMutableArray arrayWithCapacity:inputHashes.count];
    [self.inputHashes enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        [self.signatures addObject:[NSNull null]];
    }];
    
    self.outputAddresses = outputAddresses;
    self.outputAmounts = outputAmounts;
    
    return self;
}

- (BOOL)isSigned
{
    return (self.signatures.count && self.signatures.count == self.inputHashes.count &&
            ! [self.signatures containsObject:[NSNull null]]);
}

- (BOOL)signWithPrivateKeys:(NSArray *)privateKeys
{
    //XXX ecdsa voodoo goes here

    return [self isSigned];
}

- (NSData *)toData
{
    NSMutableData *d = [NSMutableData dataWithCapacity:10 + 180*self.inputHashes.count + 34*self.outputAddresses.count];

    [d appendUInt32:TX_VERSION];

    [d appendVarInt:self.inputHashes.count];

    for (NSUInteger i = 0; i < self.inputHashes.count; i++) {
        [d appendHash:self.inputHashes[i]];
        [d appendUInt32:[self.inputIndexes[i] unsignedIntValue]];

        if ([self isSigned]) {
            [d appendVarInt:[self.signatures[i] length]];
            [d appendData:self.signatures[i]];
        }
        else { // if this is an unsigned trasaction, use previous output sigPubKey in place of signature
            [d appendVarInt:[self.inputScripts[i] length]];
            [d appendData:self.inputScripts[i]];
        }
        
        [d appendUInt32:TXIN_SEQUENCE];
    }
    
    [d appendVarInt:self.outputAddresses.count];
    
    for (NSUInteger i = 0; i < self.outputAddresses.count; i++) {
        [d appendUInt64:[self.outputAmounts[i] unsignedLongLongValue]];
        
        [d appendVarInt:TXOUT_PUBKEYLEN]; //XXX this shouldn't be hard coded
        [d appendScriptPubKeyForAddress:self.outputAddresses[i]];
    }
    
    [d appendUInt32:TX_LOCKTIME];
    
    return d;
}

- (NSString *)toHex
{
    NSData *d = [self toData];
    NSMutableString *s = [NSMutableString stringWithCapacity:d.length*2];
    UInt8 *bytes = (UInt8 *)d.bytes;
    
    for (NSUInteger i = 0; i < d.length; i++) {
        [s appendFormat:@"%02x", bytes[i]];
    }

    return d ? s : nil;
}

@end
