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
#import "ZNAddressEntity.h"
#import "ZNTransaction.h"
#import "ZNMerkleBlock.h"
#import "NSManagedObject+Utils.h"
#import "NSString+Base58.h"
#import "NSMutableData+Bitcoin.h"
#import <CommonCrypto/CommonDigest.h>

@implementation ZNTransactionEntity

@dynamic txHash;
@dynamic blockHeight;
@dynamic timeStamp;
@dynamic inputs;
@dynamic outputs;
@dynamic lockTime;

+ (void)setBlockHeight:(int32_t)blockHeight forTxHashes:(NSArray *)txHashes
{
    if (txHashes.count == 0) return;
    
    [[self context] performBlockAndWait:^{
        [[self objectsMatching:@"txHash in %@", txHashes] setValue:@(blockHeight) forKey:@"blockHeight"];
    }];
}

- (instancetype)setAttributesFromTx:(ZNTransaction *)tx
{
    [[self managedObjectContext] performBlockAndWait:^{
        NSMutableOrderedSet *inputs = [self mutableOrderedSetValueForKey:@"inputs"];
        NSMutableOrderedSet *outputs = [self mutableOrderedSetValueForKey:@"outputs"];
        NSUInteger idx = 0;
        
        self.txHash = tx.txHash;
        self.blockHeight = tx.blockHeight;
        if (self.timeStamp < 1.0) self.timeStamp = [NSDate timeIntervalSinceReferenceDate];
    
        while (inputs.count < tx.inputHashes.count) {
            [inputs addObject:[ZNTxInputEntity managedObject]];
        }
    
        while (inputs.count > tx.inputHashes.count) {
            [inputs removeObjectAtIndex:inputs.count - 1];
        }
    
        for (ZNTxInputEntity *e in inputs) {
            [e setAttributesFromTx:tx inputIndex:idx++];
        }

        while (outputs.count < tx.outputAddresses.count) {
            [outputs addObject:[ZNTxOutputEntity managedObject]];
        }
    
        while (outputs.count > tx.outputAddresses.count) {
            [self removeObjectFromOutputsAtIndex:outputs.count - 1];
        }

        idx = 0;
        
        for (ZNTxOutputEntity *e in outputs) {
            [e setAttributesFromTx:tx outputIndex:idx++];
        }
        
        self.lockTime = tx.lockTime;
    }];
    
    return self;
}

- (ZNTransaction *)transaction
{
    __block ZNTransaction *tx = [ZNTransaction new];
    
    [[self managedObjectContext] performBlockAndWait:^{
        tx.txHash = self.txHash;
        tx.lockTime = self.lockTime;
        tx.blockHeight = self.blockHeight;
    
        for (ZNTxInputEntity *e in self.inputs) {
            [tx addInputHash:e.txHash index:e.n script:nil signature:e.signature sequence:e.sequence];
        }
        
        for (ZNTxOutputEntity *e in self.outputs) {
            [tx addOutputScript:e.script amount:e.value];
        }
    }];
    
    return tx;
}

- (void)deleteObject
{
    for (ZNTxInputEntity *e in self.inputs) {
        if ([ZNTxInputEntity countObjectsMatching:@"txHash == %@ && n == %d", e.txHash, e.n] > 1) continue;
        [[ZNTxOutputEntity objectsMatching:@"txHash == %@ && n == %d", e.txHash, e.n].lastObject setSpent:NO];
    }

    [super deleteObject];
}

@end
