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
#import "ZNWallet.h"
#import "NSString+Base58.h"
#import "NSMutableData+Bitcoin.h"
#import "NSData+Bitcoin.h"
#import "NSData+Hash.h"
#import "NSManagedObject+Utils.h"
#import <netdb.h>
#import <arpa/inet.h>
#import "Reachability.h"

#define FIXED_PEERS      @"FixedPeers"
#define MAX_CONNECTIONS  3
#define NODE_NETWORK     1 // services value indicating a node offers full blocks, not just headers
#define PROTOCOL_TIMEOUT 10.0

#if BITCOIN_TESTNET

#define GENESIS_BLOCK_HASH @"000000000933ea01ad0ee984209779baaec3ced90fa3f408719526f8d77f4943".hexToData

// The testnet genesis block uses the mainnet genesis block's merkle root. The hash is wrong using it's own root.
#define GENESIS_BLOCK [[ZNMerkleBlock alloc] initWithBlockHash:GENESIS_BLOCK_HASH.reverse version:1\
    prevBlock:@"0000000000000000000000000000000000000000000000000000000000000000".hexToData\
    merkleRoot:@"3ba3edfd7a7b12b27ac72c3e67768f617fC81bc3888a51323a9fb8aa4b1e5e4a".hexToData\
    timestamp:1296688602.0 - NSTimeIntervalSince1970 target:0x1d00ffffu nonce:414098458u totalTransactions:1\
    hashes:@"3ba3edfd7a7b12b27ac72c3e67768f617fC81bc3888a51323a9fb8aa4b1e5e4a".hexToData flags:@"00".hexToData]

static const struct { uint32_t height; char *hash; } checkpoint_array[] = {};

static const char *dns_seeds[] = { "testnet-seed.bitcoin.petertodd.org", "testnet-seed.bluematt.me" };

#else

#define GENESIS_BLOCK_HASH @"000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f".hexToData

#define GENESIS_BLOCK [[ZNMerkleBlock alloc] initWithBlockHash:GENESIS_BLOCK_HASH.reverse version:1\
    prevBlock:@"0000000000000000000000000000000000000000000000000000000000000000".hexToData\
    merkleRoot:@"3ba3edfd7a7b12b27ac72c3e67768f617fC81bc3888a51323a9fb8aa4b1e5e4a".hexToData\
    timestamp:1231006505.0 - NSTimeIntervalSince1970 target:0x1d00ffffu nonce:2083236893u totalTransactions:1\
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

static const char *dns_seeds[] = {
    "seed.bitcoin.sipa.be", "dnsseed.bluematt.me", "dnsseed.bitcoin.dashjr.org", "bitseed.xf2.org"
};

#endif

@interface ZNPeerManager ()

@property (nonatomic, strong) NSMutableArray *peers, *blockChain;
@property (nonatomic, strong) ZNPeer *downloadPeer;
@property (nonatomic, assign) uint32_t tweak, syncStartHeight, prevHeight;
@property (nonatomic, strong) ZNBloomFilter *bloomFilter;
@property (nonatomic, assign) NSUInteger filterElemCount, taskId;
@property (nonatomic, assign) BOOL filterWasReset;
@property (nonatomic, strong) NSMutableDictionary *checkpoints, *publishedTx, *publishedCallback;
@property (nonatomic, strong) NSCountedSet *txRelayCounts;
@property (nonatomic, strong) ZNWallet *wallet;
@property (nonatomic, strong) Reachability *reachability;

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

    self.wallet = [ZNWallet sharedInstance];
    self.earliestKeyTime = BITCOIN_REFERENCE_BLOCK_TIME;
    self.peers = [NSMutableArray array];
    self.tweak = mrand48();
    self.publishedTx = [NSMutableDictionary dictionary];
    self.publishedCallback = [NSMutableDictionary dictionary];
    self.txRelayCounts = [NSCountedSet set];
    self.taskId = UIBackgroundTaskInvalid;
    self.prevHeight = NSNotFound;
    self.reachability = [Reachability reachabilityForInternetConnection];
    self.checkpoints = [NSMutableDictionary dictionary];

    for (int i = 0; i < sizeof(checkpoint_array)/sizeof(*checkpoint_array); i++) {
        self.checkpoints[@(checkpoint_array[i].height)] =
            [NSString stringWithUTF8String:checkpoint_array[i].hash].hexToData.reverse;
    }

    for (ZNTransaction *tx in self.wallet.recentTransactions) {
        if (tx.blockHeight == TX_UNCONFIRMED) self.publishedTx[tx.txHash] = tx;
    }

    NSFetchRequest *req = [ZNMerkleBlockEntity fetchRequest];
    
    req.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"height" ascending:NO]];
    req.predicate = [NSPredicate predicateWithFormat:@"height >= 0 && height != %d", TX_UNCONFIRMED];
    req.fetchLimit = 1;
    _lastBlockHeight = [[[ZNMerkleBlockEntity fetchObjects:req].lastObject get:@"height"] unsignedIntegerValue];

    //TODO: disconnect peers when app is backgrounded unless we're syncing or launching mobile web app tx handler
    
    return self;
}

- (NSUInteger)discoverPeers
{
    __block NSUInteger count = 0;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];

    for (int i = 0; i < sizeof(dns_seeds)/sizeof(*dns_seeds); i++) { // DNS peer discovery
        struct hostent *h = gethostbyname(dns_seeds[i]);
        
        [[ZNPeerEntity context] performBlockAndWait:^{
            for (int j = 0; h != NULL && h->h_addr_list[j] != NULL; j++) {
                uint32_t addr = CFSwapInt32BigToHost(((struct in_addr *)h->h_addr_list[j])->s_addr);
                ZNPeerEntity *e =
                    [ZNPeerEntity createOrUpdateWithPeer:[ZNPeer peerWithAddress:addr andPort:BITCOIN_STANDARD_PORT]];
                
                e.timestamp = now - 24*60*60*(3 + drand48()*4); // random timestamp between 3 and 7 days ago;
                e.services = NODE_NETWORK;
                e.misbehavin = 0;
                count++;
            }
        }];
    }
    
    // if we've resorted to DNS peer discovery, reset the misbahavin' count on any peers we already had in case
    // something went horribly wrong and every peer was marked as bad, but give them a timestamp older than two weeks
    [[ZNPeerEntity context] performBlockAndWait:^{
        for (ZNPeerEntity *e in [ZNPeerEntity objectsMatching:@"misbehavin > 0"]) {
            e.misbehavin = 0;
            e.timestamp += 14*24*60*60;
        }
    }];

    //TODO: connect to a few random DNS peers and just to grab a list of peers and disconnect so as to not overload them

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

- (void)connect
{
    if (self.reachability.currentReachabilityStatus == NotReachable) return;

    if (! self.downloadPeer || self.lastBlockHeight < self.downloadPeer.lastblock) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:ZNPeerManagerSyncStartedNotification object:nil];
        });
    }

    [[ZNPeerEntity context] performBlock:^{
        [self.peers
         removeObjectsAtIndexes:[self.peers indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
            return ([obj status] == disconnected) ? YES : NO;
        }]];

        //BUG: if we're behind and haven't received a block in 10-20 seconds, we might need a tickle

        if (self.peers.count >= MAX_CONNECTIONS) return; // we're already connected to MAX_CONNECTIONS peers

        NSFetchRequest *req = [ZNPeerEntity fetchRequest];
    
        req.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"timestamp" ascending:NO]];
        req.predicate = [NSPredicate predicateWithFormat:@"misbehavin == 0"];
        req.fetchLimit = MAX_CONNECTIONS + 100;
        if ([ZNPeerEntity countObjects:req] < MAX_CONNECTIONS) [self discoverPeers];

        NSMutableArray *peers = [NSMutableArray arrayWithArray:[ZNPeerEntity fetchObjects:req]];

        if (self.peers.count < MAX_CONNECTIONS) self.syncStartHeight = self.lastBlockHeight;
    
        while (peers.count > 0 && self.peers.count < MAX_CONNECTIONS) {
            // pick a random peer biased towards peers with more recent timestamps
            ZNPeerEntity *e = peers[(NSUInteger)(pow(lrand48() % peers.count, 2)/peers.count)];
            ZNPeer *p = [ZNPeer peerWithAddress:e.address andPort:e.port];
            
            if (p && ! [self.peers containsObject:p]) {
                p.delegate = self;
                p.earliestKeyTime = self.earliestKeyTime;
                [self.peers addObject:p];
                [p connect];
            }
            
            [peers removeObject:e];
        }
    
        if (self.peers.count == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.taskId != UIBackgroundTaskInvalid) {
                    [[UIApplication sharedApplication] endBackgroundTask:self.taskId];
                    self.taskId = UIBackgroundTaskInvalid;
                }

                [[NSNotificationCenter defaultCenter] postNotificationName:ZNPeerManagerSyncFailedNotification
                 object:@{@"error":[NSError errorWithDomain:@"ZincWallet" code:1
                 userInfo:@{NSLocalizedDescriptionKey:@"no peers found"}]}];
            });
        }
    }];
}

- (NSMutableArray *)blockChain
{
    if (_blockChain.count > 0) return _blockChain;

    [[ZNMerkleBlockEntity context] performBlockAndWait:^{
        if (_blockChain.count > 0) return;

        NSFetchRequest *req = [ZNMerkleBlockEntity fetchRequest];

        req.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"height" ascending:YES]];
        req.predicate = [NSPredicate predicateWithFormat:@"height >= 0 && height != %d", TX_UNCONFIRMED];

        _blockChain = [[ZNMerkleBlockEntity fetchObjects:req] mutableCopy];

        if (_blockChain.lastObject == nil) {
            [_blockChain addObject:[[ZNMerkleBlockEntity managedObject] setAttributesFromBlock:GENESIS_BLOCK]];
            [_blockChain.lastObject setHeight:0];
        }

        for (int32_t i = [_blockChain[0] height]; i > 0; i--) {
            [_blockChain insertObject:[NSNull null] atIndex:0];
        }

        _lastBlockHeight = [_blockChain.lastObject height];

        NSAssert(self.lastBlockHeight + 1 == _blockChain.count, @"wrong block height %d at index %d",
                 (int)self.lastBlockHeight, (int)_blockChain.count - 1);
    }];

    return _blockChain;
}

- (NSArray *)blockLocatorArray
{
    NSMutableArray *locators = [NSMutableArray array];

    // append 10 most recent block hashes, decending, then continue appending, doubling the step back each time,
    // finishing with the genisis block (top, -1, -2, -3, -4, -5, -6, -7, -8, -9, -11, -15, -23, -39, -71, -135, ..., 0)
    [[ZNMerkleBlockEntity context] performBlockAndWait:^{
        int32_t step = 1, start = 0;

        for (int i = (int)self.lastBlockHeight; i > 0 && self.blockChain[i] != [NSNull null]; i -= step, ++start) {
            if (start >= 10) step *= 2;
            [locators addObject:[self.blockChain[i] blockHash]];
        }
    }];

    [locators addObject:GENESIS_BLOCK_HASH.reverse];

    return locators;
}

//TODO: XXXX add refresh method that refreshes blocks/tx from earliestKeyTime
// a malicious node might lie by omitting transactions, so it's a good idea to be able to refresh from a random node

- (ZNBloomFilter *)bloomFilter
{
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

    // every time a new wallet address is added to the filter, the filter has to be rebuilt and sent to each peer,
    // and each address is only used for one transaction, so here we generate some spare addresses to avoid
    // rebuilding the filter each time a wallet transaction is encountered during the blockchain download (generates
    // twice the external gap limit for both address chains)
    [self.wallet addressesWithGapLimit:SEQUENCE_GAP_LIMIT_EXTERNAL*2 internal:NO];
    [self.wallet addressesWithGapLimit:SEQUENCE_GAP_LIMIT_EXTERNAL*2 internal:YES];

    self.filterElemCount = self.wallet.addresses.count + self.wallet.unspentOutputs.count;
    self.filterElemCount = (self.filterElemCount < 200) ? self.filterElemCount*1.5 : self.filterElemCount + 100;


    ZNBloomFilter *filter = [ZNBloomFilter filterWithFalsePositiveRate:BLOOM_DEFAULT_FALSEPOSITIVE_RATE
                             forElementCount:self.filterElemCount tweak:self.tweak flags:BLOOM_UPDATE_P2PUBKEY_ONLY];

    for (NSString *address in self.wallet.addresses) {
        NSData *d = address.base58checkToData;
            
        // add the address hash160 to watch for any tx receiveing money to the wallet
        if (d.length == 160/8 + 1) [filter insertData:[d subdataWithRange:NSMakeRange(1, d.length - 1)]];
    }
    
    for (NSData *utxo in self.wallet.unspentOutputs) {
        [filter insertData:utxo]; // add the unspent output to watch for any tx sending money from the wallet
    }
    
    //TODO: after a wallet restore and chain download, reset all non-download peer's filters with new utxo's

    _bloomFilter = filter;
    return _bloomFilter;
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

    [self.wallet registerTransaction:transaction];

    self.publishedTx[transaction.txHash] = transaction;
    if (completion) self.publishedCallback[transaction.txHash] = completion;

    //TODO: XXXX setup a publish timeout
    //TODO: also publish transactions directly to coinbase and bitpay servers for faster POS experience

    for (ZNPeer *peer in self.peers) {
        [peer sendInvMessageWithTxHash:transaction.txHash];
    }
}

- (void)setBlockHeight:(int32_t)height forTxHashes:(NSArray *)txHashes
{
    if (txHashes.count == 0) return;

    [self.wallet setBlockHeight:height forTxHashes:txHashes];
    
    if (height != TX_UNCONFIRMED) { // remove confirmed tx from publish list and relay counts
        [self.publishedTx removeObjectsForKeys:txHashes];
        [self.publishedCallback removeObjectsForKeys:txHashes];
        [self.txRelayCounts minusSet:[NSSet setWithArray:txHashes]];
    }
}

// transaction is considered verified when all peers have relayed it
- (BOOL)transactionIsVerified:(NSData *)txHash
{
    //TODO: we also need to know if a transaction is bad (double spend, not propagated after a certain time, etc...)
    // and also consider estimated confirmation time based on fee per kb and priority

    return ([self.txRelayCounts countForObject:txHash] >= MAX_CONNECTIONS) ? YES : NO;
}

- (double)syncProgress
{
    // TODO: account for both download and processing progress indivdually so progress doesn't appear stalled

    if (! self.downloadPeer) return 0.0;

    if (self.lastBlockHeight >= self.downloadPeer.lastblock) return 1;

    return (self.connected ? 0.05 : 0.0) +
        (self.lastBlockHeight - self.syncStartHeight)/(double)(self.downloadPeer.lastblock - self.syncStartHeight)*0.95;
}

- (void)peerMisbehavin:(ZNPeer *)peer
{
    [[ZNPeerEntity context] performBlockAndWait:^{
        [ZNPeerEntity createOrUpdateWithPeer:peer].misbehavin++;
    }];
    
    [peer disconnect];
    [self connect];
}

#pragma mark - ZNPeerDelegate

- (void)peerConnected:(ZNPeer *)peer
{
    NSLog(@"%@:%d connected", peer.host, peer.port);

    [[ZNPeerEntity createOrUpdateWithPeer:peer] set:@"timestamp" to:[NSDate date]]; // set last seen timestamp for peer

    //TODO: adjust the false positive rate depending on how far behind we are, to target, say, 100 transactions that
    // aren't in the wallet for plausible deniability
    [peer sendFilterloadMessage:self.bloomFilter.data]; // load the bloom filter

    if ([ZNPeerEntity countAllObjects] < 500) [peer sendGetaddrMessage]; // request a list of other bitcoin peers
    
    if (self.connected) return; // we're already connected
    
    // select the peer with the lowest ping time to download the chain from if we're behind
    for (ZNPeer *p in self.peers) {
        //if (p.status != connected) return; // wait for all peers to finish connecting
        if (p.pingTime < peer.pingTime) peer = p; // find the peer with the lowest ping time
    }

    _connected = YES;
    self.downloadPeer = peer;

    if (self.lastBlockHeight < peer.lastblock) {
        [[ZNMerkleBlockEntity context] performBlockAndWait:^{
            if (self.taskId == UIBackgroundTaskInvalid) {
                self.taskId = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{}];
            }

            //TODO: XXXX need a timeout for stalled chain downloads

            // request just block headers up to earliestKeyTime, and then merkleblocks after that
            if ([self.blockChain.lastObject timestamp] + 7*24*60*60 >= self.earliestKeyTime) {
                [peer sendGetblocksMessageWithLocators:[self blockLocatorArray] andHashStop:nil];
            }
            else [peer sendGetheadersMessageWithLocators:[self blockLocatorArray] andHashStop:nil];
        }];
    }
    else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:ZNPeerManagerSyncFinishedNotification
            object:nil];
        });
    }
}

- (void)peer:(ZNPeer *)peer disconnectedWithError:(NSError *)error
{
    //TODO: XXXX detect 10-20 connection refused (NSPOSIXErrorDomain Code=61) in a row and notify about network problem
    // Error Domain=NSPOSIXErrorDomain Code=65 "The operation couldn’t be completed. No route to host"
    // Error Domain=NSPOSIXErrorDomain Code=49 "The operation couldn’t be completed. Can't assign requested address"
    NSLog(@"%@:%d disconnected%@%@", peer.host, peer.port, error ? @", " : @"", error ? error : @"");
    
    if ([error.domain isEqual:@"ZincWallet"] && error.code != 1001) {
        [self peerMisbehavin:peer];
    }
    else if (error) [[ZNPeerEntity createOrUpdateWithPeer:peer] deleteObject];

    if (! self.downloadPeer || [self.downloadPeer isEqual:peer]) {
        _connected = NO;
        self.downloadPeer = nil;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self connect];
    });
}

- (void)peer:(ZNPeer *)peer relayedPeers:(NSArray *)peers
{
    [[ZNPeerEntity context] performBlock:^{
        [ZNPeerEntity createOrUpdateWithPeers:peers];
    
        NSUInteger count = [ZNPeerEntity countAllObjects], deleted = 0;
        NSFetchRequest *req = [ZNPeerEntity fetchRequest];
        
        if (count > 1000) { // remove peers with a timestamp more than 3 hours old, or until there are only 1000 left
            req.predicate = [NSPredicate predicateWithFormat:@"timestamp < %@",
                             [NSDate dateWithTimeIntervalSinceReferenceDate:[NSDate timeIntervalSinceReferenceDate] -
                              3*60*60]];
            req.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"timestamp" ascending:YES]];
            req.fetchLimit = count - 1000;
            deleted = [ZNPeerEntity deleteObjects:[ZNPeerEntity fetchObjects:req]];

            if (count - deleted > 2500) { // limit total to 2500 peers
                [ZNPeerEntity deleteObjects:[ZNPeerEntity objectsSortedBy:@"timestamp" ascending:YES offset:0
                 limit:count - deleted - 2500]];
            }
        }
    }];
}

- (void)peer:(ZNPeer *)peer relayedTransaction:(ZNTransaction *)transaction
{
    NSMutableData *d = [NSMutableData data];
    uint32_t n = 0;

    // When a transaction is matched by the bloom filter, if any of it's output scripts have a hash or key that also
    // matches the filter, the remote peer will automatically add that output to the filter. That way if another
    // transaction spends the output later, it will also be matched without having to manually update the filter.
    // We do the same here with the local copy to keep the filters in sync.
    for (NSData *script in transaction.outputScripts) {
        for (NSData *elem in [script scriptDataElements]) {
            if (! [self.bloomFilter containsData:elem]) continue;
            [d setData:transaction.txHash];
            [d appendUInt32:n];
            [self.bloomFilter insertData:d]; // update bloom filter with matched txout
            break;
        }

        n++;
    }

    NSLog(@"%@:%d relayed transaction %@", peer.host, peer.port, transaction.txHash);

    if ([self.wallet registerTransaction:transaction]) {
        // keep track of how many peers relay a tx, this indicates how likely it is to be confirmed in future blocks
        [self.txRelayCounts addObject:transaction.txHash];
        self.publishedTx[transaction.txHash] = transaction;

        // the transaction likely consumed one or more wallet addresses, so check that at least the next <gap limit>
        // unused addresses are still matched by the bloom filter
        NSArray *external = [self.wallet addressesWithGapLimit:SEQUENCE_GAP_LIMIT_EXTERNAL internal:NO],
                *internal = [self.wallet addressesWithGapLimit:SEQUENCE_GAP_LIMIT_INTERNAL internal:YES];

        for (NSString *a in [external arrayByAddingObjectsFromArray:internal]) {
            NSData *d = a.base58checkToData;
            
            if (d.length != 160/8 + 1) continue;
            if ([self.bloomFilter containsData:[d subdataWithRange:NSMakeRange(1, 160/8)]]) continue;
            
            _bloomFilter = nil;
            self.filterWasReset = YES;
            break;
        }
    }

    if (self.filterWasReset) { // filter got reset, send the new one to all the peers
        self.filterWasReset = NO;

        for (ZNPeer *peer in self.peers) {
            [peer sendFilterloadMessage:self.bloomFilter.data];
        }
    }

    // if we're not downloading the chain, relay tx to other peers for plausible deniability for our own tx
    //TODO: XXXX relay tx to other peers
}

- (void)peer:(ZNPeer *)peer relayedBlock:(ZNMerkleBlock *)block
{
    // ignore block headers that are newer than one week before earliestKeyTime (headers have 0 totalTransactions)
    if (block.totalTransactions == 0 && block.timestamp + 7*24*60*60 >= self.earliestKeyTime) return;

    [[ZNMerkleBlockEntity context] performBlock:^{
        // find previous block
        ZNMerkleBlockEntity *e = (self.prevHeight < self.blockChain.count) ? self.blockChain[self.prevHeight] : nil;

        NSAssert(! e || e.height == self.prevHeight, @"wrong block height %d at index %d", e.height, self.prevHeight);

        if (! [e.blockHash isEqual:block.prevBlock]) {
            e = [ZNMerkleBlockEntity objectsMatching:@"blockHash == %@", block.prevBlock].lastObject;
        }

        if (! e) { // block is an orphan
            // if we're still downloading the chain, ignore orphan block for now since it's probably in the chain
            if (self.lastBlockHeight < peer.lastblock) return;

            NSLog(@"%@:%d relayed orphan block %@, previous %@, calling getblocks with last block %@", peer.host,
                  peer.port, block.blockHash, block.prevBlock, [self.blockChain[self.lastBlockHeight] blockHash]);

            //TODO: set a limit on how many times we call getblocks, if we get 500 blocks and the first one is an
            //      orphan, we don't want to make 500 getblocks requests
            [peer sendGetblocksMessageWithLocators:[self blockLocatorArray] andHashStop:block.blockHash];
            return;
        }

        int32_t height = abs(e.height) + 1;
        NSTimeInterval transitionTime = 0;

        self.prevHeight = height;

        if ((height % BITCOIN_DIFFICULTY_INTERVAL) == 0) { // hit a difficulty transition, find previous transition time
            transitionTime = [self.blockChain[height - BITCOIN_DIFFICULTY_INTERVAL] timestamp];

            if (height > BITCOIN_DIFFICULTY_INTERVAL*2) { // discard blocks prior to the previous two transitions
                int32_t h = height - BITCOIN_DIFFICULTY_INTERVAL*2;

                [ZNMerkleBlockEntity
                 deleteObjects:[ZNMerkleBlockEntity objectsMatching:@"height < 0 && height > %d", -h]];
                [ZNMerkleBlockEntity
                 deleteObjects:[ZNMerkleBlockEntity objectsMatching:@"height >= 0 && height < %d", h]];
                [self.blockChain removeObjectsInRange:NSMakeRange(0, h)];

                while (self.blockChain.count <= self.lastBlockHeight) {
                    [self.blockChain insertObject:[NSNull null] atIndex:0];
                }
            }
        }

        // verify block difficulty
        if (! [block verifyDifficultyAtHeight:height previous:e.merkleBlock transitionTime:transitionTime]) {
            NSLog(@"%@:%d relayed block with invalid difficulty target %x, blockHash: %@", peer.host, peer.port,
                  block.target, block.blockHash);
            [self peerMisbehavin:peer];
            return;
        }

        // verify block chain checkpoints
        if (self.checkpoints[@(height)] && ! [block.blockHash isEqual:self.checkpoints[@(height)]]) {
            NSLog(@"%@:%d relayed a block that differs from the checkpoint at height %d, blockHash: %@, expected: %@",
                  peer.host, peer.port, height, block.blockHash, self.checkpoints[@(height)]);
            [self peerMisbehavin:peer];
            return;
        }

        // check if we already have the block
        if (e.height >= 0) { // negative block heights are used internally to denote chain forks
            e = (height < self.blockChain.count) ? self.blockChain[height] : nil;

            if (e && ! [e.blockHash isEqual:block.blockHash]) {
                e = [ZNMerkleBlockEntity objectsMatching:@"blockHash == %@", block.blockHash].lastObject;
            }
        }
        else e = [ZNMerkleBlockEntity objectsMatching:@"blockHash == %@", block.blockHash].lastObject;

        NSAssert(! e || e.height < 0 || e.height == height, @"wrong block height %d at index %d", e.height, height);

        if (e) { // we already have the block (or at least the header)
            if ((height % 500) == 0) NSLog(@"%@:%d relayed existing block at height %d", peer.host, peer.port, height);

            [e setAttributesFromBlock:block]; // update the block in case the bloom matched additional transactions

            // if the block isn't on a fork, set block heights for its transactions
            if (e.height >= 0) [self setBlockHeight:height forTxHashes:block.txHashes];
            return;
        }
        else if ([block.prevBlock isEqual:[self.blockChain.lastObject blockHash]]) { // new block extends main chain
            if ((height % 500) == 0) NSLog(@"adding block at height: %d", height);

            e = [[ZNMerkleBlockEntity managedObject] setAttributesFromBlock:block];
            e.height = height;
            [self.blockChain addObject:e];
            _lastBlockHeight = height;

            NSAssert(self.lastBlockHeight + 1 == self.blockChain.count, @"wrong block height %d at index %d",
                     (int)self.lastBlockHeight, (int)self.blockChain.count - 1);

            [self setBlockHeight:height forTxHashes:block.txHashes];
        }
        else { // new block is on a fork
            if (height <= BITCOIN_REFERENCE_BLOCK_HEIGHT) { // fork is older than the most recent checkpoint
                NSLog(@"ignoring block on fork older than most recent checkpoint, fork height: %d, blockHash: %@",
                      height, block.blockHash);
                return;
            }

            NSLog(@"chain fork to height %d", height);

            e = [[ZNMerkleBlockEntity managedObject] setAttributesFromBlock:block];
            e.height = -height; // set negative height to denote a fork

            // if fork is shorter than main chain, ingore it for now
            if (height <= self.lastBlockHeight) return;

            // the fork is longer than the main chain, so make it the new main chain
            int32_t h = -height;

            while (h < 0) { // walk back to where the fork joins the old main chain
                e = [ZNMerkleBlockEntity objectsMatching:@"blockHash == %@", e.prevBlock].lastObject;
                h = e.height;
            }

            NSLog(@"reorganizing chain from height %d, new height is %d", h, height);

            // mark transactions after the join point as unconfirmed
            NSMutableArray *txHashes = [NSMutableArray array];

            for (ZNTransaction *tx in self.wallet.recentTransactions) {
                if (tx.blockHeight > h) [txHashes addObject:tx.txHash];
            }

            [self setBlockHeight:TX_UNCONFIRMED forTxHashes:txHashes];

            // set old main chain heights to negative to denote they are now a fork
            for (e in [ZNMerkleBlockEntity objectsMatching:@"height > %d", h]) {
                [self.blockChain removeObject:e];
                e.height *= -1;
            }

            e = [ZNMerkleBlockEntity objectsMatching:@"blockHash == %@", block.blockHash].lastObject;

            while (e.height < 0) { // set block heights for new main chain and mark its transactions as confirmed
                e.height *= -1;

                while (self.blockChain.count <= e.height) {
                    [self.blockChain addObject:[NSNull null]];
                    _lastBlockHeight = e.height;
                }

                [self.blockChain replaceObjectAtIndex:e.height withObject:e];
                [self setBlockHeight:e.height forTxHashes:e.merkleBlock.txHashes];
                e = [ZNMerkleBlockEntity objectsMatching:@"blockHash == %@", e.prevBlock].lastObject;
            }

            NSAssert(self.lastBlockHeight + 1 == self.blockChain.count, @"wrong block height %d at index %d",
                     (int)self.lastBlockHeight, (int)self.blockChain.count - 1);

            // re-publish any transactions that may have become unconfirmed
            for (ZNTransaction *tx in self.wallet.recentTransactions) {
                if (tx.blockHeight == TX_UNCONFIRMED) [self publishTransaction:tx completion:nil];
            }
        }

        if (height >= peer.lastblock) [ZNMerkleBlockEntity saveContext];

        if (height == peer.lastblock) { // chain download is complete
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:ZNPeerManagerSyncFinishedNotification
                 object:nil];
            });
            
            if (self.taskId != UIBackgroundTaskInvalid) {
                [[UIApplication sharedApplication] endBackgroundTask:self.taskId];
                self.taskId = UIBackgroundTaskInvalid;
            }
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
    }

    return tx;
}

@end
