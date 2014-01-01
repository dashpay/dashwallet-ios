
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
@dynamic target;
@dynamic nonce;
@dynamic totalTransactions;
@dynamic hashes;
@dynamic flags;

// the block store has it's own context for performance reasons
+ (NSManagedObjectContext *)context
{
    static NSManagedObjectContext *moc = nil;
    static dispatch_once_t onceToken = 0;

    dispatch_once(&onceToken, ^{
        moc = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        moc.parentContext = [super context].parentContext;
    });

    return moc;
}

- (instancetype)setAttributesFromBlock:(ZNMerkleBlock *)block;
{
    [[self managedObjectContext] performBlockAndWait:^{
        self.blockHash = block.blockHash;
        self.version = block.version;
        self.prevBlock = block.prevBlock;
        self.merkleRoot = block.merkleRoot;
        self.timestamp = block.timestamp;
        self.target = block.target;
        self.nonce = block.nonce;
        self.totalTransactions = block.totalTransactions;
        self.hashes = [NSData dataWithData:block.hashes];
        self.flags = [NSData dataWithData:block.flags];
    }];

    return self;
}

- (ZNMerkleBlock *)merkleBlock
{
    __block ZNMerkleBlock *block = nil;
    
    [[self managedObjectContext] performBlockAndWait:^{
        block = [[ZNMerkleBlock alloc] initWithBlockHash:self.blockHash version:self.version prevBlock:self.prevBlock
                 merkleRoot:self.merkleRoot timestamp:self.timestamp target:self.target nonce:self.nonce
                 totalTransactions:self.totalTransactions hashes:self.hashes flags:self.flags];
    }];
    
    return block;
}

@end
