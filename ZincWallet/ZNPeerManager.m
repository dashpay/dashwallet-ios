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
#import "ZNTransaction.h"
#import "ZNTransactionEntity.h"
#import "ZNTxOutputEntity.h"
#import "ZNAddressEntity.h"
#import "ZNWallet.h"
#import "NSString+Base58.h"
#import "NSMutableData+Bitcoin.h"
#import "NSData+Hash.h"
#import "NSManagedObject+Utils.h"
#import <netdb.h>
#import <arpa/inet.h>

// blockchain checkpoints
//
//( 11111, uint256("0x0000000069e244f73d78e8fd29ba2fd2ed618bd6fa2ee92559f542fdb26e7c1d"))
//( 33333, uint256("0x000000002dd5588a74784eaa7ab0507a18ad16a236e7b1ce69f00d7ddfb5d0a6"))
//( 74000, uint256("0x0000000000573993a3c9e41ce34471c079dcf5f52a0e824a81e7f953b8661a20"))
//(105000, uint256("0x00000000000291ce28027faea320c8d2b054b2e0fe44a773f3eefb151d6bdc97"))
//(134444, uint256("0x00000000000005b12ffd4cd315cd34ffd4a594f430ac814c91184a0d42d2b0fe"))
//(168000, uint256("0x000000000000099e61ea72015e79632f216fe6cb33d7899acb35b75c8303b763"))
//(193000, uint256("0x000000000000059f452a5f7340de6682a977387c17010ff6e6c3bd83ca8b1317"))
//(210000, uint256("0x000000000000048b95347e83192f69cf0366076336c639f9b7228e9ba171342e"))
//(216116, uint256("0x00000000000001b4f4b433e81ee46494af945cf96014816a4e2370f11b23df4e"))
//(225430, uint256("0x00000000000001c108384350f74090433e7fcf79a606b8e797f065b130575932"))
//(250000, uint256("0x000000000000003887df1f29024b06fc2200b55f8af8f35453d7be294df2d214"))
//
//static const CCheckpointData data = {
//    &mapCheckpoints,
//    1375533383, // * UNIX timestamp of last checkpoint block
//    21491097,   // * total number of transactions between genesis and last checkpoint
//                //   (the tx=... number in the SetBestChain debug.log lines)
//    60000.0     // * estimated number of transactions per day after checkpoint
//};

#define FIXED_PEERS     @"FixedPeers"
#define MAX_CONNECTIONS 3

@interface ZNPeerManager ()

@property (nonatomic, strong) NSMutableArray *peers;
//@property (nonatomic, assign) BOOL connected;
@property (nonatomic, assign) int connectFailures;

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
        singleton = [self new];
    });
    
    return singleton;
}

- (instancetype)init
{
    if (! (self = [super init])) return nil;

    self.peers = [NSMutableArray array];
    
    //TODO: monitor network reachability and reconnect whenever connection becomes available
    //TODO: disconnect peers when app is backgrounded unless we're syncing or launching mobile web app tx handler
    
    return self;
}

- (NSUInteger)discoverPeers
{
    __block NSUInteger count = 0;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
#if BITCOIN_TESTNET
    NSArray *a = @[@"testnet-seed.bitcoin.petertodd.org", @"testnet-seed.bluematt.me"];
#else
    NSArray *a = @[@"seed.bitcoin.sipa.be", @"dnsseed.bluematt.me", @"dnsseed.bitcoin.dashjr.org", @"bitseed.xf2.org"];
#endif

    // DNS peer discovery
    // TODO: provide seed.zincwallet.com DNS seed service
    for (NSString *host in a) {
        struct hostent *h = gethostbyname(host.UTF8String);
        
        for (int j = 0; h->h_addr_list[j] != NULL; j++) {
            uint32_t addr = CFSwapInt32BigToHost(((struct in_addr *)h->h_addr_list[j])->s_addr);
            NSTimeInterval t = now - 24*60*60*(3 + drand48()*4); // random timestamp between 3 and 7 days ago
            
            [ZNPeerEntity createOrUpdateWithAddress:addr port:STANDARD_PORT timestamp:t services:NODE_NETWORK];
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
        
        [ZNPeerEntity createOrUpdateWithAddress:addr port:STANDARD_PORT timestamp:t services:NODE_NETWORK];
        count++;
    }
#endif
    
    return count;
}

- (ZNPeerEntity *)randomPeer
{
    //TODO: prefer peers within 3 hours of most recent peer?
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
    
    if (! e) {
        [[NSNotificationCenter defaultCenter] postNotificationName:walletSyncFailedNotification
         object:@{@"error":[NSError errorWithDomain:@"ZincWallet" code:1
                            userInfo:@{NSLocalizedDescriptionKey:@"no peers found"}]}];
        return;
    }
    
    ZNPeer *peer = [ZNPeer peerWithAddress:e.address andPort:e.port];
    
    peer.delegate = self;
    [self.peers removeAllObjects]; //XXX: obviously this will need to change
    [self.peers addObject:peer];

    [peer connect];
}

- (void)subscribeToAddresses:(NSArray *)addresses
{
    //TODO: add addresses to bloom filters
}

#pragma mark - ZNPeerDelegate

- (void)peerConnected:(ZNPeer *)peer
{
    _connected = YES;
    self.connectFailures = 0;
    NSLog(@"%@:%d connected", peer.host, peer.port);
    
    [[NSNotificationCenter defaultCenter] postNotificationName:walletSyncFinishedNotification object:nil];
    
    if ([ZNPeerEntity countAllObjects] <= 1000) [peer sendGetaddrMessage];
    
    //TODO: XXXX send bloom filters
}

- (void)peer:(ZNPeer *)peer disconnectedWithError:(NSError *)error
{
    [self.peers removeObject:peer];
    NSLog(@"%@:%d disconnected%@%@", peer.host, peer.port, error ? @", " : @"", error ? error : @"");

    //TODO: XXXX check for network reachability
    if (error) {
        [[ZNPeerEntity objectsMatching:@"address == %u && port == %u", peer.address, peer.port]
         makeObjectsPerformSelector:@selector(deleteObject)];
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
    NSUInteger idx = 0;
    
    if (tx) {
        // TODO: mark tx as having been relayed
        return;
    }

    // relayed transactions don't contain input scripts, input scripts must be obtained from previous tx outputs
    for (NSData *hash in transaction.inputHashes) { // lookup input addresses
        uint32_t n = [transaction.inputIndexes[idx++] unsignedIntValue];
        ZNTransactionEntity *e = [ZNTransactionEntity objectsMatching:@"txHash == %@", hash].lastObject;

        if (! e) continue; // if the input tx is missing, then that input tx didn't involve wallet addresses
        
        if (n > e.outputs.count) {
            NSLog(@"invalid transaction, input %u has non-existant previous output index", (int)idx - 1);
            return;
        }
        
        //TODO: refactor this to use the actual previous output script instead of generating a new one from the address
        [transaction setInputAddress:[(ZNTxOutputEntity *)e.outputs[n] address] atIndex:idx - 1];
    }
    
    [[ZNWallet sharedInstance] registerTransaction:transaction]; // registerTransaction will ignore any non-wallet tx
}

@end
