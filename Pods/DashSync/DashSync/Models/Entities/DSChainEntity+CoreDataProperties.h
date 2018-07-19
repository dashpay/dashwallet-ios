//
//  DSChainEntity+CoreDataProperties.h
//  
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

#import "DSChainEntity+CoreDataClass.h"


NS_ASSUME_NONNULL_BEGIN

@interface DSChainEntity (CoreDataProperties)

+ (NSFetchRequest<DSChainEntity *> *)fetchRequest;

@property (nullable, nonatomic, retain) NSData *checkpoints;
@property (nullable, nonatomic, copy) NSString *devnetIdentifier;
@property (nonatomic, assign) uint32_t standardPort;
@property (nonatomic, assign) uint32_t totalMasternodeCount;
@property (nonatomic, assign) uint32_t totalGovernanceObjectsCount;
@property (nonatomic, assign) uint16_t type;
@property (nonnull, nonatomic, retain) NSSet<DSPeerEntity *> *peers;
@property (nonnull, nonatomic, retain) NSSet<DSTransactionEntity *> *transactions;
@property (nonnull, nonatomic, retain) NSSet<DSMerkleBlockEntity *> *blocks;
@property (nonnull, nonatomic, retain) NSSet<DSDerivationPathEntity *> *derivationPaths;
@property (nonnull, nonatomic, retain) NSSet<DSMasternodeBroadcastHashEntity *> *masternodeBroadcastHashes;

@end

@interface DSChainEntity (CoreDataGeneratedAccessors)

- (void)addPeersObject:(DSPeerEntity *)value;
- (void)removePeersObject:(DSPeerEntity *)value;
- (void)addPeers:(NSSet<DSPeerEntity *> *)values;
- (void)removePeers:(NSSet<DSPeerEntity *> *)values;

- (void)addTransactionsObject:(DSTransactionEntity *)value;
- (void)removeTransactionsObject:(DSTransactionEntity *)value;
- (void)addTransactions:(NSSet<DSTransactionEntity *> *)values;
- (void)removeTransactions:(NSSet<DSTransactionEntity *> *)values;

- (void)addBlocksObject:(DSMerkleBlockEntity *)value;
- (void)removeBlocksObject:(DSMerkleBlockEntity *)value;
- (void)addBlocks:(NSSet<DSMerkleBlockEntity *> *)values;
- (void)removeBlocks:(NSSet<DSMerkleBlockEntity *> *)values;

@end

NS_ASSUME_NONNULL_END
