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
#import "ZNTransactionEntity.h"
#import "ZNTxOutputEntity.h"
#import "ZNMerkleBlock.h"
#import "ZNMerkleBlockEntity.h"
#import "ZNAddressEntity.h"
#import "ZNWallet.h"
#import "NSString+Base58.h"
#import "NSMutableData+Bitcoin.h"
#import "NSData+Bitcoin.h"
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
    prevBlock:@"0000000000000000000000000000000000000000000000000000000000000000".hexToData\
    merkleRoot:@"3ba3edfd7a7b12b27ac72c3e67768f617fC81bc3888a51323a9fb8aa4b1e5e4a".hexToData\
    timestamp:1296688602.0 - NSTimeIntervalSince1970 target:0x1d00ffffu nonce:414098458u totalTransactions:1\
    hashes:@"3ba3edfd7a7b12b27ac72c3e67768f617fC81bc3888a51323a9fb8aa4b1e5e4a".hexToData flags:@"00".hexToData]

static const struct { uint32_t height; char *hash; } checkpoint_array[] = {};

static const char *dns_seeds[] = { "testnet-seed.bitcoin.petertodd.org", "testnet-seed.bluematt.me" };

#else

#define GENESIS_BLOCK_HASH @"000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f".hexToData

#define GENESIS_BLOCK [[ZNMerkleBlock alloc] initWithBlockHash:[GENESIS_BLOCK_HASH reverse] version:1\
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
@property (nonatomic, assign) NSUInteger filterElemCount;
@property (nonatomic, assign) BOOL filterWasReset;
@property (nonatomic, strong) NSMutableDictionary *publishedTx, *publishedCallback, *checkpoints;
@property (nonatomic, strong) NSCountedSet *txRelayCounts;

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

#warning remove this!
    //    [ZNMerkleBlockEntity deleteObjects:[ZNMerkleBlockEntity allObjects]]; //for testing chain download
    //    [ZNTransactionEntity deleteObjects:[ZNTransactionEntity allObjects]]; // and remove this
    self.earliestKeyTime = [NSDate timeIntervalSinceReferenceDate] - 365*24*60*60; // remove this too

    self.earliestKeyTime = BITCOIN_REFERENCE_BLOCK_TIME;
    self.peers = [NSMutableArray array];
    self.tweak = mrand48();
    self.publishedTx = [NSMutableDictionary dictionary];
    self.publishedCallback = [NSMutableDictionary dictionary];
    self.txRelayCounts = [NSCountedSet set];
    self.checkpoints = [NSMutableDictionary dictionary];
    
    for (int i = 0; i < sizeof(checkpoint_array)/sizeof(*checkpoint_array); i++) {
        self.checkpoints[@(checkpoint_array[i].height)] =
        [[NSString stringWithUTF8String:checkpoint_array[i].hash].hexToData reverse];
    }

    [[ZNMerkleBlockEntity context] performBlock:^{
        NSFetchRequest *req = [ZNMerkleBlockEntity fetchRequest];

        req.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"height" ascending:YES]];
        req.predicate = [NSPredicate predicateWithFormat:@"height >= 0 && height != %d", TX_UNCONFIRMED];
        req.fetchBatchSize = 100;
        self.blockChain = [[ZNMerkleBlockEntity fetchObjects:req] mutableCopy];

        if (self.blockChain.lastObject == nil) {
            [self.blockChain addObject:[[ZNMerkleBlockEntity managedObject] setAttributesFromBlock:GENESIS_BLOCK]];
            [self.blockChain.lastObject setHeight:0];
        }

        NSAssert([self.blockChain.lastObject height] + 1 == self.blockChain.count, @"wrong block height %d at index %d",
                 [self.blockChain.lastObject height], self.blockChain.count);
    
        for (ZNTransactionEntity *e in [ZNTransactionEntity objectsMatching:@"blockHeight == %d", TX_UNCONFIRMED]) {
            ZNTransaction *tx = [e transaction];
            
            self.publishedTx[tx.txHash] = tx;
        }
    }];
    
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
            for (int j = 0; h->h_addr_list[j] != NULL; j++) {
                uint32_t addr = CFSwapInt32BigToHost(((struct in_addr *)h->h_addr_list[j])->s_addr);
                ZNPeerEntity *e = [ZNPeerEntity createOrUpdateWithPeer:[ZNPeer peerWithAddress:addr
                                                                        andPort:BITCOIN_STANDARD_PORT]];
            
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
    [[ZNPeerEntity context] performBlock:^{
        [self.peers
         removeObjectsAtIndexes:[self.peers indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
            return ([obj status] == disconnected) ? YES : NO;
        }]];

        if (self.peers.count >= MAX_CONNECTIONS) return; // we're already connected to MAX_CONNECTIONS peers

        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:syncStartedNotification object:nil];
        });

        NSFetchRequest *req = [ZNPeerEntity fetchRequest];
    
        req.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"timestamp" ascending:NO]];
        req.predicate = [NSPredicate predicateWithFormat:@"misbehavin == 0"];
        req.fetchLimit = MAX_CONNECTIONS + 100;
        if ([ZNPeerEntity countObjects:req] < MAX_CONNECTIONS) [self discoverPeers];

        NSMutableArray *peers = [NSMutableArray arrayWithArray:[ZNPeerEntity fetchObjects:req]];

        if (self.peers.count < MAX_CONNECTIONS) self.syncStartHeight = [self.blockChain.lastObject height];
    
        while (peers.count > 0 && self.peers.count < MAX_CONNECTIONS) {
            // pick a random peer biased towards peers with more recent timestamps
            ZNPeerEntity *e = peers[(NSUInteger)(pow(lrand48() % peers.count, 2)/peers.count)];
            ZNPeer *p = [ZNPeer peerWithAddress:e.address andPort:e.port];
            
            if (p && ! [self.peers containsObject:p]) {
                p.delegate = self;
                [self.peers addObject:p];
                [p connect];
            }
            
            [peers removeObject:e];
        }
    
        if (self.peers.count == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:syncFailedNotification
                 object:@{@"error":[NSError errorWithDomain:@"ZincWallet" code:1
                 userInfo:@{NSLocalizedDescriptionKey:@"no peers found"}]}];
            });
        }
    }];
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

    // every time a new wallet address is added to the filter, the filter has to be rebuilt and sent to each peer, and
    // each address is only used for one transaction, so here we generate some spare addresses to avoid rebuilding the
    // filter each time a wallet transaction is encountered during the blockchain download
    // (generates twice the external gap limit for both address chains)
    [[ZNWallet sharedInstance] addressesWithGapLimit:SEQUENCE_GAP_LIMIT_EXTERNAL*2 internal:NO];
    [[ZNWallet sharedInstance] addressesWithGapLimit:SEQUENCE_GAP_LIMIT_EXTERNAL*2 internal:YES];

    NSArray *addresses = [ZNAddressEntity allObjects];
    NSArray *utxos = [ZNTxOutputEntity objectsMatching:@"spent == NO"];

    self.filterElemCount = addresses.count + utxos.count;
    self.filterElemCount = (self.filterElemCount < 200) ? self.filterElemCount*1.5 : self.filterElemCount + 100;
    _bloomFilter = [ZNBloomFilter filterWithFalsePositiveRate:BLOOM_DEFAULT_FALSEPOSITIVE_RATE
                    forElementCount:self.filterElemCount tweak:self.tweak flags:BLOOM_UPDATE_P2PUBKEY_ONLY];
    
    [[ZNAddressEntity context] performBlockAndWait:^{
        for (ZNAddressEntity *e in addresses) {
            NSData *d = [e.address base58checkToData];
            
            // add the address hash160 to watch for any tx receiveing money to the wallet
            if (d.length == 160/8 + 1) [_bloomFilter insertData:[d subdataWithRange:NSMakeRange(1, d.length - 1)]];
        }
        
        for (ZNTxOutputEntity *e in utxos) {
            if (! [[ZNWallet sharedInstance] containsAddress:e.address]) continue;
            NSMutableData *d = [NSMutableData data];
            
            [d appendData:e.txHash];
            [d appendUInt32:e.n];
            [_bloomFilter insertData:d]; // add the unspent output to watch for any tx sending money from the wallet
        }
        
        //TODO: after a wallet restore and chain download, reset all non-download peer's filters with new utxo's
    }];
    
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

    [[ZNWallet sharedInstance] registerTransaction:transaction];

    self.publishedTx[transaction.txHash] = transaction;
    if (completion) self.publishedCallback[transaction.txHash] = completion;

    //TODO: XXXX setup a publish timeout
    //TODO: also publish transactions directly to coinbase and bitpay servers for faster POS experience

    for (ZNPeer *peer in self.peers) {
        [peer sendInvMessageWithTxHash:transaction.txHash];
    }
}

// transaction is considered verified when all peers have relayed it
- (BOOL)transactionIsVerified:(NSData *)txHash
{
    //TODO: we also need to know if a transaction is bad (double spend, not propagated after a certain time, etc...)
    // and also consider estimated confirmation time based on fee per kb and priority

    return ([self.txRelayCounts countForObject:txHash] >= MAX_CONNECTIONS) ? YES : NO;
}

- (void)peerMisbehavin:(ZNPeer *)peer
{
    [[ZNPeerEntity context] performBlockAndWait:^{
        [ZNPeerEntity createOrUpdateWithPeer:peer].misbehavin++;
    }];
    
    [peer disconnect];
    [self connect];
}

- (double)syncProgress
{
    if (self.downloadPeer.status != connected) return 0;
    
    int32_t height = [[self.blockChain.lastObject get:@"height"] intValue];
    
    if (height >= self.downloadPeer.lastblock) return 1;
    
    return (height - self.syncStartHeight)/(double)(self.downloadPeer.lastblock - self.syncStartHeight);
}

#pragma mark - ZNPeerDelegate

- (void)peerConnected:(ZNPeer *)peer
{
    NSLog(@"%@:%d connected", peer.host, peer.port);

    [[ZNPeerEntity createOrUpdateWithPeer:peer] set:@"timestamp" to:[NSDate date]]; // set last seen timestamp for peer
    [peer sendFilterloadMessage:self.bloomFilter.data]; // load the bloom filter

    if ([ZNPeerEntity countAllObjects] <= 1000) [peer sendGetaddrMessage]; // request a list of other bitcoin peers
    
    if (self.connected) return; // we're already connected
    
    // if all peers have connected, select the peer with the lowest ping time to download the chain from if we're behind
    for (ZNPeer *p in self.peers) {
        if (p.status != connected) return; // wait for all peers to finish connecting
        if (p.pingTime < peer.pingTime) peer = p; // find the peer with the lowest ping time
    }

    _connected = YES;
    self.downloadPeer = peer;

    [[ZNMerkleBlockEntity context] performBlockAndWait:^{
        uint32_t top = [self.blockChain.lastObject height];
        NSTimeInterval t = [self.blockChain.lastObject timestamp];
        
        if (top < peer.lastblock) {
            int32_t step = 1, start = 0;
            NSMutableArray *locators = [NSMutableArray array];
            NSData *hash = nil;
        
            // append 10 most recent block hashes, decending, then continue appending, doubling the step back each time,
            // finishing with the genisis block (top, -1, -2, -3, -4, -5, -6, -7, -8, -9, -11, -15, -23, -39, -71, ...0)
            for (int32_t i = top; i > 0; i -= step, ++start) {
                if (start >= 10) step *= 2;
                hash = [self.blockChain[i] blockHash];
                if (hash) [locators addObject:hash];
            }
            
            [locators addObject:[GENESIS_BLOCK_HASH reverse]];
            
            // request just block headers up to earliestKeyTime, and then merkleblocks after that
            if (t + 7*24*60*60 > self.earliestKeyTime) {
                [peer sendGetblocksMessageWithLocators:locators andHashStop:nil];
            }
            else [peer sendGetheadersMessageWithLocators:locators andHashStop:nil];
        }
        else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:syncFinishedNotification object:nil];
            });
        }
    }];
}

- (void)peer:(ZNPeer *)peer disconnectedWithError:(NSError *)error
{
    [self.peers removeObject:peer];
    NSLog(@"%@:%d disconnected%@%@", peer.host, peer.port, error ? @", " : @"", error ? error : @"");
    
    if ([error.domain isEqual:@"ZincWallet"]) {
        [self peerMisbehavin:peer];
    }
    else if (error) [[ZNPeerEntity createOrUpdateWithPeer:peer] deleteObject];

    //TODO: XXXX check for network reachability

    if (! self.downloadPeer || [self.downloadPeer isEqual:peer]) {
        _connected = NO;
        self.downloadPeer = nil;
//        self.connectFailures++;
//
//        if (self.connectFailures > 5) {
//            if (! error) {
//                error = [NSError errorWithDomain:@"ZincWallet" code:0
//                         userInfo:@{NSLocalizedDescriptionKey:@"couldn't connect to bitcoin network"}];
//            }
//
//            dispatch_async(dispatch_get_main_queue(), ^{
//                [[NSNotificationCenter defaultCenter] postNotificationName:walletSyncFailedNotification
//                 object:@{@"error":error}];
//            });
//            return;
//        }
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self connect];
    });
}

- (void)peer:(ZNPeer *)peer relayedPeers:(NSArray *)peers
{
    [[ZNPeerEntity context] performBlockAndWait:^{
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

//TODO: XXXX measure performance, this will be called thousands of times durring a wallet restore
- (void)peer:(ZNPeer *)peer relayedTransaction:(ZNTransaction *)transaction
{
    [[ZNTransactionEntity context] performBlockAndWait:^{
        NSMutableData *d = [NSMutableData data];
        uint32_t n = 0;

        NSLog(@"%@:%d relayed transaction %@", peer.host, peer.port, transaction);
        
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
    
        [self.txRelayCounts addObject:transaction.txHash]; // increment relay count before registering tx with wallet
    
        ZNWallet *w = [ZNWallet sharedInstance];
        BOOL registered = [w registerTransaction:transaction];
    
        if (! registered) [self.txRelayCounts removeObject:transaction.txHash];
        
        // the transaction likely consumed one or more wallet addresses, so check that at least the next <gap limit>
        // unused addresses are still matched by the bloom filter
        if (registered && ! self.filterWasReset) {
            NSArray *addrs =
                [[w addressesWithGapLimit:SEQUENCE_GAP_LIMIT_EXTERNAL internal:NO]
                 arrayByAddingObjectsFromArray:[w addressesWithGapLimit:SEQUENCE_GAP_LIMIT_INTERNAL internal:YES]];
        
            for (NSString *a in addrs) {
                NSData *d = [a base58checkToData];
                
                if (d.length != 160/8 + 1) continue;
                if ([self.bloomFilter containsData:[d subdataWithRange:NSMakeRange(1, 160/8)]]) continue;

                _bloomFilter = nil;
                self.filterWasReset = YES;
                break;
            }
        }
    
        if (self.filterWasReset) { // filter got reset, send the new one to all the peers
            for (ZNPeer *peer in self.peers) {
                [peer sendFilterloadMessage:self.bloomFilter.data];
            }
            
            self.filterWasReset = NO;
        }
        
        if (registered) self.publishedTx[transaction.txHash] = transaction;
        
        // if we're not downloading the chain, relay tx to other peers so we have plausible deniability for our own tx
        //TODO: XXXX relay tx to other peers
    }];
}

- (void)peer:(ZNPeer *)peer relayedBlock:(ZNMerkleBlock *)block
{
    // ignore block headers that are newer than one week before earliestKeyTime (headers have 0 totalTransactions)
    if (block.totalTransactions == 0 && block.timestamp + 7*24*60*60 > self.earliestKeyTime) return;

    //[[ZNMerkleBlockEntity context] processPendingChanges];

    [[ZNMerkleBlockEntity context] performBlockAndWait:^{
        ZNMerkleBlockEntity *e = (self.prevHeight < self.blockChain.count) ? self.blockChain[self.prevHeight] : nil;

        NSAssert(!e || e.height == self.prevHeight, @"wrong block height %d at index %d", e.height, self.prevHeight);

        if (! [e.blockHash isEqual:block.prevBlock]) {
            e = [ZNMerkleBlockEntity objectsMatching:@"blockHash == %@", block.prevBlock].lastObject;
        }

        int32_t height = abs(e.height) + 1;
        NSTimeInterval transitionTime = 0;

        //TODO: XXX need to have some kind of timeout/retry if chain download stalls

        if (! e) { // block is an orphan
            // if we're still downloading the chain, ignore orphan block for now since it's probably in the chain
            if ([self.blockChain.lastObject height] < peer.lastblock) return;

            NSLog(@"%@:%d relayed orphan block, calling getblocks with last block", peer.host, peer.port);

            //TODO: this should use a full locator array so we don't download the entire chain if top block is on a fork
            //TODO: set a limit on how many times we call getblocks, if we get 500 blocks and the first one is an
            //      orphan, we don't want to make 500 getblocks requests
            [peer sendGetblocksMessageWithLocators:@[[self.blockChain.lastObject blockHash]] andHashStop:block.blockHash];
            return;
        }

        self.prevHeight = height;

        if ((height % BITCOIN_DIFFICULTY_INTERVAL) == 0) { // hit a difficulty transition, find last transition time
            transitionTime = [self.blockChain[height - BITCOIN_DIFFICULTY_INTERVAL] timestamp];
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

        if (e.height < 0) { // chain forks are denoted internally by using negative height
            e = [ZNMerkleBlockEntity objectsMatching:@"blockHash == %@", block.blockHash].lastObject;
        }
        else e = (height < self.blockChain.count) ? self.blockChain[height] : nil;

        NSAssert(!e || e.height < 0 || e.height == height, @"wrong block height %d at index %d", e.height, height);
        NSAssert(!e || e.height < 0 || [e.blockHash isEqual:block.blockHash], @"block hash wrong at height %d", height);

        if (e) { // we already have the block (or at least the header)
            if ((height % 500) == 0) NSLog(@"%@:%d relayed existing block at height %d", peer.host, peer.port, height);

            [e setAttributesFromBlock:block]; // the bloom filter may have matched additional transactions, so update it

            if (e.height >= 0) { // if it's not on a fork, set block heights for the block's transactions
                [ZNTransactionEntity setBlockHeight:height forTxHashes:block.txHashes];
                [self.publishedTx removeObjectsForKeys:block.txHashes]; // remove confirmed tx from publish list
                [self.txRelayCounts minusSet:[NSSet setWithArray:block.txHashes]];
            }
            return;
        }
        else if ([block.prevBlock isEqual:[self.blockChain.lastObject blockHash]]) { // new block extends main chain
            if ((height % 500) == 0) NSLog(@"adding block at height: %d", height);

            e = [[ZNMerkleBlockEntity managedObject] setAttributesFromBlock:block];
            e.height = height;

            if (e.height < self.blockChain.count) {
                [self.blockChain insertObject:e atIndex:height];
            }
            else [self.blockChain addObject:e];

            [ZNTransactionEntity setBlockHeight:height forTxHashes:block.txHashes];
            [self.publishedTx removeObjectsForKeys:block.txHashes]; // remove confirmed transactions from publish list
            [self.txRelayCounts minusSet:[NSSet setWithArray:block.txHashes]];
        }
        else { // new block is on a fork
            if (height <= BITCOIN_REFERENCE_BLOCK_HEIGHT) { // fork is older than the most recent checkpoint
                NSLog(@"%@:%d relayed a block that forks prior to the last checkpoint, fork height: %d, blockHash: %@",
                      peer.host, peer.port, height, block.blockHash);
                [self peerMisbehavin:peer];
                return;
            }

            NSLog(@"chain fork at height %d", height);

            e = [[ZNMerkleBlockEntity managedObject] setAttributesFromBlock:block];
            e.height = -height; // negative height denotes a fork

            // if fork is shorter than main chain, ingore it for now
            if (height <= [self.blockChain.lastObject height]) return;

            // the fork is longer than the main chain, so make it the new main chain
            int32_t h = -height;

            while (h < 0) { // walk back to where the fork joins the old main chain
                e = [ZNMerkleBlockEntity objectsMatching:@"blockHash == %@", e.prevBlock].lastObject;
                h = e.height;
            }

            NSLog(@"reorganizing chain from height %d, new height is %d", h, height);

            // mark transactions after the join point as unconfirmed
            [ZNTransactionEntity setBlockHeight:TX_UNCONFIRMED
             forTxHashes:[[ZNTransactionEntity objectsMatching:@"blockHeight > %d", h] valueForKey:@"txHash"]];

            // set old main chain heights to negative to denote they are now a fork
            for (e in [ZNMerkleBlockEntity objectsMatching:@"height > %d", h]) {
                [self.blockChain removeObject:e];
                e.height *= -1;
            }

            e = [ZNMerkleBlockEntity objectsMatching:@"blockHash == %@", block.blockHash].lastObject;;

            while (e.height < 0) { // set block heights for new main chain and mark its transactions as confirmed
                e.height *= -1;

                if (e.height < self.blockChain.count) {
                    [self.blockChain insertObject:e atIndex:height];
                }
                else [self.blockChain addObject:e];

                [ZNTransactionEntity setBlockHeight:e.height forTxHashes:e.merkleBlock.txHashes];
                [self.publishedTx removeObjectsForKeys:e.merkleBlock.txHashes]; // remove confirmed tx from publish list
                [self.txRelayCounts minusSet:[NSSet setWithArray:block.txHashes]];
                e = [ZNMerkleBlockEntity objectsMatching:@"blockHash == %@", e.prevBlock].lastObject;;
            }

            // re-publish any transactions that may have become unconfirmed
            for (ZNTransactionEntity *tx in [ZNTransactionEntity objectsMatching:@"blockHeight == %d", TX_UNCONFIRMED]){
                [self publishTransaction:tx.transaction completion:nil];
            }
        }

        // if we're done getting headers up to one week before earliestKeyTime, get merkle blocks for remaining chain
        if (block.totalTransactions == 0 && block.timestamp + 7*24*60*60 > self.earliestKeyTime) {
            //TODO: this should use a full locator array so we don't dowload the entire chain if top block is on a fork
            [peer sendGetblocksMessageWithLocators:@[[self.blockChain.lastObject blockHash]] andHashStop:nil];
        }

        if (height == peer.lastblock) { // chain download is complete
            //TODO: XXXX the entire chain can take several minutes for core data to save on slower devices, so make sure
            // there's a background process to allow it to complete (what happens if the app is re-entered during save?)
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:syncFinishedNotification object:nil];
            });
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
    
    return [[[ZNTransactionEntity objectsMatching:@"txHash == %@ && blockHeight == %d", txHash, TX_UNCONFIRMED]
             lastObject] transaction];
}

@end
