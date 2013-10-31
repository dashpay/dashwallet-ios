//
//  ZNBitcoin.m
//  ZincWallet
//
//  Created by Aaron Voisine on 10/6/13.
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

#import "ZNPeerManager.h"
#import "ZNPeer.h"
#import "ZNPeerEntity.h"
#import "ZNBloomFilter.h"
#import "ZNTransaction.h"
#import "ZNTransactionEntity.h"
#import "ZNTxOutputEntity.h"
#import "ZNUnspentOutputEntity.h"
#import "ZNMerkleBlock.h"
#import "ZNMerkleBlockEntity.h"
#import "ZNAddressEntity.h"
#import "ZNWallet.h"
#import "NSString+Base58.h"
#import "NSMutableData+Bitcoin.h"
#import "NSData+Hash.h"
#import "NSManagedObject+Utils.h"
#import <netdb.h>
#import <arpa/inet.h>

#define FIXED_PEERS     @"FixedPeers"
#define MAX_CONNECTIONS 3

#if BITCOIN_TESTNET
// The testnet genesis block uses the mainnet genesis block's merkle root. The hash is wrong using it's own root.
#define GENESIS_BLOCK [[ZNMerkleBlock alloc] \
    initWithBlockHash:[@"000000000933ea01ad0ee984209779baaec3ced90fa3f408719526f8d77f4943".hexToData reverse] version:1\
    prevBlock:@"0000000000000000000000000000000000000000000000000000000000000000".hexToData \
    merkleRoot:@"3ba3edfd7a7b12b27ac72c3e67768f617fC81bc3888a51323a9fb8aa4b1e5e4a".hexToData \
    timestamp:1296688602.0 - NSTimeIntervalSince1970 bits:0x1d00ffffu nonce:414098458u totalTransactions:1\
    hashes:@"3ba3edfd7a7b12b27ac72c3e67768f617fC81bc3888a51323a9fb8aa4b1e5e4a".hexToData flags:@"00".hexToData]

static const struct { uint32_t height; char *hash; } checkpoint_array[] = {};

static const char *dnsSeeds[] = { "testnet-seed.bitcoin.petertodd.org", "testnet-seed.bluematt.me" };

#else
#define GENESIS_BLOCK [[ZNMerkleBlock alloc] \
    initWithBlockHash:[@"000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f".hexToData reverse] version:1\
    prevBlock:@"0000000000000000000000000000000000000000000000000000000000000000".hexToData\
    merkleRoot:@"3ba3edfd7a7b12b27ac72c3e67768f617fC81bc3888a51323a9fb8aa4b1e5e4a".hexToData\
    timestamp:1231006505.0 - NSTimeIntervalSince1970 bits:0x1d00ffffu nonce:2083236893u totalTransactions:1\
    hashes:@"3ba3edfd7a7b12b27ac72c3e67768f617fC81bc3888a51323a9fb8aa4b1e5e4a".hexToData flags:@"00".hexToData]

static const struct { uint32_t height; char *hash; } checkpoint_array[] = {
    { 11111, "0000000069e244f73d78e8fd29ba2fd2ed618bd6fa2ee92559f542fdb26e7c1d" },
    { 33333, "000000002dd5588a74784eaa7ab0507a18ad16a236e7b1ce69f00d7ddfb5d0a6" },
    { 74000, "0000000000573993a3c9e41ce34471c079dcf5f52a0e824a81e7f953b8661a20" },
    { 105000, "00000000000291ce28027faea320c8d2b054b2e0fe44a773f3eefb151d6bdc97" },
    { 134444, "00000000000005b12ffd4cd315cd34ffd4a594f430ac814c91184a0d42d2b0fe" },
    { 168000, "000000000000099e61ea72015e79632f216fe6cb33d7899acb35b75c8303b763" },
    { 193000, "000000000000059f452a5f7340de6682a977387c17010ff6e6c3bd83ca8b1317" },
    { 210000, "000000000000048b95347e83192f69cf0366076336c639f9b7228e9ba171342e" },
    { 216116, "00000000000001b4f4b433e81ee46494af945cf96014816a4e2370f11b23df4e" },
    { 225430, "00000000000001c108384350f74090433e7fcf79a606b8e797f065b130575932" },
    { 250000, "000000000000003887df1f29024b06fc2200b55f8af8f35453d7be294df2d214" },
};

static const char *dnsSeeds[] = {
    "seed.bitcoin.sipa.be", "dnsseed.bluematt.me", "dnsseed.bitcoin.dashjr.org", "bitseed.xf2.org"
};

#endif

static NSMutableDictionary *checkpoints;

@interface ZNPeerManager ()

@property (nonatomic, strong) NSMutableArray *peers;
@property (nonatomic, assign) int connectFailures;
@property (nonatomic, strong) ZNMerkleBlock *topBlock;
@property (nonatomic, assign) int32_t topBlockHeight;
@property (nonatomic, assign) NSTimeInterval transitionTime; // timestamp of last difficulty transition
@property (nonatomic, assign) uint32_t tweak;
@property (nonatomic, strong) ZNBloomFilter *bloomFilter;
@property (nonatomic, assign) NSUInteger filterElemCount;
@property (nonatomic, assign) BOOL filterWasReset;

@end

@implementation ZNPeerManager

+ (instancetype)sharedInstance
{
    static id singleton = nil;
    static dispatch_once_t onceToken = 0;
    
#if ! SPV_MODE
    return nil;
#endif
    
    dispatch_once(&onceToken, ^{
        srand48(time(NULL)); // seed psudo random number generator (for non-cryptographic use only!)
        
        checkpoints = [NSMutableDictionary dictionary]; // blockchain checkpoints

        for (int i = 0; i < sizeof(checkpoint_array)/sizeof(*checkpoint_array); i++) {
            checkpoints[@(checkpoint_array[i].height)] =
                [[NSString stringWithUTF8String:checkpoint_array[i].hash].hexToData reverse];
        }

        singleton = [self new];
    });
    
    return singleton;
}

- (instancetype)init
{
    if (! (self = [super init])) return nil;

    self.earliestBlockHeight = BITCOIN_REFERENCE_BLOCK_HEIGHT;
    self.peers = [NSMutableArray array];
    
#warning remove this!
    [ZNMerkleBlockEntity deleteObjects:[ZNMerkleBlockEntity allObjects]]; //XXXX <--- this right here, YES THIS!
    
    ZNMerkleBlockEntity *e = [ZNMerkleBlockEntity objectsSortedBy:@"height" ascending:NO offset:0 limit:1].lastObject;

    if (! e || [[e get:@"height"] intValue] < 0) {
        e = [ZNMerkleBlockEntity createOrUpdateWithMerkleBlock:GENESIS_BLOCK atHeight:0];
    }

    self.topBlockHeight = [[e get:@"height"] intValue];
    self.topBlock = [e merkleBlock];
    e = [ZNMerkleBlockEntity objectsMatching:@"height == %d",
         self.topBlockHeight - (self.topBlockHeight % BITCOIN_DIFFICULTY_INTERVAL)].lastObject;
    if (e) self.transitionTime = [[e get:@"timestamp"] timeIntervalSinceReferenceDate];
    
    self.tweak = mrand48();
    
    //TODO: monitor network reachability and reconnect whenever connection becomes available
    //TODO: disconnect peers when app is backgrounded unless we're syncing or launching mobile web app tx handler
    
    return self;
}

- (NSUInteger)discoverPeers
{
    __block NSUInteger count = 0;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];

    for (int i = 0; i < sizeof(dnsSeeds)/sizeof(*dnsSeeds); i++) { // DNS peer discovery
        struct hostent *h = gethostbyname(dnsSeeds[i]);
        
        for (int j = 0; h->h_addr_list[j] != NULL; j++) {
            uint32_t addr = CFSwapInt32BigToHost(((struct in_addr *)h->h_addr_list[j])->s_addr);
            NSTimeInterval t = now - 24*60*60*(3 + drand48()*4); // random timestamp between 3 and 7 days ago
            
            [ZNPeerEntity createOrUpdateWithAddress:addr port:BITCOIN_STANDARD_PORT timestamp:t services:NODE_NETWORK];
            count++;
        }
    }
    
#if ! BITCOIN_TESTNET
    if (count > 0) return count;
     
    // if dns peer discovery fails, fall back on a hard coded list of peers
    // hard coded list is taken from the satoshi client, values need to be byte order swapped to be host native
    for (NSNumber *address in
         [NSArray arrayWithContentsOfFile:[[NSBundle mainBundle] pathForResource:FIXED_PEERS ofType:@"plist"]]) {
        uint32_t addr = CFSwapInt32(address.intValue);
        NSTimeInterval t = now - 24*60*60*(7 + drand48()*7); // random timestamp between 7 and 14 days ago
        
        [ZNPeerEntity createOrUpdateWithAddress:addr port:BITCOIN_STANDARD_PORT timestamp:t services:NODE_NETWORK];
        count++;
    }
#endif
    
    return count;
}

- (ZNPeerEntity *)randomPeer
{
    NSUInteger count = [ZNPeerEntity countAllObjects], offset = 0;
    
    if (count == 0) count += [self discoverPeers];
    if (count > 100) count = 100;
    if (count == 0) return nil;

    offset = pow(lrand48() % count, 2)/count; // pick a random peer biased for peers with more recent timestamps
    
    NSLog(@"picking peer %lu out of %lu most recent", (unsigned long)offset, (unsigned long)count);
    
    return [ZNPeerEntity objectsSortedBy:@"timestamp" ascending:NO offset:offset limit:1].lastObject;
}

- (void)connect
{
    if (self.peers.count > 0 && [self.peers[0] status] != disconnected) return;

    ZNPeerEntity *e = [self randomPeer];
    __block ZNPeer *peer = nil;
    
    if (! e) {
        [[NSNotificationCenter defaultCenter] postNotificationName:walletSyncFailedNotification
         object:@{@"error":[NSError errorWithDomain:@"ZincWallet" code:1
                            userInfo:@{NSLocalizedDescriptionKey:@"no peers found"}]}];
        return;
    }
    
    [e.managedObjectContext performBlockAndWait:^{
        peer = [ZNPeer peerWithAddress:e.address andPort:e.port];
    }];
    
    peer.delegate = self;
    [self.peers removeAllObjects]; //TODO: XXXX connect to multiple peers
    if (peer) [self.peers addObject:peer];

    [peer connect];
}

- (ZNBloomFilter *)bloomFilter
{
    // A bloom filter's falsepositive rate will increase with each item added to the filter. If the filter has degraded
    // by half and we've added at least 100 items to it, clear it and build a new one
    if (_bloomFilter && _bloomFilter.falsePositiveRate > BLOOM_DEFAULT_FALSEPOSITIVE_RATE*2 &&
        _bloomFilter.elementCount > self.filterElemCount + 100) {
        _bloomFilter = nil;
        self.filterWasReset = YES;
    }

    if (_bloomFilter) return _bloomFilter;

    NSArray *addresses = [ZNAddressEntity allObjects];
    NSArray *utxos = [ZNUnspentOutputEntity allObjects];

    // set the filter element count to the next largest multiple of 100, and use a fixed tweak to reduce the information
    // leaked to the remote peer when the filter is reset
    self.filterElemCount = (addresses.count + utxos.count + 100) - ((addresses.count + utxos.count) % 100);
    _bloomFilter = [ZNBloomFilter filterWithFalsePositiveRate:BLOOM_DEFAULT_FALSEPOSITIVE_RATE
                    forElementCount:self.filterElemCount tweak:self.tweak flags:BLOOM_UPDATE_P2PUBKEY_ONLY];
    
    [[addresses.lastObject managedObjectContext] performBlockAndWait:^{
        for (ZNAddressEntity *e in addresses) {
            NSData *d = [e.address base58checkToData];
            
            // add the address hash160 to watch for any tx receiveing money to the wallet
            if (d.length == 160/8 + 1) [_bloomFilter insertData:[d subdataWithRange:NSMakeRange(1, d.length - 1)]];
        }
        
        for (ZNUnspentOutputEntity *e in utxos) {
            NSMutableData *d = [NSMutableData data];
            
            [d appendData:e.txHash];
            [d appendUInt32:e.n];
            [_bloomFilter insertData:d]; // add the unspent output to watch for any tx sending money from the wallet
        }
        
        //TODO: after a wallet restore and chain download, reset all non-download peer's filters with new utxo's
    }];
    
    return _bloomFilter;
}

// this will extend the bloom filter to include transactions sent to the given addresses
- (void)subscribeToAddresses:(NSArray *)addresses
{
    [[addresses.lastObject managedObjectContext] performBlockAndWait:^{
        for (ZNAddressEntity *e in addresses) {
            NSData *d = [e.address base58checkToData];
        
            // add the address hash160 to watch for any tx receiveing money to the wallet
            if (d.length == 160/8 + 1) [self.bloomFilter insertData:[d subdataWithRange:NSMakeRange(1, d.length - 1)]];
        }
    }];

    for (ZNPeer *peer in self.peers) {
        [peer sendMessage:self.bloomFilter.data type:MSG_FILTERLOAD];
    }
}

- (void)peerMisbehavin:(ZNPeer *)peer
{
    //TODO: XXXX mark peer as misbehaving and disconnect
}

#pragma mark - ZNPeerDelegate

- (void)peerConnected:(ZNPeer *)peer
{
    _connected = YES;
    self.connectFailures = 0;
    NSLog(@"%@:%d connected", peer.host, peer.port);
    
    [[NSNotificationCenter defaultCenter] postNotificationName:walletSyncFinishedNotification object:nil];
    
    [peer sendMessage:self.bloomFilter.data type:MSG_FILTERLOAD];
    if ([ZNPeerEntity countAllObjects] <= 1000) [peer sendGetaddrMessage];
    if (self.topBlockHeight < peer.lastblock) [peer sendGetblocksMessage];
}

- (void)peer:(ZNPeer *)peer disconnectedWithError:(NSError *)error
{
    [self.peers removeObject:peer];
    NSLog(@"%@:%d disconnected%@%@", peer.host, peer.port, error ? @", " : @"", error ? error : @"");

    //TODO: XXXX check for network reachability
    if (error) {
        [ZNPeerEntity deleteObjects:[ZNPeerEntity objectsMatching:@"address == %u && port == %u", peer.address,
                                     peer.port]];
    }

    if (! self.peers.count) {
        _connected = NO;
        self.connectFailures++;
        
//        if (self.connectFailures > 5) {
//            if (! error) {
//                error = [NSError errorWithDomain:@"ZincWallet" code:0
//                         userInfo:@{NSLocalizedDescriptionKey:@"couldn't connect to bitcoin network"}];
//            }
//            
//            [[NSNotificationCenter defaultCenter] postNotificationName:walletSyncFailedNotification
//             object:@{@"error":error}];
//            return;
//        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self connect];
        });
    }
}

- (void)peer:(ZNPeer *)peer relayedTransaction:(ZNTransaction *)transaction
{
    ZNTransactionEntity *tx = [ZNTransactionEntity objectsMatching:@"txHash == %@", transaction.txHash].lastObject;
    __block NSUInteger idx = 0;
    __block BOOL valid = YES;
    NSMutableData *d = [NSMutableData data];
    
    if (tx) { // we already have the transaction, and now we also know that a bitcoin node is willing to relay it
        [self peerMisbehavin:peer];
        return;
    }

    // relayed transactions don't contain input scripts, input scripts must be obtained from previous tx outputs
    [[ZNTransactionEntity context] performBlockAndWait:^{
        for (NSData *hash in transaction.inputHashes) { // lookup input addresses
            uint32_t n = [transaction.inputIndexes[idx++] unsignedIntValue];
            ZNTransactionEntity *e = [ZNTransactionEntity objectsMatching:@"txHash == %@", hash].lastObject;
        
            if (! e) continue; // if the input tx is missing, then that input tx didn't involve wallet addresses
        
            if (n > e.outputs.count) {
                NSLog(@"invalid transaction, input %u has non-existant previous output index", (int)idx - 1);
                valid = NO;
                return;
            }
        
            //TODO: refactor to use actual previous output script instead of generating a standard one from the address
            [transaction setInputAddress:[(ZNTxOutputEntity *)e.outputs[n] address] atIndex:idx - 1];
        }
    }];
    
    for (uint32_t n = 0; n < transaction.outputAddresses.count; n++) {
        [d setData:transaction.txHash];
        [d appendUInt32:n];
        [self.bloomFilter insertData:d]; // update bloomFilter with each txout
    }
    
    if (self.filterWasReset) { // filter got reset, send the new one to all the peers
        self.filterWasReset = NO;
        
        for (ZNPeer *peer in self.peers) {
            [peer sendMessage:self.bloomFilter.data type:MSG_FILTERLOAD];
        }
    }
    
    if (valid) [[ZNWallet sharedInstance] registerTransaction:transaction]; // this will ignore any non-wallet tx
}

- (void)peer:(ZNPeer *)peer relayedBlock:(ZNMerkleBlock *)block
{
    int32_t height = self.topBlockHeight + 1;
    ZNMerkleBlock *prev = self.topBlock;
    NSTimeInterval transitionTime = self.transitionTime;
    
    if (! [block.prevBlock isEqual:prev.blockHash]) { // find previous block for difficulty verification
        ZNMerkleBlockEntity *e = [ZNMerkleBlockEntity objectsMatching:@"blockHash == %@", block.prevBlock].lastObject;
        
        if (! e) { // block is either an orphan, or we haven't downloaded the whole chain yet
            //[peer sendGetblocksMessage]; // continue chain download
            return;
        }
        
        height = abs([[e get:@"height"] intValue]) + 1;
        prev = [e merkleBlock];
        
        if ((height % BITCOIN_DIFFICULTY_INTERVAL) == 0) { // hit a difficulty transition, find the last transition time
            int32_t h = [[e get:@"height"] intValue];

            // if we're on a fork, walk back to main chain or previous transition on this fork
            while (h < 0 && abs(h) > height - BITCOIN_DIFFICULTY_INTERVAL) { // we use negative height to denote forks
                e = [ZNMerkleBlockEntity objectsMatching:@"blockHash == %@", e.prevBlock].lastObject;
                h = [[e get:@"height"] intValue];
            }
        
            if (h >= 0) { // once we're back on the main chain, we can jump straight to the previous transition
                transitionTime = [[[ZNMerkleBlockEntity objectsMatching:@"height == %d",
                                    height - BITCOIN_DIFFICULTY_INTERVAL].lastObject get:@"timestamp"] doubleValue];
            }
            else transitionTime = [[e get:@"timestamp"] doubleValue]; // previous transition was on the fork as well
            //NOTE: a fork longer than 2016 blocks probably means an attempted 51% attack
        }
    }

    if (! [block verifyDifficultyAtHeight:height previous:prev transitionTime:transitionTime]) { // verify difficulty
        NSLog(@"%@:%d relayed block with invalid difficulty target %x, blockHash: %@", peer.host, peer.port,
              block.bits, block.blockHash);
        [self peerMisbehavin:peer];
        return;
    }
    
    if (checkpoints[@(height)] && ! [block.blockHash isEqual:checkpoints[@(height)]]) { // verify checkpoints
        NSLog(@"%@:%d relayed a block that differs from the checkpoint at height %d, blockHash: %@, expected: %@",
              peer.host, peer.port, height, block.blockHash, checkpoints[@(height)]);
        [self peerMisbehavin:peer];
        return;
    }

    if (prev == self.topBlock) { // block extends main chain
        NSLog(@"adding block at height: %d", height);
        [ZNMerkleBlockEntity createOrUpdateWithMerkleBlock:block atHeight:height];
        
        self.topBlock = block;
        self.topBlockHeight = height;
        if ((height % BITCOIN_DIFFICULTY_INTERVAL) == 0) self.transitionTime = block.timestamp;
        
        NSArray *txHashes = block.txHashes;
        
        if (txHashes.count > 0) {
            for (ZNTransactionEntity *tx in [ZNTransactionEntity objectsMatching:@"txHash IN %@", txHashes]) {
                [tx set:@"blockHeight" to:@(height)]; // mark transactions in the new block as having a confirmation
            }
        }
        return;
    }
    
    if ([ZNMerkleBlockEntity countObjectsMatching:@"blockHash == %@", block.blockHash] > 0) { // already have the block
        [ZNMerkleBlockEntity updateTreeFromMerkleBlock:block]; // update merkle tree with any new matched transactions

        for (ZNTransactionEntity *tx in [ZNTransactionEntity objectsMatching:@"txHash IN %@", block.txHashes]) {
            [tx set:@"blockHeight" to:@(height)]; // mark transactions in the new block as having a confirmation
        }
        return;
    }

    if (height <= BITCOIN_REFERENCE_BLOCK_HEIGHT) { // fork is older than the most recent checkpoint
        NSLog(@"%@:%d relayed a block that forks prior to the last checkpoint, fork height: %d, blockHash: %@",
              peer.host, peer.port, height, block.blockHash);
        [self peerMisbehavin:peer];
        return;
    }

    // use negative height to denote we're on a fork
    __block ZNMerkleBlockEntity *b = [ZNMerkleBlockEntity createOrUpdateWithMerkleBlock:block atHeight:-height], *e;

    if (height <= self.topBlockHeight) return; // fork is shorter than main chain, so ingore it for now

    // the fork is longer than the main chain, so make it the new main chain
    [[ZNMerkleBlockEntity context] performBlockAndWait:^{
        int32_t h = -height;
    
        while (h < 0) { // walk back to where the fork joins the old main chain
            e = [ZNMerkleBlockEntity objectsMatching:@"blockHash == %@", e.prevBlock].lastObject;
            h = e.height;
        }
        
        for (ZNTransactionEntity *tx in [ZNTransactionEntity objectsMatching:@"blockHeight > %d", h]) {
            tx.blockHeight = 0; // mark transactions after the join point as unconfirmed
        }
        
        for (e in [ZNMerkleBlockEntity objectsMatching:@"height > %d", h]) {
            e.height = -e.height; // set old main chain heights to negative to denote a fork
        }
        
        while (b.height < 0) {
            b.height = -b.height;

            for (ZNTransactionEntity *tx in
                 [ZNTransactionEntity objectsMatching:@"txHash IN %@", b.merkleBlock.txHashes]) {
                tx.blockHeight = b.height; // mark transactions in new main chain as confirmed
            }
            
            b = [ZNMerkleBlockEntity objectsMatching:@"blockHash == %@", b.prevBlock].lastObject;
        }
        
        self.topBlock = block;
        self.topBlockHeight = height;
        if ((height % BITCOIN_DIFFICULTY_INTERVAL) == 0) self.transitionTime = block.timestamp;
    }];
}

@end
