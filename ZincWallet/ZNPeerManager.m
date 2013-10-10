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

    self.peers = [NSMutableArray array];
    
    return self;
}

- (NSUInteger)discoverPeers
{
    __block NSUInteger count = 0;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate] + NSTimeIntervalSince1970;
#if BITCOIN_TESTNET
    NSArray *a = @[@"testnet-seed.bitcoin.petertodd.org", @"testnet-seed.bluematt.me"];
#else
    NSArray *a = @[@"seed.bitcoin.sipa.be", @"dnsseed.bluematt.me", @"dnsseed.bitcoin.dashjr.org", @"bitseed.xf2.org"];
#endif

    // DNS peer discovery
    // TODO: provide seed.zincwallet.com DNS seed service
    [a enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        struct hostent *h = gethostbyname([obj UTF8String]);
        
        for (int j = 0; h->h_addr_list[j] != NULL; j++) {
            struct in_addr a = *(struct in_addr *)h->h_addr_list[j];
            NSTimeInterval t = now - 24*60*60*(3 + drand48()*4); // random timestamp between 3 and 7 days ago
            
            [ZNPeerEntity entityWithAddress:a.s_addr port:STANDARD_PORT timestamp:t services:NODE_NETWORK];
            count++;
        }
    }];
    
#if ! BITCOIN_TESTNET
    if (count > 0) return count;
     
    // if dns peer discovery fails, fall back on a hard coded list of peers
    [[NSArray arrayWithContentsOfFile:[[NSBundle mainBundle] pathForResource:FIXED_PEERS ofType:@"plist"]]
    enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        NSTimeInterval t = now - 24*60*60*(7 + drand48()*7); // random timestamp between 7 and 14 days ago
        
        [ZNPeerEntity entityWithAddress:[obj intValue] port:STANDARD_PORT timestamp:t services:NODE_NETWORK];
        count++;
    }];
#endif
    
    return count;
}

- (ZNPeerEntity *)randomPeer
{
    NSUInteger count = [ZNPeerEntity countAllObjects], offset = 0;
    
    if (count == 0) count += [self discoverPeers];
    if (count == 0) return nil;
    
    offset = pow(lrand48() % count, 2)/count; // pick a random peer biased for peers with more recent timestamps
    return [ZNPeerEntity objectsSortedBy:@"timestamp" ascending:NO offset:offset limit:1].lastObject;
}

- (void)connect
{
    ZNPeerEntity *e = [self randomPeer];
    
    if (! e) return;
    
    ZNPeer *peer = [ZNPeer peerWithAddress:e.address andPort:e.port];
    
    [self.peers addObject:peer];
    [peer connect];
}

@end
