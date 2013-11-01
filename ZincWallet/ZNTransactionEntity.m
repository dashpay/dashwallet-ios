//
//  ZNTransactionEntity.m
//  ZincWallet
//
//  Created by Aaron Voisine on 8/22/13.
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

#import "ZNTransactionEntity.h"
#import "ZNTxInputEntity.h"
#import "ZNTxOutputEntity.h"
#import "ZNUnspentOutputEntity.h"
#import "ZNAddressEntity.h"
#import "ZNTransaction.h"
#import "ZNMerkleBlock.h"
#import "NSManagedObject+Utils.h"
#import "NSString+Base58.h"
#import <CommonCrypto/CommonDigest.h>

@implementation ZNTransactionEntity

@dynamic txHash;
@dynamic blockHeight;
@dynamic timeStamp;
@dynamic txIndex;
@dynamic inputs;
@dynamic outputs;

+ (instancetype)createOrUpdateWithJSON:(NSDictionary *)JSON
{
    if (! [JSON isKindOfClass:[NSDictionary class]] || ! [JSON[@"hash"] isKindOfClass:[NSString class]]) return nil;

    NSData *hash = [JSON[@"hash"] hexToData];
    __block ZNTransactionEntity *e = nil;

    if (hash.length != CC_SHA256_DIGEST_LENGTH) return nil;
    
    [[self context] performBlockAndWait:^{
        e = [self objectsMatching:@"txHash == %@", hash].lastObject;
    
        if (! e) e = [self managedObject];
    
        [e setAttributesFromJSON:JSON];
    }];
    
    return e;
}

// more efficient method for updating the heights of all the transactions in a long chain of blocks
+ (NSArray *)updateHeightsWithChain:(NSArray *)chain startHeight:(int32_t)height
{
    NSMutableDictionary *txHeights = [NSMutableDictionary dictionary];
    
    for (ZNMerkleBlock *b in chain) {
        for (NSData *txHash in b.txHashes) {
            txHeights[txHash] = @(height);
        }

        height++;
    }

    [[self context] performBlockAndWait:^{
        for (ZNTransactionEntity *e in [ZNTransactionEntity objectsMatching:@"txHash in %@", txHeights.allKeys]) {
            e.blockHeight = [txHeights[e.txHash] intValue];
        }
    }];

    return nil;
}

- (instancetype)setAttributesFromJSON:(NSDictionary *)JSON
{
    if (! [JSON isKindOfClass:[NSDictionary class]]) return self;
    
    [[self managedObjectContext] performBlockAndWait:^{
        if ([JSON[@"hash"] isKindOfClass:[NSString class]]) self.txHash = [JSON[@"hash"] hexToData];
        if ([JSON[@"block_height"] isKindOfClass:[NSNumber class]]) self.blockHeight = [JSON[@"block_height"] intValue];
        if ([JSON[@"time"] isKindOfClass:[NSNumber class]]) self.timeStamp = [JSON[@"time"] doubleValue] - NSTimeIntervalSince1970;
        if ([JSON[@"tx_index"] isKindOfClass:[NSNumber class]]) self.txIndex = [JSON[@"tx_index"] longLongValue];
        
        if ([JSON[@"inputs"] isKindOfClass:[NSArray class]]) {
            NSMutableOrderedSet *inputs = [self mutableOrderedSetValueForKey:@"inputs"];
            NSUInteger idx = 0;
            
            while (inputs.count < [JSON[@"inputs"] count]) {
                [inputs addObject:[ZNTxInputEntity managedObject]];
            }

            while (inputs.count > [JSON[@"inputs"] count]) {
                [inputs removeObjectAtIndex:inputs.count - 1];
            }

            for (NSDictionary *input in [JSON[@"inputs"] valueForKey:@"prev_out"]) {
                [inputs[idx++] setAttributesFromJSON:input];
            };
        }
    
        if ([JSON[@"out"] isKindOfClass:[NSArray class]]) {
            NSMutableOrderedSet *outputs = [self mutableOrderedSetValueForKey:@"outputs"];
            NSUInteger idx = 0;
            
            while (outputs.count < [JSON[@"out"] count]) {
                [outputs addObject:[ZNTxOutputEntity managedObject]];
            }

            while (outputs.count > [JSON[@"out"] count]) {
                [outputs removeObjectAtIndex:outputs.count - 1];
            }

            for (NSDictionary *output in JSON[@"out"]) {
                [outputs[idx++] setAttributesFromJSON:output];
            }
        }
    }];
    
    return self;
}

- (instancetype)setAttributesFromTx:(ZNTransaction *)tx
{
    [[self managedObjectContext] performBlockAndWait:^{
        NSMutableOrderedSet *inputs = [self mutableOrderedSetValueForKey:@"inputs"];
        NSMutableOrderedSet *outputs = [self mutableOrderedSetValueForKey:@"outputs"];
        NSUInteger idx = 0;
        
        self.txHash = tx.txHash;
        if (self.timeStamp < 1.0) self.timeStamp = [NSDate timeIntervalSinceReferenceDate];
    
        while (inputs.count < tx.inputHashes.count) {
            [inputs addObject:[ZNTxInputEntity managedObject]];
        }
    
        while (inputs.count > tx.inputHashes.count) {
            [inputs removeObjectAtIndex:inputs.count - 1];
        }
    
        for (ZNTxInputEntity *e in inputs) {
            ZNUnspentOutputEntity *o = [ZNUnspentOutputEntity objectsMatching:@"txHash == %@ && n == %d",
                                        tx.inputHashes[idx], [tx.inputIndexes[idx] intValue]].lastObject;
        
            if (o) {
                [e setAddress:o.address txIndex:o.txIndex n:o.n value:o.value];
            }
            else [e setAddress:tx.inputAddresses[idx] txIndex:0 n:[tx.inputIndexes[idx] intValue] value:0];
            
            idx++;
        }

        while (outputs.count < tx.outputAddresses.count) {
            [outputs addObject:[ZNTxOutputEntity managedObject]];
        }
    
        while (outputs.count > tx.outputAddresses.count) {
            [self removeObjectFromOutputsAtIndex:outputs.count - 1];
        }

        idx = 0;
        
        for (ZNTxOutputEntity *o in outputs) {
            [o setAddress:tx.outputAddresses[idx] txIndex:0 n:(int32_t)idx
             value:[tx.outputAmounts[idx] longLongValue]];
            idx++;
        }
    }];
    
    return self;
}

@end
