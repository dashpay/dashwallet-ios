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
#define NODE_NETWORK    1 // services value indicating a node offers full blocks, not just headers

#if BITCOIN_TESTNET
#define GENESIS_BLOCK_HASH @"000000000933ea01ad0ee984209779baaec3ced90fa3f408719526f8d77f4943".hexToData

// The testnet genesis block uses the mainnet genesis block's merkle root. The hash is wrong using it's own root.
#define GENESIS_BLOCK [[ZNMerkleBlock alloc] initWithBlockHash:[GENESIS_BLOCK_HASH reverse] version:1\
    prevBlock:@"0000000000000000000000000000000000000000000000000000000000000000".hexToData \
    merkleRoot:@"3ba3edfd7a7b12b27ac72c3e67768f617fC81bc3888a51323a9fb8aa4b1e5e4a".hexToData \
    timestamp:1296688602.0 - NSTimeIntervalSince1970 bits:0x1d00ffffu nonce:414098458u totalTransactions:1\
    hashes:@"3ba3edfd7a7b12b27ac72c3e67768f617fC81bc3888a51323a9fb8aa4b1e5e4a".hexToData flags:@"00".hexToData]

static const struct { uint32_t height; char *hash; } checkpoint_array[] = {};

static const char *dnsSeeds[] = { "testnet-seed.bitcoin.petertodd.org", "testnet-seed.bluematt.me" };

#else
#define GENESIS_BLOCK_HASH @"000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f".hexToData
#define GENESIS_BLOCK [[ZNMerkleBlock alloc] initWithBlockHash:[GENESIS_BLOCK_HASH reverse] version:1\
    prevBlock:@"0000000000000000000000000000000000000000000000000000000000000000".hexToData\
    merkleRoot:@"3ba3edfd7a7b12b27ac72c3e67768f617fC81bc3888a51323a9fb8aa4b1e5e4a".hexToData\
    timestamp:1231006505.0 - NSTimeIntervalSince1970 bits:0x1d00ffffu nonce:2083236893u totalTransactions:1\
    hashes:@"3ba3edfd7a7b12b27ac72c3e67768f617fC81bc3888a51323a9fb8aa4b1e5e4a".hexToData flags:@"00".hexToData]

// blockchain checkpoints
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
@property (nonatomic, assign) uint32_t tweak;
@property (nonatomic, strong) ZNBloomFilter *bloomFilter;
@property (nonatomic, assign) NSUInteger filterElemCount;
@property (nonatomic, assign) BOOL filterWasReset;
@property (nonatomic, strong) NSMutableDictionary *publishedTx, *publishedCallback;

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
    [ZNMerkleBlockEntity deleteObjects:[ZNMerkleBlockEntity allObjects]]; //for testing chain download
    
    if (! [ZNMerkleBlockEntity topBlock]) [ZNMerkleBlockEntity createOrUpdateWithBlock:GENESIS_BLOCK atHeight:0];

    self.tweak = mrand48();
    self.publishedTx = [NSMutableDictionary dictionary];
    self.publishedCallback = [NSMutableDictionary dictionary];
    
    for (ZNTransactionEntity *e in [ZNTransactionEntity objectsMatching:@"blockHeight == %d", TX_UNCONFIRMED]) {
        self.publishedTx[[e get:@"txHash"]] = [e transaction];
    }
    
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
        
        [[ZNPeerEntity context] performBlockAndWait:^{
            for (int j = 0; h->h_addr_list[j] != NULL; j++) {
                uint32_t addr = CFSwapInt32BigToHost(((struct in_addr *)h->h_addr_list[j])->s_addr);
                ZNPeerEntity *e = [ZNPeerEntity createOrUpdateWithPeer:[ZNPeer peerWithAddress:addr
                                                                        andPort:BITCOIN_STANDARD_PORT]];
            
                e.timestamp = now - 24*60*60*(3 + drand48()*4); // random timestamp between 3 and 7 days ago;
                e.services = NODE_NETWORK;
                count++;
            }
        }];
    }
    
#if BITCOIN_TESTNET
    return count;
#endif

    if (count > 0) return count;
    
    [[ZNPeerEntity context] performBlockAndWait:^{
        // if dns peer discovery fails, fall back on a hard coded list of peers
        // hard coded list is taken from the satoshi client, values need to be byte order swapped to be host native
        for (NSNumber *address in
             [NSArray arrayWithContentsOfFile:[[NSBundle mainBundle] pathForResource:FIXED_PEERS ofType:@"plist"]]) {
            uint32_t addr = CFSwapInt32(address.intValue);
            ZNPeerEntity *e = [ZNPeerEntity createOrUpdateWithPeer:[ZNPeer peerWithAddress:addr
                                                                    andPort:BITCOIN_STANDARD_PORT]];

            e.timestamp = now - 24*60*60*(7 + drand48()*7); // random timestamp between 7 and 14 days ago
            e.services = NODE_NETWORK;
            count++;
        }
    }];
    
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
    //TODO: XXXX for a wallet with fewer than 100 addresses, this creates a really low false positive rate... fix it
    if (_bloomFilter && _bloomFilter.falsePositiveRate > BLOOM_DEFAULT_FALSEPOSITIVE_RATE*2 &&
        _bloomFilter.elementCount > self.filterElemCount + 100) {
        _bloomFilter = nil;
        self.filterWasReset = YES;
    }

    if (_bloomFilter) return _bloomFilter;

    NSArray *addresses = [ZNAddressEntity allObjects];
    NSArray *utxos = [ZNTxOutputEntity objectsMatching:@"spent == NO"];

    // set the filter element count to the next largest multiple of 100, and use a fixed tweak to reduce the information
    // leaked to the remote peer when the filter is reset
    self.filterElemCount = (addresses.count + utxos.count + 100) - ((addresses.count + utxos.count) % 100);
    _bloomFilter = [ZNBloomFilter filterWithFalsePositiveRate:BLOOM_DEFAULT_FALSEPOSITIVE_RATE
                    forElementCount:self.filterElemCount tweak:self.tweak flags:BLOOM_UPDATE_P2PUBKEY_ONLY];
    
    [[ZNAddressEntity context] performBlockAndWait:^{
        for (ZNAddressEntity *e in addresses) {
            NSData *d = [e.address base58checkToData];
            
            // add the address hash160 to watch for any tx receiveing money to the wallet
            if (d.length == 160/8 + 1) [_bloomFilter insertData:[d subdataWithRange:NSMakeRange(1, d.length - 1)]];
        }
        
        for (ZNTxOutputEntity *e in utxos) {
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
    __block NSArray *a;

    [[ZNAddressEntity context] performBlockAndWait:^{
        a = [addresses valueForKey:@"address"];
    }];

    for (NSString *addr in a) {
        NSData *d = [addr base58checkToData];
        
        // add the address hash160 to watch for any tx receiveing money to the wallet
        if (d.length == 160/8 + 1) [self.bloomFilter insertData:[d subdataWithRange:NSMakeRange(1, d.length - 1)]];
    }

    for (ZNPeer *peer in self.peers) {
        [peer sendMessage:self.bloomFilter.data type:MSG_FILTERLOAD];
    }
}

- (void)publishTransaction:(ZNTransaction *)transaction completion:(void (^)(NSError *error))completion
{
    self.publishedTx[transaction.txHash] = transaction;
    self.publishedCallback[transaction.txHash] = completion;

    //TODO: XXXX setup a publish timeout

    for (ZNPeer *peer in self.peers) {
        [peer sendInvMessageWithTxHash:transaction.txHash];
    }
}

- (void)verifyTransaction:(ZNTransaction *)transaction completion:(void (^)(BOOL verified))completion;
{
    //TODO: XXXX send getdata and wait for a tx response
    if (completion) completion(YES);
}

- (void)peerMisbehavin:(ZNPeer *)peer
{
    //TODO: XXXX mark peer as misbehaving and disconnect
    //TODO: XXXX if for any reason you don't disconnect, reset _blockChain, _topBlock, _topBlockHeight
}

#pragma mark - ZNPeerDelegate

- (void)peerConnected:(ZNPeer *)peer
{
    [[ZNPeerEntity context] performBlock:^{
        _connected = YES;
        self.connectFailures = 0;
        NSLog(@"%@:%d connected", peer.host, peer.port);
    
        ZNPeerEntity *e = [ZNPeerEntity createOrUpdateWithPeer:peer];
        
        [e set:@"timestamp" to:[NSDate date]]; // set last seen timestamp for peer
        
        [peer sendMessage:self.bloomFilter.data type:MSG_FILTERLOAD];
        if ([ZNPeerEntity countAllObjects] <= 1000) [peer sendGetaddrMessage];

        uint32_t top = [ZNMerkleBlockEntity topBlock].height;

        //TODO: XXXX how does chain download work with relation to new wallet addresses being added? when a tx is found,
        // that address gets "used up" and we need to request the next address gap from the wallet somehow
        if (top < peer.lastblock) {
            NSFetchRequest *req = [ZNMerkleBlockEntity fetchRequest];
            int32_t step = 1, start = 0;
            NSMutableArray *heights = [NSMutableArray array];
        
            // append 10 most recent block hashes, decending, then continue appending, doubling the step back each time,
            // finishing with the genisis block (top, -1, -2, -3, -4, -5, -6, -7, -8, -9, -11, -15, -23, -39, -71, ...0)
            for (int32_t i = top; i > 0; i -= step, ++start) {
                if (start >= 10) step *= 2;
                
                [heights addObject:@(i)];
            }
            
            [heights addObject:@(0)];
            
            req.predicate = [NSPredicate predicateWithFormat:@"height in %@", heights];
            req.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"height" ascending:NO]];
            
            NSArray *blocks = [ZNMerkleBlockEntity fetchObjects:req];
            
            if (blocks.count > 0) {
                [peer sendGetheadersMessageWithLocators:[blocks valueForKey:@"blockHash"] andHashStop:nil];
            }
            else [peer sendGetheadersMessageWithLocators:@[[GENESIS_BLOCK_HASH reverse]] andHashStop:nil];
        }
        else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:walletSyncFinishedNotification object:nil];
            });
        }
    }];
}

- (void)peer:(ZNPeer *)peer disconnectedWithError:(NSError *)error
{
    [[ZNPeerEntity context] performBlock:^{
        [self.peers removeObject:peer];
        NSLog(@"%@:%d disconnected%@%@", peer.host, peer.port, error ? @", " : @"", error ? error : @"");

        //TODO: XXXX check for network reachability
        if (error) {
            [ZNPeerEntity deleteObjects:[ZNPeerEntity objectsMatching:@"address == %d && port == %d",
                                         (int32_t)peer.address, (int16_t)peer.port]];
        }

        if (! self.peers.count) {
            _connected = NO;
            self.connectFailures++;
        
//            if (self.connectFailures > 5) {
//                if (! error) {
//                    error = [NSError errorWithDomain:@"ZincWallet" code:0
//                             userInfo:@{NSLocalizedDescriptionKey:@"couldn't connect to bitcoin network"}];
//                }
//
//                dispatch_async(dispatch_get_main_queue(), ^{
//                    [[NSNotificationCenter defaultCenter] postNotificationName:walletSyncFailedNotification
//                     object:@{@"error":error}];
//                });
//                return;
//            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [self connect];
            });
        }
    }];
}

- (void)peer:(ZNPeer *)peer relayedPeers:(NSArray *)peers
{
    [[ZNPeerEntity context] performBlock:^{
        [ZNPeerEntity createOrUpdateWithPeers:peers];
    
        NSUInteger count = [ZNPeerEntity countAllObjects];
        NSFetchRequest *req = [ZNPeerEntity fetchRequest];
        
        if (count > 1000) { // remove peers with a timestamp more than 3 hours old, or until there are only 1000 left
            req.predicate = [NSPredicate predicateWithFormat:@"timestamp < %@",
                             [NSDate dateWithTimeIntervalSinceReferenceDate:[NSDate timeIntervalSinceReferenceDate] -
                              3*60*60]];
            req.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"timestamp" ascending:YES]];
            req.fetchLimit = count - 1000;
            [ZNPeerEntity deleteObjects:[ZNPeerEntity fetchObjects:req]];
            
            // limit total to 2500 peers
            [ZNPeerEntity deleteObjects:[ZNPeerEntity objectsSortedBy:@"timestamp" ascending:NO offset:2500 limit:0]];
        }
    }];
}

- (void)peer:(ZNPeer *)peer relayedTransaction:(ZNTransaction *)transaction
{
    [[ZNTransactionEntity context] performBlock:^{
        NSLog(@"%@:%d relayed transaction %@", peer.host, peer.port, transaction);

        NSMutableData *d = [NSMutableData data];
        
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
        
        if (! [[ZNWallet sharedInstance] registerTransaction:transaction]) return;
        
        ZNTransactionEntity *tx = [ZNTransactionEntity objectsMatching:@"txHash == %@", transaction.txHash].lastObject;
    
        if (tx) { // we already have the transaction, and now we also know that a bitcoin node is willing to relay it
                  //TODO: XXXX mark transaction as having been relayed
            return;
        }
    
        // if we're not downloading the chain, relay the tx to other peers so we have plausible deniability for our own
        //TODO: XXXX relay tx to other peers
    }];
}

- (void)peer:(ZNPeer *)peer relayedBlock:(ZNMerkleBlock *)block
{
    [[ZNMerkleBlockEntity context] performBlock:^{
        ZNMerkleBlockEntity *e = [ZNMerkleBlockEntity blockForHash:block.prevBlock];
        int32_t height = abs(e.height) + 1;
        NSTimeInterval transitionTime = 0;

        //TODO: XXX need to have some kind of timeout/retry if chain download stalls
        
        if (! e) { // block is either an orphan, or we haven't downloaded the whole chain yet
            // if the top block is just a header (totalTransactions == 0) that means we're still downloading the chain,
            // in which case we ignore the orphan block for now as it's probably in the chain we're already downloading
            if ([ZNMerkleBlockEntity topBlock].totalTransactions == 0) return;

            NSLog(@"%@:%d relayed orphan block, calling getblocks with last block", peer.host, peer.port);

            //TODO: this should use a full locator array so we don't dowload the entire chain if top block is on a fork
            [peer sendGetblocksMessageWithLocators:@[[ZNMerkleBlockEntity topBlock].blockHash]
             andHashStop:block.blockHash];
            return;
        }

        if ((height % BITCOIN_DIFFICULTY_INTERVAL) == 0) { // hit a difficulty transition, find last transition time
            while (abs(e.height) > height - BITCOIN_DIFFICULTY_INTERVAL) {
                e = [ZNMerkleBlockEntity blockForHash:e.prevBlock];
            }
        
            transitionTime = e.timestamp;
            e = [ZNMerkleBlockEntity blockForHash:block.prevBlock];
        }

        if (! [block verifyDifficultyAtHeight:height previous:e.merkleBlock transitionTime:transitionTime]) {
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
    
        e = [ZNMerkleBlockEntity blockForHash:block.blockHash];
    
        if (e) { // already have the block
            if ((height % 500) == 0) NSLog(@"%@:%d relayed existing block at height %d", peer.host, peer.port, height);
            
            [e setTreeFromBlock:block];
            
            if (e.height >= 0) { // and it's not on a fork
                [ZNTransactionEntity setBlockHeight:height forTxHashes:block.txHashes];
                [self.publishedTx removeObjectsForKeys:block.txHashes]; // remove confirmed tx from publish list
            }
            return;
        }
        else if ([ZNMerkleBlockEntity blockAtHeight:height] == nil) { // new block extends main chain
            // if the current top block is a header (totalTransactions == 0) that means we're still downloading the
            // chain, in which case we ignore new blocks we don't already have headers for so we don't get confused
            //TODO: BUG: XXXX the real problem is that checking if the top block is a header is just a bad way of
            // determining if we're downloading the chain
            if (block.totalTransactions > 0 && [ZNMerkleBlockEntity topBlock].totalTransactions == 0) return;
            
            if ((height % 500) == 0) NSLog(@"adding block at height: %d", height);
        
            [ZNMerkleBlockEntity createOrUpdateWithBlock:block atHeight:height];
            [ZNTransactionEntity setBlockHeight:height forTxHashes:block.txHashes];
            [self.publishedTx removeObjectsForKeys:block.txHashes]; // remove confirmed transactions from publish list
        }
        else { // new block is on a fork
            if (height <= BITCOIN_REFERENCE_BLOCK_HEIGHT) { // fork is older than the most recent checkpoint
                NSLog(@"%@:%d relayed a block that forks prior to the last checkpoint, fork height: %d, blockHash: %@",
                      peer.host, peer.port, height, block.blockHash);
                [self peerMisbehavin:peer];
                return;
            }
        
            NSLog(@"chain fork at height %d", height);
            
            e = [ZNMerkleBlockEntity createOrUpdateWithBlock:block atHeight:-height]; // negative height denotes a fork
        
            // if fork is shorter than main chain, ingore it for now
            if (height <= [ZNMerkleBlockEntity topBlock].height) return;

            // the fork is longer than the main chain, so make it the new main chain
            int32_t h = -height;
            
            while (h < 0) { // walk back to where the fork joins the old main chain
                e = [ZNMerkleBlockEntity blockForHash:e.prevBlock];
                h = e.height;
            }
    
            NSLog(@"reorganizing chain from height %d", h);
        
            // mark transactions after the join point as unconfirmed
            [ZNTransactionEntity setBlockHeight:TX_UNCONFIRMED
             forTxHashes:[[ZNTransactionEntity objectsMatching:@"blockHeight > %d", h] valueForKey:@"txHash"]];
        
            // set old main chain heights to negative to denote they are now a fork
            for (e in [ZNMerkleBlockEntity objectsMatching:@"height > %d", h]) {
                e.height *= -1;
            }
            
            e = [ZNMerkleBlockEntity blockForHash:block.blockHash];
            
            while (e.height < 0) { // set block heights for new main chain and mark its transactions as confirmed
                e.height *= -1;
                [ZNTransactionEntity setBlockHeight:e.height forTxHashes:e.merkleBlock.txHashes];
                [self.publishedTx removeObjectsForKeys:e.merkleBlock.txHashes]; // remove confirmed tx from publish list
                e = [ZNMerkleBlockEntity blockForHash:e.prevBlock];
            }

            // re-publish any transactions that may have become unconfirmed
            for (ZNTransactionEntity *tx in [ZNTransactionEntity objectsMatching:@"blockHeight == %d", TX_UNCONFIRMED]){
                [self publishTransaction:tx.transaction completion:nil];
            }
                
            NSLog(@"new chain height %d", height);
        }
    
        // after downloading the block headers, get the transactions for the blocks newer than earliestBlockHeight
        if (block.totalTransactions == 0 && height == peer.lastblock) { // totalTransactions is 0 if it's a block header
            NSMutableArray *locators = [NSMutableArray array];
    
            e = [ZNMerkleBlockEntity blockForHash:block.blockHash];

            // find the previous non-header, or earliestBlockHeight
            while (e.totalTransactions == 0 && e.height > self.earliestBlockHeight) {
                e = [ZNMerkleBlockEntity blockForHash:e.prevBlock];
            }
    
            if (e) [locators addObject:e.blockHash];
            if (e.height > 0) [locators addObject:[GENESIS_BLOCK_HASH reverse]];
    
            [peer sendGetblocksMessageWithLocators:locators andHashStop:nil];
        }
    }];
}

- (ZNTransaction *)peer:(ZNPeer *)peer requestedTransaction:(NSData *)txHash
{
    ZNTransaction *tx = self.publishedTx[txHash];
    void (^callback)(NSError *error) = self.publishedCallback[txHash];
    
    if (tx) {
        [self.publishedCallback removeObjectForKey:txHash];
        //TODO: XXXX cancel callback timeout
        if (callback) callback(nil);
        return tx;
    }
    
    return [[ZNTransactionEntity objectsMatching:@"txHash == %@ && blockHeight == %d", txHash,
             TX_UNCONFIRMED].lastObject transaction];
}

@end
