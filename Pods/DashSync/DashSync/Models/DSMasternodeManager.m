//
//  DSMasternodeManager.m
//  DashSync
//
//  Created by Sam Westrich on 6/7/18.
//

#import "DSMasternodeManager.h"
#import "DSMasternodeBroadcast.h"
#import "DSMasternodePing.h"
#import "DSMasternodeBroadcastEntity+CoreDataProperties.h"
#import "DSMasternodeBroadcastHashEntity+CoreDataProperties.h"
#import "DSChainEntity+CoreDataProperties.h"
#import "NSManagedObject+Sugar.h"
#import "DSChain.h"
#import "DSPeer.h"
#import "NSData+Dash.h"
#import "DSChainPeerManager.h"
#import "DSTransactionFactory.h"
#import "NSMutableData+Dash.h"
#import "DSSimplifiedMasternodeEntry.h"

// from https://en.bitcoin.it/wiki/Protocol_specification#Merkle_Trees
// Merkle trees are binary trees of hashes. Merkle trees in bitcoin use a double SHA-256, the SHA-256 hash of the
// SHA-256 hash of something. If, when forming a row in the tree (other than the root of the tree), it would have an odd
// number of elements, the final double-hash is duplicated to ensure that the row has an even number of hashes. First
// form the bottom row of the tree with the ordered double-SHA-256 hashes of the byte streams of the transactions in the
// block. Then the row above it consists of half that number of hashes. Each entry is the double-SHA-256 of the 64-byte
// concatenation of the corresponding two hashes below it in the tree. This procedure repeats recursively until we reach
// a row consisting of just a single double-hash. This is the merkle root of the tree.
//
// from https://github.com/bitcoin/bips/blob/master/bip-0037.mediawiki#Partial_Merkle_branch_format
// The encoding works as follows: we traverse the tree in depth-first order, storing a bit for each traversed node,
// signifying whether the node is the parent of at least one matched leaf txid (or a matched txid itself). In case we
// are at the leaf level, or this bit is 0, its merkle node hash is stored, and its children are not explored further.
// Otherwise, no hash is stored, but we recurse into both (or the only) child branch. During decoding, the same
// depth-first traversal is performed, consuming bits and hashes as they written during encoding.
//
// example tree with three transactions, where only tx2 is matched by the bloom filter:
//
//     merkleRoot
//      /     \
//    m1       m2
//   /  \     /  \
// tx1  tx2 tx3  tx3
//
// flag bits (little endian): 00001011 [merkleRoot = 1, m1 = 1, tx1 = 0, tx2 = 1, m2 = 0, byte padding = 000]
// hashes: [tx1, tx2, m2]

inline static int ceil_log2(int x)
{
    int r = (x & (x - 1)) ? 1 : 0;
    
    while ((x >>= 1) != 0) r++;
    return r;
}

#define REQUEST_MASTERNODE_BROADCAST_COUNT 500


@interface DSMasternodeManager()

@property (nonatomic,strong) DSChain * chain;
@property (nonatomic,strong) NSOrderedSet * knownHashes;
@property (nonatomic,readonly) NSOrderedSet * fulfilledRequestsHashEntities;
@property (nonatomic,strong) NSMutableArray *needsRequestsHashEntities;
@property (nonatomic,strong) NSMutableArray * requestHashEntities;
@property (nonatomic,strong) NSMutableArray<DSMasternodeBroadcast *> * masternodeBroadcasts;
@property (nonatomic,assign) NSUInteger masternodeBroadcastsCount;
@property (nonatomic,strong) NSManagedObjectContext * managedObjectContext;

@property (nonatomic,assign) UInt256 baseBlockHash;
@property (nonatomic,strong) NSMutableArray *simplifiedMasternodeList;

@end

@implementation DSMasternodeManager

- (instancetype)initWithChain:(id)chain
{
    if (! (self = [super init])) return nil;
    _chain = chain;
    _masternodeBroadcasts = [NSMutableArray array];
    _simplifiedMasternodeList = [NSMutableArray array];
    self.managedObjectContext = [NSManagedObject context];
    return self;
}

//-(NSArray*)masternodeHashes {
//
//}

-(NSUInteger)recentMasternodeBroadcastHashesCount {
    __block NSUInteger count = 0;
    [self.managedObjectContext performBlockAndWait:^{
        count = [DSMasternodeBroadcastHashEntity countAroundNowOnChain:self.chain.chainEntity];
    }];
    return count;
}

-(NSUInteger)last3HoursStandaloneBroadcastHashesCount {
    __block NSUInteger count = 0;
    [self.managedObjectContext performBlockAndWait:^{
        [DSMasternodeBroadcastHashEntity setContext:self.managedObjectContext];
        count = [DSMasternodeBroadcastHashEntity standaloneCountInLast3hoursOnChain:self.chain.chainEntity];
    }];
    return count;
}

-(NSUInteger)masternodeBroadcastsCount {
    
    __block NSUInteger count = 0;
    [self.managedObjectContext performBlockAndWait:^{
        [DSMasternodeBroadcastEntity setContext:self.managedObjectContext];
        count = [DSMasternodeBroadcastEntity countForChain:self.chain.chainEntity];
    }];
    return count;
}


-(void)loadMasternodes:(NSUInteger)count {
    NSFetchRequest * fetchRequest = [[DSMasternodeBroadcastEntity fetchRequest] copy];
    [fetchRequest setFetchLimit:count];
    NSArray * masternodeBroadcastEntities = [DSMasternodeBroadcastEntity fetchObjects:fetchRequest];
    for (DSMasternodeBroadcastEntity * masternodeBroadcastEntity in masternodeBroadcastEntities) {
        DSUTXO utxo;
        utxo.hash = *(UInt256 *)masternodeBroadcastEntity.utxoHash.bytes;
        utxo.n = masternodeBroadcastEntity.utxoIndex;
        UInt128 ipv6address = UINT128_ZERO;
        ipv6address.u32[3] = masternodeBroadcastEntity.address;
        UInt256 masternodeBroadcastHash = *(UInt256 *)masternodeBroadcastEntity.masternodeBroadcastHash.masternodeBroadcastHash.bytes;
        DSMasternodeBroadcast * masternodeBroadcast = [[DSMasternodeBroadcast alloc] initWithUTXO:utxo ipAddress:ipv6address port:masternodeBroadcastEntity.port protocolVersion:masternodeBroadcastEntity.protocolVersion publicKey:masternodeBroadcastEntity.publicKey signature:masternodeBroadcastEntity.signature signatureTimestamp:masternodeBroadcastEntity.signatureTimestamp masternodeBroadcastHash:masternodeBroadcastHash onChain:self.chain];
        [_masternodeBroadcasts addObject:masternodeBroadcast];
    }
}

-(NSOrderedSet*)knownHashes {
    @synchronized(self) {
    if (_knownHashes) return _knownHashes;
    
    [self.managedObjectContext performBlockAndWait:^{
        [DSMasternodeBroadcastHashEntity setContext:self.managedObjectContext];
        NSFetchRequest *request = DSMasternodeBroadcastHashEntity.fetchReq;
        [request setPredicate:[NSPredicate predicateWithFormat:@"chain = %@",self.chain.chainEntity]];
        [request setSortDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"masternodeBroadcastHash" ascending:TRUE]]];
        NSArray<DSMasternodeBroadcastHashEntity *> * knownMasternodeBroadcastHashEntities = [DSMasternodeBroadcastHashEntity fetchObjects:request];
        NSMutableOrderedSet <NSData*> * rHashes = [NSMutableOrderedSet orderedSetWithCapacity:knownMasternodeBroadcastHashEntities.count];
        for (DSMasternodeBroadcastHashEntity * knownMasternodeBroadcastHashEntity in knownMasternodeBroadcastHashEntities) {
            NSData * hash = knownMasternodeBroadcastHashEntity.masternodeBroadcastHash;
            [rHashes addObject:hash];
        }
        self.knownHashes = [rHashes copy];
    }];
    return _knownHashes;
    }
}

-(NSMutableArray*)needsRequestsHashEntities {
    @synchronized(self) {
    if (_needsRequestsHashEntities) return _needsRequestsHashEntities;
    
    [self.managedObjectContext performBlockAndWait:^{
        [DSMasternodeBroadcastHashEntity setContext:self.managedObjectContext];
        NSFetchRequest *request = DSMasternodeBroadcastHashEntity.fetchReq;
        [request setPredicate:[NSPredicate predicateWithFormat:@"chain = %@ && masternodeBroadcast == nil",self.chain.chainEntity]];
        [request setSortDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"masternodeBroadcastHash" ascending:TRUE]]];
        self.needsRequestsHashEntities = [[DSMasternodeBroadcastHashEntity fetchObjects:request] mutableCopy];
        
    }];
    return _needsRequestsHashEntities;
    }
}

-(NSArray*)needsRequestsHashes {
    __block NSMutableArray * mArray = [NSMutableArray array];
    [self.managedObjectContext performBlockAndWait:^{
        [DSMasternodeBroadcastHashEntity setContext:self.managedObjectContext];
        for (DSMasternodeBroadcastHashEntity * masternodeBroadcastHashEntity in self.needsRequestsHashEntities) {
            [mArray addObject:masternodeBroadcastHashEntity.masternodeBroadcastHash];
        }
    }];
    return [mArray copy];
}

-(NSOrderedSet*)fulfilledRequestsHashEntities {
    @synchronized(self) {
    __block NSOrderedSet * orderedSet;
    [self.managedObjectContext performBlockAndWait:^{
        [DSMasternodeBroadcastHashEntity setContext:self.managedObjectContext];
        [DSChainEntity setContext:self.managedObjectContext];
        NSFetchRequest *request = DSMasternodeBroadcastHashEntity.fetchReq;
        [request setPredicate:[NSPredicate predicateWithFormat:@"chain = %@ && masternodeBroadcast != nil",self.chain.chainEntity]];
        [request setSortDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"masternodeBroadcastHash" ascending:TRUE]]];
        orderedSet = [NSOrderedSet orderedSetWithArray:[DSMasternodeBroadcastHashEntity fetchObjects:request]];
        
    }];
    return orderedSet;
    }
}

-(NSOrderedSet*)fulfilledRequestsHashes {
    NSMutableOrderedSet * mOrderedSet = [NSMutableOrderedSet orderedSet];
    for (DSMasternodeBroadcastHashEntity * masternodeBroadcastHashEntity in self.fulfilledRequestsHashEntities) {
        [mOrderedSet addObject:masternodeBroadcastHashEntity.masternodeBroadcastHash];
    }
    return [mOrderedSet copy];
}

-(void)requestMasternodeBroadcastsFromPeer:(DSPeer*)peer {
    if (![self.needsRequestsHashEntities count]) {
        //we are done syncing
        return;
    }
    self.requestHashEntities = [[self.needsRequestsHashEntities subarrayWithRange:NSMakeRange(0, MIN(self.needsRequestsHashes.count,REQUEST_MASTERNODE_BROADCAST_COUNT))] mutableCopy];
    NSMutableArray * requestHashes = [NSMutableArray array];
    for (DSMasternodeBroadcastHashEntity * masternodeBroadcastHashEntity in self.requestHashEntities) {
        [requestHashes addObject:masternodeBroadcastHashEntity.masternodeBroadcastHash];
    }
    [peer sendGetdataMessageWithMasternodeBroadcastHashes:requestHashes];
}

- (void)peer:(DSPeer *)peer hasMasternodeBroadcastHashes:(NSSet*)masternodeBroadcastHashes {
    NSLog(@"peer relayed masternode broadcasts");
    @synchronized(self) {
        NSMutableOrderedSet * hashesToInsert = [[NSOrderedSet orderedSetWithSet:masternodeBroadcastHashes] mutableCopy];
        NSMutableOrderedSet * hashesToUpdate = [[NSOrderedSet orderedSetWithSet:masternodeBroadcastHashes] mutableCopy];
        NSMutableOrderedSet * hashesToQuery = [[NSOrderedSet orderedSetWithSet:masternodeBroadcastHashes] mutableCopy];
        NSMutableOrderedSet <NSData*> * rHashes = [_knownHashes mutableCopy];
        [hashesToInsert minusOrderedSet:self.knownHashes];
        [hashesToUpdate minusOrderedSet:hashesToInsert];
        [hashesToQuery minusOrderedSet:self.fulfilledRequestsHashes];
        NSMutableOrderedSet * hashesToQueryFromInsert = [hashesToQuery mutableCopy];
        [hashesToQueryFromInsert intersectOrderedSet:hashesToInsert];
        NSMutableArray * hashEntitiesToQuery = [NSMutableArray array];
        NSMutableArray <NSData*> * rNeedsRequestsHashEntities = [self.needsRequestsHashEntities mutableCopy];
        if ([masternodeBroadcastHashes count]) {
            [self.managedObjectContext performBlockAndWait:^{
                [DSMasternodeBroadcastHashEntity setContext:self.managedObjectContext];
                if ([hashesToInsert count]) {
                    NSArray * novelMasternodeBroadcastHashEntities = [DSMasternodeBroadcastHashEntity masternodeBroadcastHashEntitiesWithHashes:hashesToInsert onChain:self.chain.chainEntity];
                    for (DSMasternodeBroadcastHashEntity * masternodeBroadcastHashEntity in novelMasternodeBroadcastHashEntities) {
                        if ([hashesToQueryFromInsert containsObject:masternodeBroadcastHashEntity.masternodeBroadcastHash]) {
                            [hashEntitiesToQuery addObject:masternodeBroadcastHashEntity];
                        }
                    }
                }
                if ([hashesToUpdate count]) {
                    [DSMasternodeBroadcastHashEntity updateTimestampForMasternodeBroadcastHashEntitiesWithMasternodeBroadcastHashes:hashesToUpdate onChain:self.chain.chainEntity];
                }
                [DSMasternodeBroadcastHashEntity saveContext];
            }];
            if ([hashesToInsert count]) {
                [rHashes addObjectsFromArray:[hashesToInsert array]];
                [rHashes sortUsingComparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
                    UInt256 a = *(UInt256 *)((NSData*)obj1).bytes;
                    UInt256 b = *(UInt256 *)((NSData*)obj2).bytes;
                    return uint256_sup(a,b)?NSOrderedAscending:NSOrderedDescending;
                }];
            }
        }
        
        [rNeedsRequestsHashEntities addObjectsFromArray:hashEntitiesToQuery];
        [rNeedsRequestsHashEntities sortUsingComparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
            UInt256 a = *(UInt256 *)((NSData*)((DSMasternodeBroadcastHashEntity*)obj1).masternodeBroadcastHash).bytes;
            UInt256 b = *(UInt256 *)((NSData*)((DSMasternodeBroadcastHashEntity*)obj2).masternodeBroadcastHash).bytes;
            return uint256_sup(a,b)?NSOrderedAscending:NSOrderedDescending;
        }];
        self.knownHashes = rHashes;
        self.needsRequestsHashEntities = rNeedsRequestsHashEntities;
        NSLog(@"-> %lu - %lu",(unsigned long)[self.knownHashes count],(unsigned long)self.chain.totalMasternodeCount);
        NSUInteger countAroundNow = [self recentMasternodeBroadcastHashesCount];
        if ([self.knownHashes count] > self.chain.totalMasternodeCount) {
            [self.managedObjectContext performBlockAndWait:^{
                [DSMasternodeBroadcastHashEntity setContext:self.managedObjectContext];
                NSLog(@"countAroundNow -> %lu - %lu",(unsigned long)countAroundNow,(unsigned long)self.chain.totalMasternodeCount);
                if (countAroundNow == self.chain.totalMasternodeCount) {
                    [DSMasternodeBroadcastHashEntity removeOldest:[self.knownHashes count] - self.chain.totalMasternodeCount onChain:self.chain.chainEntity];
                    [self requestMasternodeBroadcastsFromPeer:peer];
                }
            }];
        } else if (countAroundNow == self.chain.totalMasternodeCount) {
            NSLog(@"%@",@"All masternode broadcast hashes received");
            //we have all hashes, let's request objects.
            [self requestMasternodeBroadcastsFromPeer:peer];
        }
    }
}

-(void)finishedMasternodeListSyncWithPeer:(DSPeer*)peer {
    [[NSUserDefaults standardUserDefaults] setInteger:[[NSDate date] timeIntervalSince1970] forKey:[NSString stringWithFormat:@"%@-%@",self.chain.uniqueID,LAST_SYNCED_MASTERNODE_LIST]];
}

- (void)peer:(DSPeer * )peer relayedMasternodeBroadcast:(DSMasternodeBroadcast * )masternodeBroadcast {
    @synchronized(self) {
        NSData *masternodeBroadcastHash = [NSData dataWithUInt256:masternodeBroadcast.masternodeBroadcastHash];
        DSMasternodeBroadcastHashEntity * relatedHashEntity = nil;
        for (DSMasternodeBroadcastHashEntity * masternodeBroadcastHashEntity in [self.requestHashEntities copy]) {
            if ([masternodeBroadcastHashEntity.masternodeBroadcastHash isEqual:masternodeBroadcastHash]) {
                relatedHashEntity = masternodeBroadcastHashEntity;
                [self.requestHashEntities removeObject:masternodeBroadcastHashEntity];
                break;
            }
        }
        NSAssert(relatedHashEntity, @"There needs to be a relatedHashEntity");
        if (!relatedHashEntity) return;
        NSArray * broadcastEntities = [DSMasternodeBroadcastEntity objectsMatching:@"masternodeBroadcastHash = %@",relatedHashEntity];
        if ([broadcastEntities count]) {
            [[broadcastEntities objectAtIndex:0] setAttributesFromMasternodeBroadcast:masternodeBroadcast forHashEntity:relatedHashEntity];
        } else {
            [[DSMasternodeBroadcastEntity managedObject] setAttributesFromMasternodeBroadcast:masternodeBroadcast forHashEntity:relatedHashEntity];
        }
        [self.needsRequestsHashEntities removeObject:relatedHashEntity];
        [self.masternodeBroadcasts addObject:masternodeBroadcast];
        if (![self.requestHashEntities count]) {
            [self requestMasternodeBroadcastsFromPeer:peer];
            [DSMasternodeBroadcastEntity saveContext];
            [self finishedMasternodeListSyncWithPeer:peer];
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:DSMasternodeListDidChangeNotification object:self userInfo:@{DSChainPeerManagerNotificationChainKey:self.chain}];
            });
        }
    }
}

- (void)peer:(DSPeer * _Nullable)peer relayedMasternodePing:(DSMasternodePing*  _Nonnull)masternodePing {
    
}

-(DSMasternodeBroadcast*)masternodeBroadcastForUniqueID:(NSString*)uniqueId {
    __block DSMasternodeBroadcast * masternodeBroadcast = nil;
    [self.managedObjectContext performBlockAndWait:^{
        [DSMasternodeBroadcastEntity setContext:self.managedObjectContext];
        NSArray * array = [DSMasternodeBroadcastEntity objectsMatching:@"uniqueID = %@",uniqueId];
        if (array.count) {
            DSMasternodeBroadcastEntity * masternodeBroadcastEntity = [array objectAtIndex:0];
            masternodeBroadcast = [masternodeBroadcastEntity masternodeBroadcast];
        }
    }];
    return masternodeBroadcast;
}

//-(void)saveBroadcast:(DSMasternodeBroadcast*)masternodeBroadcast forHashEntity:(DSMasternodeBroadcastHashEntity*)masternodeBroadcastHashEntity {
//    NSLog(@"[DSMasternodeManager] save broadcasts");
//    if ([self.masternodeBroadcasts count]) {
//
//        NSAssert(self.managedObjectContext == masternodeBroadcastHashEntity.managedObjectContext, @"must be same contexts");
//
//
//
//
//
//    }
//}

-(DSMasternodeBroadcast*)masternodeBroadcastForUTXO:(DSUTXO)masternodeUTXO {
    __block DSMasternodeBroadcast * masternodeBroadcast = nil;
    [self.managedObjectContext performBlockAndWait:^{
        [DSMasternodeBroadcastEntity setContext:self.managedObjectContext];
        NSFetchRequest *request = DSMasternodeBroadcastEntity.fetchReq;
        
        request.predicate = [NSPredicate predicateWithFormat:@"utxoHash = %@ && utxoIndex = %@",[NSData dataWithUInt256:(UInt256)masternodeUTXO.hash],@(masternodeUTXO.n)];
        [request setFetchLimit:1];
        NSArray * array = [DSMasternodeBroadcastEntity fetchObjectsInContext:request];
        if (array.count) {
            DSMasternodeBroadcastEntity * masternodeBroadcastEntity = [array objectAtIndex:0];
            masternodeBroadcast = [masternodeBroadcastEntity masternodeBroadcast];
        }
    }];
    return masternodeBroadcast;
}

-(void)wipeMasternodeInfo {
    [self.masternodeBroadcasts removeAllObjects];
    self.needsRequestsHashEntities = nil;
    self.knownHashes = nil;
    self.masternodeBroadcastsCount = 0;
}

// recursively walks the merkle tree in depth first order, calling leaf(hash, flag) for each stored hash, and
// branch(left, right) with the result from each branch
- (id)_walk:(int *)hashIdx :(int *)flagIdx :(int)depth :(id (^)(id, BOOL))leaf :(id (^)(id, id))branch :(NSData*)simplifiedMasternodeListHashes :(NSData*)flags
{
    if ((*flagIdx)/8 >= flags.length || (*hashIdx + 1)*sizeof(UInt256) > simplifiedMasternodeListHashes.length) return leaf(nil, NO);
    
    BOOL flag = (((const uint8_t *)flags.bytes)[*flagIdx/8] & (1 << (*flagIdx % 8)));
    
    (*flagIdx)++;
    
    if (! flag || depth == ceil_log2((int)_simplifiedMasternodeList.count)) {
        UInt256 hash = [simplifiedMasternodeListHashes hashAtOffset:(*hashIdx)*sizeof(UInt256)];
        
        (*hashIdx)++;
        return leaf(uint256_obj(hash), flag);
    }
    
    id left = [self _walk:hashIdx :flagIdx :depth + 1 :leaf :branch :simplifiedMasternodeListHashes :flags];
    id right = [self _walk:hashIdx :flagIdx :depth + 1 :leaf :branch :simplifiedMasternodeListHashes :flags];
    
    return branch(left, right);
}

-(UInt256)merkleRoot {
    [self.simplifiedMasternodeList sortUsingComparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
        DSSimplifiedMasternodeEntry * sml1 = obj1;
        DSSimplifiedMasternodeEntry * sml2 = obj2;
        return uint256_sup(sml1.providerRegistrationTransactionHash,sml2.providerRegistrationTransactionHash);
    }];
    NSMutableArray * higherLevel = nil;
    NSMutableArray * level = [self.simplifiedMasternodeList copy];
    while (higherLevel && higherLevel.count > 1) {
        higherLevel = [NSMutableArray array];
        for (int i = 0; i < level.count;i+=2) {
            if ([level count] - i > 2) {
                NSData * left = [level objectAtIndex:0];
                NSData * right = [level objectAtIndex:1];
                NSMutableData * combined = [NSMutableData data];
                [combined appendData:left];
                [combined appendData:right];
                [higherLevel addObject:[NSData dataWithUInt256:combined.SHA256_2]];
            } else {
                NSData * left = [level objectAtIndex:0];
                NSMutableData * combined = [NSMutableData data];
                [combined appendData:left];
                [combined appendData:left];
                [higherLevel addObject:[NSData dataWithUInt256:combined.SHA256_2]];
            }
        }
        level = higherLevel;
    }
    return [[higherLevel objectAtIndex:0] UInt256AtOffset:0];
}

//-(void)verify {
//    NSMutableData * simplifiedMasternodeListHashes = [NSMutableData data];
//    for (DSSimplifiedMasternodeEntry * simplifiedMasternodeEntry in self.simplifiedMasternodeList) {
//        [simplifiedMasternodeListHashes appendUInt256:simplifiedMasternodeEntry.simplifiedMasternodeEntryHash];
//    }
//    NSMutableData *d = [NSMutableData data];
//    UInt256 merkleRoot, t = UINT256_ZERO;
//    int hashIdx = 0, flagIdx = 0;
//    NSValue *root = [self _walk:&hashIdx :&flagIdx :0 :^id (id hash, BOOL flag) {
//        return hash;
//    } :^id (id left, id right) {
//        UInt256 l, r;
//        
//        if (! right) right = left; // if right branch is missing, duplicate left branch
//        [left getValue:&l];
//        [right getValue:&r];
//        d.length = 0;
//        [d appendBytes:&l length:sizeof(l)];
//        [d appendBytes:&r length:sizeof(r)];
//        return uint256_obj(d.SHA256_2);
//    } :simplifiedMasternodeListHashes :flags];
//    
//    [root getValue:&merkleRoot];
//}

-(void)peer:(DSPeer *)peer relayedMasternodeDiffMessage:(NSData*)message {
    NSUInteger length = message.length;
    NSUInteger offset = 0;
    
    if (length - offset < 32) return;
    UInt256 baseBlockHash = [message UInt256AtOffset:offset];
    offset += 32;
    
    if (!uint256_eq(baseBlockHash, self.baseBlockHash)) return;
    
    if (length - offset < 32) return;
    UInt256 blockHash = [message UInt256AtOffset:offset];
    offset += 32;
    
    if (length - offset < 4) return;
    uint32_t totalTransactions = [message UInt32AtOffset:offset];
    offset += 4;
    
    if (length - offset < 1) return;
    NSNumber * merkleHashCountLength;
    uint64_t merkleHashCount = [message varIntAtOffset:offset length:&merkleHashCountLength];
    offset += [merkleHashCountLength unsignedLongValue];
    
    NSMutableArray * merkleHashes = [NSMutableArray array];
    
    while (merkleHashCount >= 1) {
        if (length - offset < 32) return;
        [merkleHashes addObject:[NSData dataWithUInt256:[message UInt256AtOffset:offset]]];
        offset += 32;
        merkleHashCount--;
    }
    
    if (length - offset < 1) return;
    NSNumber * merkleFlagCountLength;
    uint64_t merkleFlagCount = [message varIntAtOffset:offset length:&merkleFlagCountLength];
    offset += [merkleFlagCountLength unsignedLongValue];
    
    NSMutableArray * merkleFlags = [NSMutableArray array];
    
    while (merkleFlagCount >= 1) {
        if (length - offset < 1) return;
        offset += 1;
        merkleFlagCount--;
    }
    
    DSCoinbaseTransaction *tx = (DSCoinbaseTransaction*)[DSTransactionFactory transactionWithMessage:[message subdataWithRange:NSMakeRange(offset, message.length - offset)] onChain:self.chain];
    if (![tx isMemberOfClass:[DSCoinbaseTransaction class]]) return;
    offset += tx.payloadOffset;
    
    if (length - offset < 1) return;
    NSNumber * deletedMasternodeCountLength;
    uint64_t deletedMasternodeCount = [message varIntAtOffset:offset length:&deletedMasternodeCountLength];
    offset += [deletedMasternodeCountLength unsignedLongValue];
    
    NSMutableArray * deletedMasternodeHashes = [NSMutableArray array];
    
    while (deletedMasternodeCount >= 1) {
        if (length - offset < 32) return;
        [deletedMasternodeHashes addObject:[NSData dataWithUInt256:[message UInt256AtOffset:offset]]];
        offset += 32;
        deletedMasternodeCount--;
    }
    
    if (length - offset < 1) return;
    NSNumber * addedMasternodeCountLength;
    uint64_t addedMasternodeCount = [message varIntAtOffset:offset length:&addedMasternodeCountLength];
    offset += [addedMasternodeCountLength unsignedLongValue];
    
    NSMutableArray * addedMasternodes = [NSMutableArray array];
    
    while (addedMasternodeCount >= 1) {
        if (length - offset < 91) return;
        NSData * data = [message subdataWithRange:NSMakeRange(offset, 91)];
        [addedMasternodes addObject:[DSSimplifiedMasternodeEntry simplifiedMasternodeEntryWithData:data]];
        offset += 91;
        addedMasternodeCount--;
    }
    
    
}

@end
