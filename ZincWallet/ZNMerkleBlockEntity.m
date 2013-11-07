//
//  ZNMerkleBlockEntity.m
//  ZincWallet
//
//  Created by Aaron Voisine on 10/19/13.
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

#import "ZNMerkleBlockEntity.h"
#import "ZNMerkleBlock.h"
#import "NSManagedObject+Utils.h"

@implementation ZNMerkleBlockEntity

@dynamic blockHash;
@dynamic height;
@dynamic version;
@dynamic prevBlock;
@dynamic merkleRoot;
@dynamic timestamp;
@dynamic bits;
@dynamic nonce;
@dynamic totalTransactions;
@dynamic hashes;
@dynamic flags;

+ (instancetype)createOrUpdateWithMerkleBlock:(ZNMerkleBlock *)block atHeight:(int32_t)height
{
    __block ZNMerkleBlockEntity *e = nil;

    [[self context] performBlockAndWait:^{
        e = [ZNMerkleBlockEntity objectsMatching:@"blockHash == %@", block.blockHash].lastObject;
       
        if (! e) {
            e = [ZNMerkleBlockEntity managedObject];
            e.blockHash = block.blockHash;
            [[self _allBlockHashes] addObject:e.blockHash];
        }
       
        e.version = block.version;
        e.prevBlock = block.prevBlock;
        e.merkleRoot = block.merkleRoot;
        e.timestamp = block.timestamp;
        e.bits = block.bits;
        e.nonce = block.nonce;
        e.totalTransactions = block.totalTransactions;
        e.hashes = block.hashes;
        e.flags = block.flags;
        e.height = height;
    }];
    
    return e;
}

// more efficient method for creating or updating a chain of blocks all at once
+ (NSArray *)createOrUpdateWithChain:(NSArray *)chain startHeight:(int32_t)height
{
    NSMutableArray *a = [NSMutableArray arrayWithCapacity:chain.count];
    
    [[self context] performBlockAndWait:^{
        NSMutableSet *blockHashes = [self _allBlockHashes];
        NSUInteger idx = 0;
        
        for (ZNMerkleBlock *block in chain) {
            ZNMerkleBlockEntity *e = nil;
            
            if ([blockHashes containsObject:block.blockHash]) {
                e = [ZNMerkleBlockEntity objectsMatching:@"blockHash == %@", block.blockHash].lastObject;
            }

            if (! e) {
                e = [ZNMerkleBlockEntity managedObject];
                e.blockHash = block.blockHash;
                [blockHashes addObject:block.blockHash];
                e.version = block.version;
                e.prevBlock = block.prevBlock;
                e.merkleRoot = block.merkleRoot;
                e.timestamp = block.timestamp;
                e.bits = block.bits;
                e.nonce = block.nonce;
            }
            
            e.totalTransactions = block.totalTransactions;
            e.hashes = block.hashes;
            e.flags = block.flags;
            e.height = height + idx;
            [a addObject:e];
            idx++;
        }        
    }];
    
#if DEBUG
    static int count = 0;

    count += a.count;
    NSLog(@"created or updated %d blocks", count);
#endif

    return a;
}

+ (BOOL)updateTreeFromMerkleBlock:(ZNMerkleBlock *)block
{
    __block ZNMerkleBlockEntity *e = nil;
    
    [[self context] performBlockAndWait:^{
        e = [ZNMerkleBlockEntity objectsMatching:@"blockHash == %@", block.blockHash].lastObject;
        e.hashes = [NSData dataWithData:block.hashes];
        e.flags = [NSData dataWithData:block.flags];
    }];
    
    return (e != nil) ? YES : NO;
}

+ (NSMutableSet *)_allBlockHashes
{
    static NSMutableSet *blockHashes = nil;
    static dispatch_once_t onceToken = 0;
    
    dispatch_once(&onceToken, ^{
        [[self context] performBlockAndWait:^{
            blockHashes = [NSMutableSet setWithArray:[[ZNMerkleBlockEntity allObjects] valueForKey:@"blockHash"]];
        }];
    });
    
    return blockHashes;
}

- (ZNMerkleBlock *)merkleBlock
{
    __block ZNMerkleBlock *block = nil;
    
    [[self managedObjectContext] performBlockAndWait:^{
        block = [[ZNMerkleBlock alloc] initWithBlockHash:self.blockHash version:self.version prevBlock:self.prevBlock
                 merkleRoot:self.merkleRoot timestamp:self.timestamp bits:self.bits nonce:self.nonce
                 totalTransactions:self.totalTransactions hashes:self.hashes flags:self.flags];
    }];
    
    return block;
}

@end
