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

+ (instancetype)createOrUpdateWithBlock:(ZNMerkleBlock *)block atHeight:(int32_t)height
{
    __block ZNMerkleBlockEntity *e = nil;

    [[self context] performBlockAndWait:^{
        NSMutableDictionary *allBlocks = [self _allBlocks];
        NSMutableArray *orderedBlocks = [self _orderedBlocks];
        
        e = allBlocks[block.blockHash];
       
        if (! e || e.isDeleted) {
            e = [ZNMerkleBlockEntity managedObject];
            e.blockHash = block.blockHash;
            e.version = block.version;
            e.prevBlock = block.prevBlock;
            e.merkleRoot = block.merkleRoot;
            e.timestamp = block.timestamp;
            e.bits = block.bits;
            e.nonce = block.nonce;
            allBlocks[block.blockHash] = e;
            if (height >= 0) {
                if (orderedBlocks.count != height) {
                    while (orderedBlocks.count <= height) [orderedBlocks addObject:[NSNull null]];
                    orderedBlocks[height] = e;
                }
                else [orderedBlocks addObject:e];
            }
        }
       
        e.totalTransactions = block.totalTransactions;
        e.hashes = block.hashes;
        e.flags = block.flags;
        e.height = height;
    }];
    
    return e;
}

+ (instancetype)blockForHash:(NSData *)blockHash
{
    ZNMerkleBlockEntity *e = [self _allBlocks][blockHash];

    return e.isDeleted ? nil : e;
}

+ (instancetype)blockAtHeight:(int32_t)height
{
    NSArray *orderedBlocks = [self _orderedBlocks];
    ZNMerkleBlockEntity *e = (height < orderedBlocks.count) ? orderedBlocks[height] : nil;
    
    return (e.isDeleted || e == (id)[NSNull null]) ? nil : e;
}

+ (instancetype)topBlock
{
    return [self _orderedBlocks].lastObject;
}

+ (NSMutableDictionary *)_allBlocks
{
    static NSMutableDictionary *blocks = nil;
    static dispatch_once_t onceToken = 0;
    
    dispatch_once(&onceToken, ^{
        blocks = [NSMutableDictionary dictionary];
        
        [[self context] performBlockAndWait:^{
            for (ZNMerkleBlockEntity *e in [ZNMerkleBlockEntity allObjects]) {
                blocks[e.blockHash] = e;
            }
        }];
    });
    
    return blocks;
}

+ (NSMutableArray *)_orderedBlocks
{
    static NSMutableArray *blocks = nil;
    static dispatch_once_t onceToken = 0;
    
    dispatch_once(&onceToken, ^{
        blocks = [NSMutableArray array];
        
        [[self context] performBlockAndWait:^{
            for (ZNMerkleBlockEntity *e in [ZNMerkleBlockEntity objectsSortedBy:@"height" ascending:YES]) {
                int32_t height = e.height;
                
                if (height >= 0) {
                    if (blocks.count != height) {
                        while (blocks.count <= height) [blocks addObject:[NSNull null]];
                        blocks[height] = e;
                    }
                    else [blocks addObject:e];
                }
            }
        }];
    });
    
    return blocks;
}

- (void)setTreeFromBlock:(ZNMerkleBlock *)block
{
    [[self managedObjectContext] performBlockAndWait:^{
        self.totalTransactions = block.totalTransactions;
        self.hashes = [NSData dataWithData:block.hashes];
        self.flags = [NSData dataWithData:block.flags];
    }];
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
