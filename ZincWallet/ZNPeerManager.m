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
#import "ZNKeySequence.h"
#import "ZNTransaction.h"
#import "ZNMerkleBlock.h"
#import "ZNMerkleBlockEntity.h"
#import "ZNWalletManager.h"
#import "ZNWallet.h"
#import "NSString+Base58.h"
#import "NSData+Hash.h"
#import "NSManagedObject+Utils.h"
#import <netdb.h>

#define FIXED_PEERS           @"FixedPeers"
#define MAX_CONNECTIONS       3
#define NODE_NETWORK          1 // services value indicating a node offers full blocks, not just headers
#define PROTOCOL_TIMEOUT      15.0
#define MAX_CONNENCT_FAILURES 20 // notify user of network problems after this many connect failures in a row

#if BITCOIN_TESTNET

#define GENESIS_BLOCK_HASH @"000000000933ea01ad0ee984209779baaec3ced90fa3f408719526f8d77f4943".hexToData.reverse

// The testnet genesis block uses the mainnet genesis block's merkle root. The hash is wrong using its own root.
#define GENESIS_BLOCK [[ZNMerkleBlock alloc] initWithBlockHash:GENESIS_BLOCK_HASH version:1\
    prevBlock:@"0000000000000000000000000000000000000000000000000000000000000000".hexToData\
    merkleRoot:@"3ba3edfd7a7b12b27ac72c3e67768f617fC81bc3888a51323a9fb8aa4b1e5e4a".hexToData\
    timestamp:1296688602.0 - NSTimeIntervalSince1970 target:0x1d00ffffu nonce:414098458u totalTransactions:1\
    hashes:@"3ba3edfd7a7b12b27ac72c3e67768f617fC81bc3888a51323a9fb8aa4b1e5e4a".hexToData flags:@"00".hexToData height:0]

static const struct { uint32_t height; char *hash; time_t timestamp; uint32_t target; } checkpoint_array[] = {
    {  20160, "000000001cf5440e7c9ae69f655759b17a32aad141896defd55bb895b7cfc44e", 1345001466, 0x1c4d1756u },
    {  40320, "000000008011f56b8c92ff27fb502df5723171c5374673670ef0eee3696aee6d", 1355980158, 0x1d00ffffu },
    {  60480, "00000000130f90cda6a43048a58788c0a5c75fa3c32d38f788458eb8f6952cee", 1363746033, 0x1c1eca8au },
    {  80640, "00000000002d0a8b51a9c028918db3068f976e3373d586f08201a4449619731c", 1369042673, 0x1c011c48u },
    { 100800, "0000000000a33112f86f3f7b0aa590cb4949b84c2d9c673e9e303257b3be9000", 1376543922, 0x1c00d907u },
    { 120960, "00000000003367e56e7f08fdd13b85bbb31c5bace2f8ca2b0000904d84960d0c", 1382025703, 0x1c00df4cu },
    { 141120, "0000000007da2f551c3acd00e34cc389a4c6b6b3fad0e4e67907ad4c7ed6ab9f", 1384495076, 0x1c0ffff0u },
    { 161280, "0000000001d1b79a1aec5702aaa39bad593980dfe26799697085206ef9513486", 1388980370, 0x1c03fffcu },
    { 181440, "00000000002bb4563a0ec21dc4136b37dcd1b9d577a75a695c8dd0b861e1307e", 1392304311, 0x1b336ce6u },
    { 201600, "0000000000376bb71314321c45de3015fe958543afcbada242a3b1b072498e38", 1393813869, 0x1b602ac0u }
};

static const char *dns_seeds[] = { "testnet-seed.bitcoin.petertodd.org", "testnet-seed.bluematt.me" };

#else // main net

#define GENESIS_BLOCK_HASH @"000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f".hexToData.reverse

#define GENESIS_BLOCK [[ZNMerkleBlock alloc] initWithBlockHash:GENESIS_BLOCK_HASH version:1\
    prevBlock:@"0000000000000000000000000000000000000000000000000000000000000000".hexToData\
    merkleRoot:@"3ba3edfd7a7b12b27ac72c3e67768f617fC81bc3888a51323a9fb8aa4b1e5e4a".hexToData\
    timestamp:1231006505.0 - NSTimeIntervalSince1970 target:0x1d00ffffu nonce:2083236893u totalTransactions:1\
    hashes:@"3ba3edfd7a7b12b27ac72c3e67768f617fC81bc3888a51323a9fb8aa4b1e5e4a".hexToData flags:@"00".hexToData height:0]

// blockchain checkpoints, these are also used as starting points for partial chain downloads, so they need to be at
// difficulty transition boundaries in order to verify the block difficulty at the immediately following transition
static const struct { uint32_t height; char *hash; time_t timestamp; uint32_t target; } checkpoint_array[] = {
    {  20160, "000000000f1aef56190aee63d33a373e6487132d522ff4cd98ccfc96566d461e", 1248481816, 0x1d00ffffu },
    {  40320, "0000000045861e169b5a961b7034f8de9e98022e7a39100dde3ae3ea240d7245", 1266191579, 0x1c654657u },
    {  60480, "000000000632e22ce73ed38f46d5b408ff1cff2cc9e10daaf437dfd655153837", 1276298786, 0x1c0eba64u },
    {  80640, "0000000000307c80b87edf9f6a0697e2f01db67e518c8a4d6065d1d859a3a659", 1284861847, 0x1b4766edu },
    { 100800, "000000000000e383d43cc471c64a9a4a46794026989ef4ff9611d5acb704e47a", 1294031411, 0x1b0404cbu },
    { 120960, "0000000000002c920cf7e4406b969ae9c807b5c4f271f490ca3de1b0770836fc", 1304131980, 0x1b0098fau },
    { 141120, "00000000000002d214e1af085eda0a780a8446698ab5c0128b6392e189886114", 1313451894, 0x1a094a86u },
    { 161280, "00000000000005911fe26209de7ff510a8306475b75ceffd434b68dc31943b99", 1326047176, 0x1a0d69d7u },
    { 181440, "00000000000000e527fc19df0992d58c12b98ef5a17544696bbba67812ef0e64", 1337883029, 0x1a0a8b5fu },
    { 201600, "00000000000003a5e28bef30ad31f1f9be706e91ae9dda54179a95c9f9cd9ad0", 1349226660, 0x1a057e08u },
    { 221760, "00000000000000fc85dd77ea5ed6020f9e333589392560b40908d3264bd1f401", 1361148470, 0x1a04985cu },
    { 241920, "00000000000000b79f259ad14635739aaf0cc48875874b6aeecc7308267b50fa", 1371418654, 0x1a00de15u },
    { 262080, "000000000000000aa77be1c33deac6b8d3b7b0757d02ce72fffddc768235d0e2", 1381070552, 0x1916b0cau },
    { 282240, "0000000000000000ef9ee7529607286669763763e0c46acfdefd8a2306de5ca8", 1390570126, 0x1901f52cu }
};

static const char *dns_seeds[] = {
    "seed.bitcoin.sipa.be", "dnsseed.bluematt.me", "dnsseed.bitcoin.dashjr.org", "bitseed.xf2.org"
};

#endif

@interface ZNPeerManager ()

@property (nonatomic, strong) NSMutableOrderedSet *peers;
@property (nonatomic, strong) NSMutableSet *connectedPeers, *misbehavinPeers;
@property (nonatomic, strong) ZNPeer *downloadPeer;
@property (nonatomic, assign) uint32_t tweak, syncStartHeight;
@property (nonatomic, strong) ZNBloomFilter *bloomFilter;
@property (nonatomic, assign) NSUInteger taskId, connectFailures;
@property (nonatomic, assign) BOOL filterWasReset;
@property (nonatomic, assign) NSTimeInterval earliestKeyTime, lastRelayTime;
@property (nonatomic, strong) NSMutableDictionary *blocks, *orphans, *checkpoints, *publishedTx, *publishedCallback;
@property (nonatomic, strong) ZNMerkleBlock *lastBlock, *lastOrphan;
@property (nonatomic, strong) NSCountedSet *txRelayCounts;
@property (nonatomic, strong) dispatch_queue_t q;
@property (nonatomic, strong) id activeObserver, seedObserver;

@end

@implementation ZNPeerManager

+ (instancetype)sharedInstance
{
    static id singleton = nil;
    static dispatch_once_t onceToken = 0;
    
    dispatch_once(&onceToken, ^{
        srand48(time(NULL)); // seed psudo random number generator (for non-cryptographic use only!)
        singleton = [self new];
    });
    
    return singleton;
}

- (instancetype)init
{
    if (! (self = [super init])) return nil;

    self.earliestKeyTime = [[ZNWalletManager sharedInstance] seedCreationTime];
    self.connectedPeers = [NSMutableSet set];
    self.misbehavinPeers = [NSMutableSet set];
    self.tweak = mrand48();
    self.taskId = UIBackgroundTaskInvalid;
    self.q = dispatch_queue_create("cc.zinc.peermanager", NULL);
    self.txRelayCounts = [NSCountedSet set];
    self.orphans = [NSMutableDictionary dictionary];
    self.publishedTx = [NSMutableDictionary dictionary];
    self.publishedCallback = [NSMutableDictionary dictionary];

    for (ZNTransaction *tx in [[[ZNWalletManager sharedInstance] wallet] recentTransactions]) {
        if (tx.blockHeight != TX_UNCONFIRMED) break;
        self.publishedTx[tx.txHash] = tx; // add unconfirmed tx to mempool
    }

    self.activeObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillResignActiveNotification object:nil
        queue:nil usingBlock:^(NSNotification *note) {
            [self savePeers];
            [self saveBlocks];
            [ZNMerkleBlockEntity saveContext];
            if (self.syncProgress >= 1.0) [self.peers.array makeObjectsPerformSelector:@selector(disconnect)];
        }];

    self.seedObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:ZNWalletManagerSeedChangedNotification object:nil
        queue:nil usingBlock:^(NSNotification *note) {
            self.earliestKeyTime = [[ZNWalletManager sharedInstance] seedCreationTime];
            [self.txRelayCounts removeAllObjects];
            [self.orphans removeAllObjects];
            [self.publishedTx removeAllObjects];
            [self.publishedCallback removeAllObjects];
            [ZNMerkleBlockEntity deleteObjects:[ZNMerkleBlockEntity allObjects]];
            [ZNMerkleBlockEntity saveContext];
            _blocks = nil;
            _bloomFilter = nil;
            _lastBlock = nil;
            _lastOrphan = nil;

            for (ZNPeer *peer in self.connectedPeers) {
                [peer disconnect];
            }
        }];

    return self;
}

- (void)dealloc
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    if (self.activeObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.activeObserver];
    if (self.seedObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.seedObserver];
}

- (NSMutableOrderedSet *)peers
{
    if (_peers.count >= MAX_CONNECTIONS) return _peers;

    [[ZNPeerEntity context] performBlockAndWait:^{
        if (_peers.count >= MAX_CONNECTIONS) return;
        _peers = [NSMutableOrderedSet orderedSet];

        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];

        for (ZNPeerEntity *e in [ZNPeerEntity allObjects]) {
            if ([_peers.lastObject misbehavin] == 0) [_peers addObject:[e peer]];
            else [self.misbehavinPeers addObject:[e peer]];
        }

        if (_peers.count < MAX_CONNECTIONS) {
            // we're resorting to DNS peer discovery, so reset the misbahavin' count on any peers we already had in case
            // something went horribly wrong and every peer was marked as bad, but set timestamp older than two weeks
            for (ZNPeer *p in self.misbehavinPeers) {
                p.misbehavin = 0;
                p.timestamp += 14*24*60*60;
                [_peers addObject:p];
            }

            [self.misbehavinPeers removeAllObjects];

            for (int i = 0; i < sizeof(dns_seeds)/sizeof(*dns_seeds); i++) { // DNS peer discovery
                struct hostent *h = gethostbyname(dns_seeds[i]);

                for (int j = 0; h != NULL && h->h_addr_list[j] != NULL; j++) {
                    uint32_t addr = CFSwapInt32BigToHost(((struct in_addr *)h->h_addr_list[j])->s_addr);

                    [_peers addObject:[ZNPeer peerWithAddress:addr port:BITCOIN_STANDARD_PORT
                                       timestamp:now - 24*60*60*(3 + drand48()*4) services:NODE_NETWORK]];
                }
            }

#if BITCOIN_TESTNET
            [self sortPeers];
            return;
#endif
            if (_peers.count < MAX_CONNECTIONS) {
                // if dns peer discovery fails, fall back on a hard coded list of peers
                // hard coded list is taken from the satoshi client, values need to be byte swapped to be host native
                for (NSNumber *address in [NSArray arrayWithContentsOfFile:[[NSBundle mainBundle]
                                           pathForResource:FIXED_PEERS ofType:@"plist"]]) {
                    [_peers addObject:[ZNPeer peerWithAddress:CFSwapInt32(address.intValue) port:BITCOIN_STANDARD_PORT
                                       timestamp:now - 24*60*60*(7 + drand48()*7) services:NODE_NETWORK]];
                }
            }

            [self sortPeers];
        }
    }];

    return _peers;
}

- (NSMutableDictionary *)blocks
{
    if (_blocks.count > 0) return _blocks;

    [[ZNMerkleBlockEntity context] performBlockAndWait:^{
        if (_blocks.count > 0) return;
        _blocks = [NSMutableDictionary dictionary];
        self.checkpoints = [NSMutableDictionary dictionary];

        _blocks[GENESIS_BLOCK_HASH] = GENESIS_BLOCK;

        for (int i = 0; i < sizeof(checkpoint_array)/sizeof(*checkpoint_array); i++) {
            NSData *hash = [NSString stringWithUTF8String:checkpoint_array[i].hash].hexToData.reverse;

            _blocks[hash] = [[ZNMerkleBlock alloc] initWithBlockHash:hash version:1 prevBlock:nil merkleRoot:nil
                             timestamp:checkpoint_array[i].timestamp - NSTimeIntervalSince1970
                             target:checkpoint_array[i].target nonce:0 totalTransactions:0 hashes:nil flags:nil
                             height:checkpoint_array[i].height];
            self.checkpoints[@(checkpoint_array[i].height)] = hash;
        }

        for (ZNMerkleBlockEntity *e in [ZNMerkleBlockEntity allObjects]) {
            _blocks[e.blockHash] = [e merkleBlock];
        };
    }];

    return _blocks;
}

- (NSArray *)blockLocatorArray
{
    // append 10 most recent block hashes, decending, then continue appending, doubling the step back each time,
    // finishing with the genisis block (top, -1, -2, -3, -4, -5, -6, -7, -8, -9, -11, -15, -23, -39, -71, -135, ..., 0)
    NSMutableArray *locators = [NSMutableArray array];
    int32_t step = 1, start = 0;
    ZNMerkleBlock *b = self.lastBlock;

    while (b && b.height > 0) {
        [locators addObject:b.blockHash];
        if (++start >= 10) step *= 2;

        for (int32_t i = 0; b && i < step; i++) {
            b = self.blocks[b.prevBlock];
        }
    }

    [locators addObject:GENESIS_BLOCK_HASH];

    return locators;
}

- (ZNMerkleBlock *)lastBlock
{
    if (_lastBlock) return _lastBlock;

    NSFetchRequest *req = [ZNMerkleBlockEntity fetchRequest];

    req.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"height" ascending:NO]];
    req.predicate = [NSPredicate predicateWithFormat:@"height >= 0 && height != %d", BLOCK_UNKOWN_HEIGHT];
    req.fetchLimit = 1;
    _lastBlock = [[ZNMerkleBlockEntity fetchObjects:req].lastObject merkleBlock];

    for (int i = sizeof(checkpoint_array)/sizeof(*checkpoint_array) - 1; ! _lastBlock && i >= 0; i--) {
        if (checkpoint_array[i].timestamp + 7*24*60*60 - NSTimeIntervalSince1970 >= self.earliestKeyTime) continue;
        _lastBlock = [[ZNMerkleBlock alloc]
                      initWithBlockHash:[NSString stringWithUTF8String:checkpoint_array[i].hash].hexToData.reverse
                      version:1 prevBlock:nil merkleRoot:nil
                      timestamp:checkpoint_array[i].timestamp - NSTimeIntervalSince1970
                      target:checkpoint_array[i].target nonce:0 totalTransactions:0 hashes:nil flags:nil
                      height:checkpoint_array[i].height];
    }

    if (! _lastBlock) _lastBlock = GENESIS_BLOCK;

    return _lastBlock;
}

- (uint32_t)lastBlockHeight
{
    return self.lastBlock.height;
}

- (double)syncProgress
{
    if (! self.downloadPeer) return 0.05;
    if (self.lastBlockHeight >= self.downloadPeer.lastblock) return 1.0;
    return (self.connected ? 0.1 : 0.05) +
        (self.lastBlockHeight - self.syncStartHeight)/(double)(self.downloadPeer.lastblock - self.syncStartHeight)*0.9;
}

- (ZNBloomFilter *)bloomFilter
{
    //TODO: XXXX use a lower false positive rate when restoring from backup for imporved peformance
    
    // a bloom filter's falsepositive rate will increase with each item added to the filter, so if it has degraded by
    // half, clear it and build a new one
    if (_bloomFilter && _bloomFilter.length < BLOOM_MAX_FILTER_LENGTH &&
        _bloomFilter.falsePositiveRate > BLOOM_DEFAULT_FALSEPOSITIVE_RATE*2) {
        NSLog(@"bloom filter false positive rate has degraded by half after adding %d items... rebuilding",
              (int)_bloomFilter.elementCount);
        _bloomFilter = nil;
        self.filterWasReset = YES;
    }

    if (_bloomFilter) return _bloomFilter;

    ZNWallet *w = [[ZNWalletManager sharedInstance] wallet];

    // every time a new wallet address is added, the filter has to be rebuilt, and each address is only used for one
    // transaction, so here we generate some spare addresses to avoid rebuilding the filter each time a wallet
    // transaction is encountered during the blockchain download (generates twice the external gap limit for both
    // address chains)
    [w addressesWithGapLimit:SEQUENCE_GAP_LIMIT_EXTERNAL*2 internal:NO];
    [w addressesWithGapLimit:SEQUENCE_GAP_LIMIT_EXTERNAL*2 internal:YES];

    NSUInteger elemCount = w.addresses.count + w.unspentOutputs.count;
    ZNBloomFilter *filter = [ZNBloomFilter filterWithFalsePositiveRate:BLOOM_DEFAULT_FALSEPOSITIVE_RATE
                             forElementCount:(elemCount < 200) ? elemCount*1.5 : elemCount + 100
                             tweak:self.tweak flags:BLOOM_UPDATE_P2PUBKEY_ONLY];

    for (NSString *address in w.addresses) {
        NSData *d = address.base58checkToData;

        // add the address hash160 to watch for any tx receiveing money to the wallet
        if (d.length == 160/8 + 1) [filter insertData:[d subdataWithRange:NSMakeRange(1, d.length - 1)]];
    }

    for (NSData *utxo in w.unspentOutputs) {
        [filter insertData:utxo]; // add the unspent output to watch for any tx sending money from the wallet
    }
    
    _bloomFilter = filter;
    return _bloomFilter;
}

- (void)connect
{
    if (! [[ZNWalletManager sharedInstance] wallet]) return;
    if (self.connectFailures >= MAX_CONNENCT_FAILURES) self.connectFailures = 0; // this attempt is a manual retry
    
    if (self.syncProgress < 1.0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:ZNPeerManagerSyncStartedNotification object:nil];
        });
    }

    dispatch_async(self.q, ^{
        [self.connectedPeers minusSet:[self.connectedPeers objectsPassingTest:^BOOL(id obj, BOOL *stop) {
            return ([obj status] == ZNPeerStatusDisconnected) ? YES : NO;
        }]];

        if (self.connectedPeers.count >= MAX_CONNECTIONS) return; // we're already connected to MAX_CONNECTIONS peers

        NSMutableOrderedSet *peers = [NSMutableOrderedSet orderedSetWithOrderedSet:self.peers];

        if (peers.count > 100) [peers removeObjectsInRange:NSMakeRange(100, peers.count - 100)];
        if (! self.connected) self.syncStartHeight = self.lastBlockHeight;

        while (peers.count > 0 && self.connectedPeers.count < MAX_CONNECTIONS) {
            // pick a random peer biased towards peers with more recent timestamps
            ZNPeer *p = peers[(NSUInteger)(pow(lrand48() % peers.count, 2)/peers.count)];

            if (p && ! [self.connectedPeers containsObject:p]) {
                p.delegate = self;
                p.delegateQueue = self.q;
                p.earliestKeyTime = self.earliestKeyTime;
                [self.connectedPeers addObject:p];
                [p connect];
            }

            [peers removeObject:p];
        }

        if (self.connectedPeers.count == 0) {
            [self syncStopped];

            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:ZNPeerManagerSyncFailedNotification
                 object:nil userInfo:@{@"error":[NSError errorWithDomain:@"ZincWallet" code:1
                                                 userInfo:@{NSLocalizedDescriptionKey:@"no peers found"}]}];
            });
        }
    });
}

// rescans blocks and transactions after earliestKeyTime, a new random download peer is also selected due to the
// possibility that a malicious node might lie by omitting transactions that match the bloom filter
- (void)rescan
{
    if (! self.connected) return;

    _lastBlock = nil;

    // start the chain download from the most recent checkpoint that's at least a week older than earliestKeyTime
    for (int i = sizeof(checkpoint_array)/sizeof(*checkpoint_array) - 1; ! _lastBlock && i >= 0; i--) {
        if (checkpoint_array[i].timestamp + 7*24*60*60 - NSTimeIntervalSince1970 >= self.earliestKeyTime) continue;
        self.lastBlock = self.blocks[[NSString stringWithUTF8String:checkpoint_array[i].hash].hexToData.reverse];
    }

    if (! _lastBlock) _lastBlock = self.blocks[GENESIS_BLOCK_HASH];

    if (self.downloadPeer) { // disconnect the current download peer so a new random one will be selected
        [self.peers removeObject:self.downloadPeer];
        [self.downloadPeer disconnect];
    }

    self.syncStartHeight = self.lastBlockHeight;
    [self connect];
}

- (void)publishTransaction:(ZNTransaction *)transaction completion:(void (^)(NSError *error))completion
{
    if (! [transaction isSigned]) {
        if (completion) {
            completion([NSError errorWithDomain:@"ZincWallet" code:401
                        userInfo:@{NSLocalizedDescriptionKey:@"bitcoin transaction not signed"}]);
        }
        return;
    }

    if (! self.connected) {
        if (completion) {
            completion([NSError errorWithDomain:@"ZincWallet" code:-1009
                        userInfo:@{NSLocalizedDescriptionKey:@"transaction canceled, not connected to network"}]);
        }
        return;
    }

    self.publishedTx[transaction.txHash] = transaction;
    if (completion) self.publishedCallback[transaction.txHash] = completion;

    dispatch_async(dispatch_get_main_queue(), ^{
        [self performSelector:@selector(txTimeout:) withObject:transaction.txHash afterDelay:PROTOCOL_TIMEOUT];
    });

    NSMutableSet *peers = [NSMutableSet setWithSet:self.connectedPeers];

    // instead of publishing to all peers, leave one out to see if the tx propogates and is relayed back to us
    //TODO: also publish transactions directly to coinbase/bitpay/blockchain.info servers for faster POS experience
    if (peers.count > 1) [peers removeObject:[peers anyObject]];

    for (ZNPeer *p in peers) {
        [p sendInvMessageWithTxHash:transaction.txHash];
    }
}

// transaction is considered verified when all peers have relayed it
- (BOOL)transactionIsVerified:(NSData *)txHash
{
    return ([self.txRelayCounts countForObject:txHash] >= self.connectedPeers.count) ? YES : NO;
}

- (void)setBlockHeight:(int32_t)height forTxHashes:(NSArray *)txHashes
{
    [[[ZNWalletManager sharedInstance] wallet] setBlockHeight:height forTxHashes:txHashes];
    
    if (height != TX_UNCONFIRMED) { // remove confirmed tx from publish list and relay counts
        [self.publishedTx removeObjectsForKeys:txHashes];
        [self.publishedCallback removeObjectsForKeys:txHashes];
        [self.txRelayCounts minusSet:[NSSet setWithArray:txHashes]];
    }
}

- (void)txTimeout:(NSData *)txHash
{
    void (^callback)(NSError *error) = self.publishedCallback[txHash];

    [self.publishedTx removeObjectForKey:txHash];
    [self.publishedCallback removeObjectForKey:txHash];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(txTimeout:) object:txHash];

    if (callback) {
        callback([NSError errorWithDomain:@"ZincWallet" code:BITCOIN_TIMEOUT_CODE
                  userInfo:@{NSLocalizedDescriptionKey:@"transaction canceled, network timeout"}]);
    }
}

- (void)syncTimeout
{
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];

    if (now - self.lastRelayTime < PROTOCOL_TIMEOUT) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(syncTimeout) object:nil];
        [self performSelector:@selector(syncTimeout) withObject:nil
         afterDelay:PROTOCOL_TIMEOUT - (now - self.lastRelayTime)];
        return;
    }

    NSLog(@"%@:%d chain sync timed out", self.downloadPeer.host, self.downloadPeer.port);
    //BUG: the progress bar resets when the chain sync times out and auto-retries

    [self.peers removeObject:self.downloadPeer];
    [self.downloadPeer disconnect];
}

- (void)syncStopped
{
    if ([[UIApplication sharedApplication] applicationState] == UIApplicationStateBackground) {
        [self.peers.array makeObjectsPerformSelector:@selector(disconnect)];
    }

    if (self.taskId != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:self.taskId];
        self.taskId = UIBackgroundTaskInvalid;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(syncTimeout) object:nil];
    });
}

- (void)removeUnrelayedTransactions
{
    //BUG: XXXX this won't work if tx relays are still counted after the peer that relayed them is disconnected
    ZNWallet *w = [[ZNWalletManager sharedInstance] wallet];

    for (ZNTransaction *tx in w.recentTransactions) {
        if (tx.blockHeight != TX_UNCONFIRMED) break;
        if ([self.txRelayCounts countForObject:tx.txHash] == 0) [w removeTransaction:tx.txHash];
    }
}

- (void)peerMisbehavin:(ZNPeer *)peer
{
    peer.misbehavin++;
    [self.peers removeObject:peer];
    [self.misbehavinPeers addObject:peer];
    [peer disconnect];
    [self connect];
}

- (void)sortPeers
{
    [_peers sortUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        if ([obj1 timestamp] > [obj2 timestamp]) return NSOrderedAscending;
        if ([obj1 timestamp] < [obj2 timestamp]) return NSOrderedDescending;
        return NSOrderedSame;
    }];
}

- (void)savePeers
{
    NSMutableSet *peers = [[self.peers.set setByAddingObjectsFromSet:self.misbehavinPeers] mutableCopy];
    NSMutableSet *addrs = [NSMutableSet set];

    for (ZNPeer *p in peers) {
        [addrs addObject:@((int32_t)p.address)];
    }

    [[ZNPeerEntity context] performBlock:^{
        [ZNPeerEntity deleteObjects:[ZNPeerEntity objectsMatching:@"! (address in %@)", addrs]];

        for (ZNPeerEntity *e in [ZNPeerEntity objectsMatching:@"address in %@", addrs]) {
            ZNPeer *p = [peers member:[e peer]];

            if (p) {
                e.timestamp = p.timestamp;
                e.services = p.services;
                e.misbehavin = p.misbehavin;
                [peers removeObject:p];
            }
            else [e deleteObject];
        }

        for (ZNPeer *p in peers) {
            [[ZNPeerEntity managedObject] setAttributesFromPeer:p];
        }
    }];
}

- (void)saveBlocks
{
    NSMutableSet *blockHashes = [NSMutableSet set];
    ZNMerkleBlock *b = self.lastBlock;

    while (b) {
        [blockHashes addObject:b.blockHash];
        b = self.blocks[b.prevBlock];
    }

    [[ZNMerkleBlockEntity context] performBlock:^{
        [ZNMerkleBlockEntity deleteObjects:[ZNMerkleBlockEntity objectsMatching:@"! (blockHash in %@)", blockHashes]];

        for (ZNMerkleBlockEntity *e in [ZNMerkleBlockEntity objectsMatching:@"blockHash in %@", blockHashes]) {
            [e setAttributesFromBlock:self.blocks[e.blockHash]];
            [blockHashes removeObject:e.blockHash];
        }

        for (NSData *hash in blockHashes) {
            [[ZNMerkleBlockEntity managedObject] setAttributesFromBlock:self.blocks[hash]];
        }
    }];
}

#pragma mark - ZNPeerDelegate

- (void)peerConnected:(ZNPeer *)peer
{
    NSLog(@"%@:%d connected with lastblock %d", peer.host, peer.port, peer.lastblock);

    self.connectFailures = 0;
    peer.timestamp = [NSDate timeIntervalSinceReferenceDate]; // set last seen timestamp for peer

    if (peer.lastblock + 10 < self.lastBlock.height) { // drop peers that aren't synced yet, we can't help them
        [peer disconnect];
        return;
    }

    [peer sendFilterloadMessage:self.bloomFilter.data]; // load the bloom filter

    if (self.connected && (self.downloadPeer.lastblock >= peer.lastblock || self.lastBlock.height >= peer.lastblock)) {
        return; // we're already connected
    }

    // select the peer with the lowest ping time to download the chain from if we're behind
    for (ZNPeer *p in self.connectedPeers) {
        if ((p.pingTime < peer.pingTime && p.lastblock >= peer.lastblock) || p.lastblock > peer.lastblock) peer = p;
    }

    _connected = YES;
    [self.downloadPeer disconnect];
    self.downloadPeer = peer;

    if (self.lastBlock.height < peer.lastblock) { // start blockchain sync
        if (self.taskId == UIBackgroundTaskInvalid) { // start a background task for the chain sync
            self.taskId = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{}];
        }

        dispatch_async(dispatch_get_main_queue(), ^{ // setup a timer to detect if the sync stalls
            [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(syncTimeout) object:nil];
            [self performSelector:@selector(syncTimeout) withObject:nil afterDelay:PROTOCOL_TIMEOUT];
        });
        self.lastRelayTime = 0;

        // request just block headers up to earliestKeyTime, and then merkleblocks after that
        if (self.lastBlock.timestamp + 7*24*60*60 >= self.earliestKeyTime) {
            [peer sendGetblocksMessageWithLocators:[self blockLocatorArray] andHashStop:nil];
        }
        else [peer sendGetheadersMessageWithLocators:[self blockLocatorArray] andHashStop:nil];
    }
    else {
        [self syncStopped];
        [peer sendGetaddrMessage]; // request a list of other bitcoin peers

        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:ZNPeerManagerSyncFinishedNotification
             object:nil];
        });
    }
}

- (void)peer:(ZNPeer *)peer disconnectedWithError:(NSError *)error
{
    NSLog(@"%@:%d disconnected%@%@", peer.host, peer.port, error ? @", " : @"", error ? error : @"");
    
    if ([error.domain isEqual:@"ZincWallet"] && error.code != BITCOIN_TIMEOUT_CODE) {
        [self peerMisbehavin:peer];
    }
    else if (error) {
        [self.peers removeObject:peer];
        self.connectFailures++;
    }

    if ([self.downloadPeer isEqual:peer]) {
        _connected = NO;
        self.downloadPeer = nil;
        if (self.connectFailures > MAX_CONNENCT_FAILURES) self.connectFailures = MAX_CONNENCT_FAILURES;
        [self syncStopped];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (! self.connected && self.connectFailures == MAX_CONNENCT_FAILURES) {
            [[NSNotificationCenter defaultCenter] postNotificationName:ZNPeerManagerSyncFailedNotification
             object:nil userInfo:@{@"error":error}];
        }
        else if (self.connectFailures < MAX_CONNENCT_FAILURES) [self connect];
    });
}

- (void)peer:(ZNPeer *)peer relayedPeers:(NSArray *)peers
{
    NSLog(@"%@:%d relayed %d peer(s)", peer.host, peer.port, (int)peers.count);
    self.lastRelayTime = [NSDate timeIntervalSinceReferenceDate];
    [self.peers addObjectsFromArray:peers];
    [self.peers minusSet:self.misbehavinPeers];
    [self sortPeers];

    // limit total to 2500 peers
    if (self.peers.count > 2500) [self.peers removeObjectsInRange:NSMakeRange(2500, self.peers.count - 2500)];

    NSTimeInterval t = [NSDate timeIntervalSinceReferenceDate] - 3*60*60;

    // remove peers more than 3 hours old, or until there are only 1000 left
    while (self.peers.count > 1000 && [self.peers.lastObject timestamp] < t) {
        [self.peers removeObject:self.peers.lastObject];
    }

    if (peers.count < 1000) { // peer relaying is complete when we receive fewer than 1000
        [self removeUnrelayedTransactions]; // this is a good time to remove unconfirmed tx that dropped off the network
        [self savePeers];
        [ZNPeerEntity saveContext];
    }
}

- (void)peer:(ZNPeer *)peer relayedTransaction:(ZNTransaction *)transaction
{
    ZNWallet *w = [[ZNWalletManager sharedInstance] wallet];

    NSLog(@"%@:%d relayed transaction %@", peer.host, peer.port, transaction.txHash);
    self.lastRelayTime = [NSDate timeIntervalSinceReferenceDate];

    // When a transaction is matched by the bloom filter, if any of its output scripts have a hash or key that also
    // matches the filter, the remote peer will automatically add that output to the filter. That way if another
    // transaction spends the output later, it will also be matched without having to manually update the filter.
    // We do the same here with the local copy to keep the filters in sync.
    [self.bloomFilter insertTransaction:transaction];

    if ([w registerTransaction:transaction]) {
        // keep track of how many peers relay a tx, this indicates how likely it is to be confirmed in future blocks
        self.publishedTx[transaction.txHash] = transaction;
        [self.txRelayCounts addObject:transaction.txHash];

        if ([self.txRelayCounts countForObject:transaction.txHash] == self.connectedPeers.count) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:ZNPeerManagerTxStatusNotification
                 object:nil];
            });
        }

        // the transaction likely consumed one or more wallet addresses, so check that at least the next <gap limit>
        // unused addresses are still matched by the bloom filter
        NSArray *external = [w addressesWithGapLimit:SEQUENCE_GAP_LIMIT_EXTERNAL internal:NO],
                *internal = [w addressesWithGapLimit:SEQUENCE_GAP_LIMIT_INTERNAL internal:YES];

        for (NSString *a in [external arrayByAddingObjectsFromArray:internal]) {
            NSData *d = a.base58checkToData;
            
            if (d.length != 160/8 + 1) continue;
            if ([self.bloomFilter containsData:[d subdataWithRange:NSMakeRange(1, 160/8)]]) continue;
            
            _bloomFilter = nil;
            self.filterWasReset = YES;
            break;
        }
    }

    //BUG: XXXX durring a wallet restore with 40+ transactions, some tx are missed that don't show up until a rescan
    if (self.filterWasReset) { // filter got reset, send the new one to all the peers
        self.filterWasReset = NO;

        for (ZNPeer *peer in self.connectedPeers) {
            [peer sendFilterloadMessage:self.bloomFilter.data];
        }
    }
}

- (void)peer:(ZNPeer *)peer relayedBlock:(ZNMerkleBlock *)block
{
    self.lastRelayTime = [NSDate timeIntervalSinceReferenceDate];

    // ignore block headers that are newer than one week before earliestKeyTime (headers have 0 totalTransactions)
    if (block.totalTransactions == 0 && block.timestamp + 7*24*60*60 > self.earliestKeyTime) return;

    ZNMerkleBlock *prev = self.blocks[block.prevBlock];
    NSTimeInterval transitionTime = 0;

    if (! prev) { // block is an orphan
        NSLog(@"%@:%d relayed orphan block %@, previous %@, last block is %@, height %d", peer.host, peer.port,
              block.blockHash, block.prevBlock, self.lastBlock.blockHash, self.lastBlock.height);

        // ignore orphans older than one week ago
        if (block.timestamp < [NSDate timeIntervalSinceReferenceDate] - 7*24*60*60) return;

        // call getblocks, unless we already did with the previous block, or we're still downloading the chain
        if (self.lastBlock.height >= peer.lastblock && ! [self.lastOrphan.blockHash isEqual:block.prevBlock]) {
            NSLog(@"%@:%d calling getblocks", peer.host, peer.port);
            [peer sendGetblocksMessageWithLocators:[self blockLocatorArray] andHashStop:nil];
        }

        self.orphans[block.prevBlock] = block; // orphans are indexed by previous block rather than their own hash
        self.lastOrphan = block;
        return;
    }

    block.height = prev.height + 1;

    if ((block.height % BLOCK_DIFFICULTY_INTERVAL) == 0) { // hit a difficulty transition, find previous transition time
        ZNMerkleBlock *b = block;

        for (uint32_t i = 0; b && i < BLOCK_DIFFICULTY_INTERVAL; i++) {
            b = self.blocks[b.prevBlock];
        }

        transitionTime = b.timestamp;

        while (b) { // free up some memory
            b = self.blocks[b.prevBlock];
            if (b) [self.blocks removeObjectForKey:b.blockHash];
        }
    }

    // verify block difficulty
    if (! [block verifyDifficultyFromPreviousBlock:prev andTransitionTime:transitionTime]) {
        NSLog(@"%@:%d relayed block with invalid difficulty target %x, blockHash: %@", peer.host, peer.port,
              block.target, block.blockHash);
        [self peerMisbehavin:peer];
        return;
    }

    // verify block chain checkpoints
    if (self.checkpoints[@(block.height)] && ! [block.blockHash isEqual:self.checkpoints[@(block.height)]]) {
        NSLog(@"%@:%d relayed a block that differs from the checkpoint at height %d, blockHash: %@, expected: %@",
              peer.host, peer.port, block.height, block.blockHash, self.checkpoints[@(block.height)]);
        [self peerMisbehavin:peer];
        return;
    }

    if ([block.prevBlock isEqual:self.lastBlock.blockHash]) { // new block extends main chain
        if (! (block.height % 500) || block.height > peer.lastblock) NSLog(@"adding block at height: %d", block.height);

        self.blocks[block.blockHash] = block;
        self.lastBlock = block;
        [self setBlockHeight:block.height forTxHashes:block.txHashes];
    }
    else if (self.blocks[block.blockHash] != nil) { // we already have the block (or at least the header)
        NSLog(@"%@:%d relayed existing block at height %d", peer.host, peer.port, block.height);
        self.blocks[block.blockHash] = block;

        ZNMerkleBlock *b = self.lastBlock;

        while (b && b.height > block.height) { // check if block is in main chain
            b = self.blocks[b.prevBlock];
        }

        if ([b.blockHash isEqual:block.blockHash]) { // if it's not on a fork, set block heights for its transactions
            [self setBlockHeight:block.height forTxHashes:block.txHashes];
            if (block.height == self.lastBlock.height) self.lastBlock = block;
        }
    }
    else { // new block is on a fork
        if (block.height <= BITCOIN_REFERENCE_BLOCK_HEIGHT) { // fork is older than the most recent checkpoint
            NSLog(@"ignoring block on fork older than most recent checkpoint, fork height: %d, blockHash: %@",
                  block.height, block.blockHash);
            return;
        }

        // special case, if a new block is mined while we're rescaning the chain, mark as orphan til we're caught up
        if (self.lastBlock.height < peer.lastblock && block.height > self.lastBlock.height + 1) {
            NSLog(@"marking new block at height %d as orphan until rescan completes", block.height);
            self.orphans[block.prevBlock] = block;
            self.lastOrphan = block;
            return;
        }

        NSLog(@"chain fork to height %d", block.height);
        self.blocks[block.blockHash] = block;
        if (block.height <= self.lastBlock.height) return; // if fork is shorter than main chain, ingore it for now

        NSMutableArray *txHashes = [NSMutableArray array];
        ZNMerkleBlock *b = block, *b2 = self.lastBlock;

        while (b && b2 && ! [b.blockHash isEqual:b2.blockHash]) { // walk back to where the fork joins the main chain
            b = self.blocks[b.prevBlock];
            if (b.height < b2.height) b2 = self.blocks[b2.prevBlock];
        }

        NSLog(@"reorganizing chain from height %d, new height is %d", b.height, block.height);

        // mark transactions after the join point as unconfirmed
        for (ZNTransaction *tx in [[[ZNWalletManager sharedInstance] wallet] recentTransactions]) {
            if (tx.blockHeight <= b.height) break;
            [txHashes addObject:tx.txHash];
        }

        [self setBlockHeight:TX_UNCONFIRMED forTxHashes:txHashes];
        b = block;

        while (b.height > b2.height) { // set transaction heights for new main chain
            [self setBlockHeight:b.height forTxHashes:b.txHashes];
            b = self.blocks[b.prevBlock];
        }

        self.lastBlock = block;
    }

    if (block.height == peer.lastblock && block == self.lastBlock) { // chain download is complete
        [self saveBlocks];
        [ZNMerkleBlockEntity saveContext];
        [self syncStopped];
        [peer sendGetaddrMessage]; // request a list of other bitcoin peers

        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:ZNPeerManagerSyncFinishedNotification
             object:nil];
        });
    }

    if (block == self.lastBlock && self.orphans[block.blockHash]) { // check if the next block was received as an orphan
        ZNMerkleBlock *b = self.orphans[block.blockHash];

        [self.orphans removeObjectForKey:block.blockHash];
        [self peer:peer relayedBlock:b];
    }

    if (block.height > peer.lastblock) { // notify that transaction confirmations may have changed
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:ZNPeerManagerTxStatusNotification object:nil];
        });
    }
}

- (ZNTransaction *)peer:(ZNPeer *)peer requestedTransaction:(NSData *)txHash
{
    ZNTransaction *tx = self.publishedTx[txHash];
    void (^callback)(NSError *error) = self.publishedCallback[txHash];
    
    if (tx) {
        [self.publishedCallback removeObjectForKey:txHash];
        [self.bloomFilter insertTransaction:tx];
        [self.txRelayCounts addObject:txHash];
        [[[ZNWalletManager sharedInstance] wallet] registerTransaction:tx];

        if ([self.txRelayCounts countForObject:txHash] == self.connectedPeers.count) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:ZNPeerManagerTxStatusNotification
                 object:nil];
            });
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(txTimeout:) object:txHash];
            if (callback) callback(nil);
        });

    }

    return tx;
}

@end
