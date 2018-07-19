//
//  DSMerkleBlockEntity+CoreDataClass.m
//  
//  Created by Sam Westrich on 5/20/18.
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

#import "DSMerkleBlockEntity+CoreDataClass.h"
#import "DSMerkleBlock.h"
#import "NSData+Bitcoin.h"
#import "DSChainEntity+CoreDataClass.h"
#import "NSManagedObject+Sugar.h"
#import "DSChain.h"

@implementation DSMerkleBlockEntity

- (instancetype)setAttributesFromBlock:(DSMerkleBlock *)block;
{
    [self.managedObjectContext performBlockAndWait:^{
        self.blockHash = [NSData dataWithBytes:block.blockHash.u8 length:sizeof(UInt256)];
        self.version = block.version;
        self.prevBlock = [NSData dataWithBytes:block.prevBlock.u8 length:sizeof(UInt256)];
        self.merkleRoot = [NSData dataWithBytes:block.merkleRoot.u8 length:sizeof(UInt256)];
        self.timestamp = block.timestamp - NSTimeIntervalSince1970;
        self.target = block.target;
        self.nonce = block.nonce;
        self.totalTransactions = block.totalTransactions;
        self.hashes = [NSData dataWithData:block.hashes];
        self.flags = [NSData dataWithData:block.flags];
        self.height = block.height;
        self.chain = [block.chain chainEntity];
    }];
    
    return self;
}

- (instancetype)setAttributesFromBlock:(DSMerkleBlock *)block forChain:(DSChainEntity*)chainEntity {
    [self.managedObjectContext performBlockAndWait:^{
        self.blockHash = [NSData dataWithBytes:block.blockHash.u8 length:sizeof(UInt256)];
        self.version = block.version;
        self.prevBlock = [NSData dataWithBytes:block.prevBlock.u8 length:sizeof(UInt256)];
        self.merkleRoot = [NSData dataWithBytes:block.merkleRoot.u8 length:sizeof(UInt256)];
        self.timestamp = block.timestamp - NSTimeIntervalSince1970;
        self.target = block.target;
        self.nonce = block.nonce;
        self.totalTransactions = block.totalTransactions;
        self.hashes = [NSData dataWithData:block.hashes];
        self.flags = [NSData dataWithData:block.flags];
        self.height = block.height;
        self.chain = chainEntity;
    }];
    
    return self;
}

- (DSMerkleBlock *)merkleBlock
{
    __block DSMerkleBlock *block = nil;
    
    [self.managedObjectContext performBlockAndWait:^{
        NSData *blockHash = self.blockHash, *prevBlock = self.prevBlock, *merkleRoot = self.merkleRoot;
        UInt256 hash = (blockHash.length == sizeof(UInt256)) ? *(const UInt256 *)blockHash.bytes : UINT256_ZERO,
        prev = (prevBlock.length == sizeof(UInt256)) ? *(const UInt256 *)prevBlock.bytes : UINT256_ZERO,
        root = (merkleRoot.length == sizeof(UInt256)) ? *(const UInt256 *)merkleRoot.bytes : UINT256_ZERO;
        
        block = [[DSMerkleBlock alloc] initWithBlockHash:hash onChain:self.chain.chain version:self.version prevBlock:prev merkleRoot:root
                                               timestamp:self.timestamp + NSTimeIntervalSince1970 target:self.target nonce:self.nonce
                                       totalTransactions:self.totalTransactions hashes:self.hashes flags:self.flags height:self.height];
    }];
    
    return block;
}

+ (NSArray<DSMerkleBlockEntity*>*)lastBlocks:(uint32_t)blockcount onChain:(DSChainEntity*)chainEntity {
    __block NSArray * blocks = nil;
    [chainEntity.managedObjectContext performBlockAndWait:^{
        NSFetchRequest * fetchRequest = [DSMerkleBlockEntity fetchReq];
        [fetchRequest setPredicate:[NSPredicate predicateWithFormat:@"(chain == %@)",chainEntity]];
        [fetchRequest setSortDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"height" ascending:FALSE]]];
        [fetchRequest setFetchLimit:blockcount];
        blocks = [DSMerkleBlockEntity fetchObjects:fetchRequest];
    }];
    return blocks;
}

+ (void)deleteBlocksOnChain:(DSChainEntity*)chainEntity {
    [chainEntity.managedObjectContext performBlockAndWait:^{
        NSArray * merkleBlocksToDelete = [self objectsMatching:@"(chain == %@)",chainEntity];
        for (DSMerkleBlockEntity * merkleBlock in merkleBlocksToDelete) {
            [chainEntity.managedObjectContext deleteObject:merkleBlock];
        }
    }];
}

@end
