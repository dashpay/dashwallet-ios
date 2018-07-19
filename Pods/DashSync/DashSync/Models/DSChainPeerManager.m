//
//  DSChainPeerManager.m
//  DashSync
//
//  Created by Aaron Voisine on 10/6/13.
//  Copyright (c) 2013 Aaron Voisine <voisine@gmail.com>
//  Updated by Quantum Explorer on 05/11/18.
//  Copyright (c) 2018 Quantum Explorer <quantum@dash.org>
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

#import "DSChainPeerManager.h"
#import "DSPeer.h"
#import "DSPeerEntity+CoreDataClass.h"
#import "DSBloomFilter.h"
#import "DSTransaction.h"
#import "DSTransactionEntity+CoreDataClass.h"
#import "DSMerkleBlock.h"
#import "DSMerkleBlockEntity+CoreDataClass.h"
#import "DSWalletManager.h"
#import "NSString+Bitcoin.h"
#import "NSData+Bitcoin.h"
#import "NSManagedObject+Sugar.h"
#import "DSEventManager.h"
#import "DSChain.h"
#import "DSSpork.h"
#import "DSSporkManager.h"
#import "DSChainEntity+CoreDataClass.h"
#import <netdb.h>
#import "DSDerivationPath.h"
#import "DSAccount.h"
#import "DSOptionsManager.h"
#import "DSMasternodeManager.h"
#import "DSGovernanceSyncManager.h"
#import "DSGovernanceObject.h"
#import "DSGovernanceVote.h"

#define PEER_LOGGING 1

#if ! PEER_LOGGING
#define NSLog(...)
#endif

#define SYNC_STARTHEIGHT_KEY @"SYNC_STARTHEIGHT"

#define TESTNET_DNS_SEEDS @[@"test.dnsseed.masternode.io",@"testnet-seed.dashdot.io"]

#define MAINNET_DNS_SEEDS @[@"dnsseed.dashpay.io",@"dnsseed.masternode.io",@"dnsseed.dashdot.io"]


#define FIXED_PEERS          @"FixedPeers"
#define PROTOCOL_TIMEOUT     20.0
#define MAX_CONNECT_FAILURES 20 // notify user of network problems after this many connect failures in a row

#define SYNC_COUNT_INFO @"SYNC_COUNT_INFO"

@interface DSChainPeerManager ()

@property (nonatomic, strong) NSMutableOrderedSet *peers;
@property (nonatomic, strong) NSMutableDictionary *txRelays, *txRequests;
@property (nonatomic, strong) NSMutableSet *connectedPeers, *misbehavinPeers, *nonFpTx;
@property (nonatomic, strong) DSPeer *downloadPeer, *fixedPeer;
@property (nonatomic, assign) double fpRate;
@property (nonatomic, assign) NSUInteger taskId, connectFailures, misbehavinCount, maxConnectCount;
@property (nonatomic, assign) NSTimeInterval lastRelayTime;
@property (nonatomic, strong) dispatch_queue_t q;
@property (nonatomic, strong) id backgroundObserver, walletAddedObserver;
@property (nonatomic, assign) uint32_t syncStartHeight, filterUpdateHeight;
@property (nonatomic, strong) NSMutableDictionary *publishedTx, *publishedCallback;
@property (nonatomic, strong) DSBloomFilter *bloomFilter;
@property (nonatomic, strong) DSChain * chain;
@property (nonatomic, strong) DSSporkManager * sporkManager;
@property (nonatomic, strong) DSMasternodeManager * masternodeManager;
@property (nonatomic, strong) DSGovernanceSyncManager * governanceSyncManager;

@end

@implementation DSChainPeerManager

- (instancetype)initWithChain:(DSChain*)chain
{
    if (! (self = [super init])) return nil;
    
    self.chain = chain;
    self.sporkManager = [[DSSporkManager alloc] initWithChain:chain];
    self.masternodeManager = [[DSMasternodeManager alloc] initWithChain:chain];
    self.governanceSyncManager = [[DSGovernanceSyncManager alloc] initWithChain:chain];
    self.connectedPeers = [NSMutableSet set];
    self.txRelays = [NSMutableDictionary dictionary];
    self.txRequests = [NSMutableDictionary dictionary];
    self.publishedTx = [NSMutableDictionary dictionary];
    self.publishedCallback = [NSMutableDictionary dictionary];
    self.misbehavinPeers = [NSMutableSet set];
    self.nonFpTx = [NSMutableSet set];
    self.taskId = UIBackgroundTaskInvalid;
    self.q = dispatch_queue_create("org.dashcore.dashsync.peermanager", DISPATCH_QUEUE_SERIAL);
    self.maxConnectCount = PEER_MAX_CONNECTIONS;
    
    self.backgroundObserver =
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil
                                                       queue:nil usingBlock:^(NSNotification *note) {
                                                           [self savePeers];
                                                           [self.chain saveBlocks];
                                                           
                                                           if (self.taskId == UIBackgroundTaskInvalid) {
                                                               self.misbehavinCount = 0;
                                                               [self.connectedPeers makeObjectsPerformSelector:@selector(disconnect)];
                                                           }
                                                       }];
    
    self.walletAddedObserver =
    [[NSNotificationCenter defaultCenter] addObserverForName:DSChainWalletsDidChangeNotification object:nil
                                                       queue:nil usingBlock:^(NSNotification *note) {
                                                           //[[self.connectedPeers copy] makeObjectsPerformSelector:@selector(disconnect)];
                                                       }];
    
    return self;
}

- (void)dealloc
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    if (self.backgroundObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.backgroundObserver];
    if (self.walletAddedObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.walletAddedObserver];
}

// MARK: - Info

- (double)syncProgress
{
    if (! self.downloadPeer && self.syncStartHeight == 0) return 0.0;
    if (self.downloadPeer.status != DSPeerStatus_Connected) return 0.05;
    if (self.chain.lastBlockHeight >= self.chain.estimatedBlockHeight) return 1.0;
    return 0.1 + 0.9*(self.chain.lastBlockHeight - self.syncStartHeight)/(self.chain.estimatedBlockHeight - self.syncStartHeight);
}

// number of connected peers
- (NSUInteger)peerCount
{
    NSUInteger count = 0;
    
    for (DSPeer *peer in [self.connectedPeers copy]) {
        if (peer.status == DSPeerStatus_Connected) count++;
    }
    
    return count;
}

- (NSString *)downloadPeerName
{
    return [self.downloadPeer.host stringByAppendingFormat:@":%d", self.downloadPeer.port];
}

-(NSArray*)dnsSeeds {
    switch (self.chain.chainType) {
        case DSChainType_MainNet:
            return MAINNET_DNS_SEEDS;
            break;
        case DSChainType_TestNet:
            return TESTNET_DNS_SEEDS;
            break;
        case DSChainType_DevNet:
            return nil; //no dns seeds for devnets
            break;
        default:
            break;
    }
    return nil;
}

// MARK: - Peers

-(void)clearPeers {
    [self disconnect];
    _peers = nil;
}

- (NSMutableOrderedSet *)peers
{
    if (_fixedPeer) return [NSMutableOrderedSet orderedSetWithObject:_fixedPeer];
    if (_peers.count >= _maxConnectCount) return _peers;
    
    @synchronized(self) {
        if (_peers.count >= _maxConnectCount) return _peers;
        _peers = [NSMutableOrderedSet orderedSet];
        
        [[DSPeerEntity context] performBlockAndWait:^{
            for (DSPeerEntity *e in [DSPeerEntity objectsMatching:@"chain == %@",self.chain.chainEntity]) {
                @autoreleasepool {
                    if (e.misbehavin == 0) [self->_peers addObject:[e peer]];
                    else [self.misbehavinPeers addObject:[e peer]];
                }
            }
        }];
        
        [self sortPeers];
        
        if ([self.chain isDevnetAny]) {
            
            [_peers addObjectsFromArray:[self registeredDevnetPeers]];
            
            [self sortPeers];
            return _peers;
        }
        
        // DNS peer discovery
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        NSMutableArray *peers = [NSMutableArray arrayWithObject:[NSMutableArray array]];
        NSArray * dnsSeeds = [self dnsSeeds];
        if (_peers.count < PEER_MAX_CONNECTIONS || ((DSPeer *)_peers[PEER_MAX_CONNECTIONS - 1]).timestamp + 3*24*60*60 < now) {
            while (peers.count < dnsSeeds.count) [peers addObject:[NSMutableArray array]];
        }
        
        if (peers.count > 0) {
            dispatch_apply(peers.count, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t i) {
                NSString *servname = @(self.chain.standardPort).stringValue;
                struct addrinfo hints = { 0, AF_UNSPEC, SOCK_STREAM, 0, 0, 0, NULL, NULL }, *servinfo, *p;
                UInt128 addr = { .u32 = { 0, 0, CFSwapInt32HostToBig(0xffff), 0 } };
                
                NSLog(@"DNS lookup %@", [dnsSeeds objectAtIndex:i]);
                NSString * dnsSeed = [dnsSeeds objectAtIndex:i];
                
                if (getaddrinfo([dnsSeed UTF8String], servname.UTF8String, &hints, &servinfo) == 0) {
                    for (p = servinfo; p != NULL; p = p->ai_next) {
                        if (p->ai_family == AF_INET) {
                            addr.u64[0] = 0;
                            addr.u32[2] = CFSwapInt32HostToBig(0xffff);
                            addr.u32[3] = ((struct sockaddr_in *)p->ai_addr)->sin_addr.s_addr;
                        }
                        //                        else if (p->ai_family == AF_INET6) {
                        //                            addr = *(UInt128 *)&((struct sockaddr_in6 *)p->ai_addr)->sin6_addr;
                        //                        }
                        else continue;
                        
                        uint16_t port = CFSwapInt16BigToHost(((struct sockaddr_in *)p->ai_addr)->sin_port);
                        NSTimeInterval age = 3*24*60*60 + arc4random_uniform(4*24*60*60); // add between 3 and 7 days
                        
                        [peers[i] addObject:[[DSPeer alloc] initWithAddress:addr port:port onChain:self.chain
                                                                  timestamp:(i > 0 ? now - age : now)
                                                                   services:SERVICES_NODE_NETWORK | SERVICES_NODE_BLOOM]];
                    }
                    
                    freeaddrinfo(servinfo);
                } else {
                    NSLog(@"failed getaddrinfo for %@", dnsSeeds[i]);
                }
            });
            
            for (NSArray *a in peers) [_peers addObjectsFromArray:a];
            
            if (![self.chain isMainnet]) {
                [self sortPeers];
                return _peers;
            }
            
            // if DNS peer discovery fails, fall back on a hard coded list of peers (list taken from satoshi client)
            if (_peers.count < PEER_MAX_CONNECTIONS) {
                UInt128 addr = { .u32 = { 0, 0, CFSwapInt32HostToBig(0xffff), 0 } };
                
                NSString *bundlePath = [[NSBundle bundleForClass:self.class] pathForResource:@"DashSync" ofType:@"bundle"];
                NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
                for (NSNumber *address in [NSArray arrayWithContentsOfFile:[bundle pathForResource:FIXED_PEERS ofType:@"plist"]]) {
                    // give hard coded peers a timestamp between 7 and 14 days ago
                    addr.u32[3] = CFSwapInt32HostToBig(address.unsignedIntValue);
                    [_peers addObject:[[DSPeer alloc] initWithAddress:addr port:self.chain.standardPort onChain:self.chain
                                                            timestamp:now - (7*24*60*60 + arc4random_uniform(7*24*60*60))
                                                             services:SERVICES_NODE_NETWORK | SERVICES_NODE_BLOOM]];
                }
            }
            
            [self sortPeers];
        }
        
        return _peers;
    }
}


- (void)changeCurrentPeers {
    for (DSPeer *p in self.connectedPeers) {
        p.priority--;
        NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier: NSCalendarIdentifierGregorian];
        p.lowPreferenceTill = [[calendar dateByAddingUnit:NSCalendarUnitDay value:5 toDate:[NSDate date] options:0] timeIntervalSince1970];
    }
}

- (void)peerMisbehavin:(DSPeer *)peer
{
    peer.misbehavin++;
    [self.peers removeObject:peer];
    [self.misbehavinPeers addObject:peer];
    
    if (++self.misbehavinCount >= 10) { // clear out stored peers so we get a fresh list from DNS for next connect
        self.misbehavinCount = 0;
        [self.misbehavinPeers removeAllObjects];
        [DSPeerEntity deleteAllObjects];
        _peers = nil;
    }
    
    [peer disconnect];
    [self connect];
}

- (void)sortPeers
{
    NSTimeInterval threeHoursAgo = [[NSDate date] timeIntervalSince1970] - 10800;
    BOOL syncsMasternodeList = !!([[DSOptionsManager sharedInstance] syncType] & DSSyncType_MasternodeList);
    BOOL syncsGovernanceObjects = !!([[DSOptionsManager sharedInstance] syncType] & DSSyncType_Governance);
    [_peers sortUsingComparator:^NSComparisonResult(DSPeer *p1, DSPeer *p2) {
        //the following is to make sure we get
        if (syncsMasternodeList) {
            if ((!p1.lastRequestedMasternodeList || p1.lastRequestedMasternodeList < threeHoursAgo) && p2.lastRequestedMasternodeList > threeHoursAgo) return NSOrderedDescending;
            if (p1.lastRequestedMasternodeList > threeHoursAgo && (!p2.lastRequestedMasternodeList || p2.lastRequestedMasternodeList < threeHoursAgo)) return NSOrderedAscending;
        }
        if (syncsGovernanceObjects) {
            if ((!p1.lastRequestedGovernanceSync || p1.lastRequestedGovernanceSync < threeHoursAgo) && p2.lastRequestedGovernanceSync > threeHoursAgo) return NSOrderedDescending;
            if (p1.lastRequestedGovernanceSync > threeHoursAgo && (!p2.lastRequestedGovernanceSync || p2.lastRequestedGovernanceSync < threeHoursAgo)) return NSOrderedAscending;
        }
        if (p1.priority > p2.priority) return NSOrderedAscending;
        if (p1.priority < p2.priority) return NSOrderedDescending;
        if (p1.timestamp > p2.timestamp) return NSOrderedAscending;
        if (p1.timestamp < p2.timestamp) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    //    for (DSPeer * peer in _peers) {
    //        NSLog(@"%@:%d lastRequestedMasternodeList(%f) lastRequestedGovernanceSync(%f)",peer.host,peer.port,peer.lastRequestedMasternodeList, peer.lastRequestedGovernanceSync);
    //    }
    NSLog(@"peers sorted");
}

- (void)savePeers
{
    NSLog(@"[DSChainPeerManager] save peers");
    NSMutableSet *peers = [[self.peers.set setByAddingObjectsFromSet:self.misbehavinPeers] mutableCopy];
    NSMutableSet *addrs = [NSMutableSet set];
    
    for (DSPeer *p in peers) {
        if (p.address.u64[0] != 0 || p.address.u32[2] != CFSwapInt32HostToBig(0xffff)) continue; // skip IPv6 for now
        [addrs addObject:@(CFSwapInt32BigToHost(p.address.u32[3]))];
    }
    
    [[DSPeerEntity context] performBlock:^{
        [DSPeerEntity deleteObjects:[DSPeerEntity objectsMatching:@"! (address in %@)", addrs]]; // remove deleted peers
        
        for (DSPeerEntity *e in [DSPeerEntity objectsMatching:@"address in %@", addrs]) { // update existing peers
            @autoreleasepool {
                DSPeer *p = [peers member:[e peer]];
                
                if (p) {
                    e.timestamp = p.timestamp;
                    e.services = p.services;
                    e.misbehavin = p.misbehavin;
                    e.priority = p.priority;
                    e.lowPreferenceTill = p.lowPreferenceTill;
                    e.lastRequestedMasternodeList = p.lastRequestedMasternodeList;
                    e.lastRequestedGovernanceSync = p.lastRequestedGovernanceSync;
                    [peers removeObject:p];
                }
                else [e deleteObject];
            }
        }
        
        for (DSPeer *p in peers) {
            @autoreleasepool {
                [[DSPeerEntity managedObject] setAttributesFromPeer:p]; // add new peers
            }
        }
    }];
}

-(void)savePeer:(DSPeer*)peer
{
    [[DSPeerEntity context] performBlock:^{
        NSArray * peerEntities = [DSPeerEntity objectsMatching:@"address == %@", @(CFSwapInt32BigToHost(peer.address.u32[3]))];
        if ([peerEntities count]) {
            DSPeerEntity * e = [peerEntities firstObject];
            
            @autoreleasepool {
                e.timestamp = peer.timestamp;
                e.services = peer.services;
                e.misbehavin = peer.misbehavin;
                e.priority = peer.priority;
                e.lowPreferenceTill = peer.lowPreferenceTill;
                e.lastRequestedMasternodeList = peer.lastRequestedMasternodeList;
                e.lastRequestedGovernanceSync = peer.lastRequestedGovernanceSync;
            }
        } else {
            @autoreleasepool {
                [[DSPeerEntity managedObject] setAttributesFromPeer:peer]; // add new peers
            }
        }
    }];
}

// MARK: - Peer Registration

-(void)clearRegisteredPeers {
    [self clearPeers];
    setKeychainArray(@[], self.chain.registeredPeersKey, NO);
}

-(void)registerPeerAtLocation:(UInt128)IPAddress port:(uint32_t)port {
    NSError * error = nil;
    NSMutableArray * registeredPeersArray = [getKeychainArray(self.chain.registeredPeersKey, &error) mutableCopy];
    if (!registeredPeersArray) registeredPeersArray = [NSMutableArray array];
    NSDictionary * insertDictionary = @{@"address":[NSData dataWithUInt128:IPAddress],@"port":@(port)};
    BOOL found = FALSE;
    for (NSDictionary * dictionary in registeredPeersArray) {
        if ([dictionary isEqualToDictionary:insertDictionary]) {
            found = TRUE;
            break;
        }
    }
    if (!found) {
        [registeredPeersArray addObject:insertDictionary];
    }
    setKeychainArray(registeredPeersArray, self.chain.registeredPeersKey, NO);
}


-(NSArray*)registeredDevnetPeers {
    NSError * error = nil;
    NSMutableArray * registeredPeersArray = [getKeychainArray(self.chain.registeredPeersKey, &error) mutableCopy];
    if (error) return @[];
    NSMutableArray * registeredPeers = [NSMutableArray array];
    for (NSDictionary * peerDictionary in registeredPeersArray) {
        UInt128 ipAddress = *(UInt128*)((NSData*)peerDictionary[@"address"]).bytes;
        uint16_t port = [peerDictionary[@"port"] unsignedShortValue];
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        [registeredPeers addObject:[[DSPeer alloc] initWithAddress:ipAddress port:port onChain:self.chain timestamp:now - (7*24*60*60 + arc4random_uniform(7*24*60*60)) services:SERVICES_NODE_NETWORK | SERVICES_NODE_BLOOM]];
    }
    return [registeredPeers copy];
}

-(NSArray*)registeredDevnetPeerServices {
    NSArray * registeredDevnetPeers = [self registeredDevnetPeers];
    NSMutableArray * registeredDevnetPeerServicesArray = [NSMutableArray array];
    for (DSPeer * peer in registeredDevnetPeers) {
        if (!uint128_is_zero(peer.address)) {
            [registeredDevnetPeerServicesArray addObject:[NSString stringWithFormat:@"%@:%hu",peer.host,peer.port]];
        }
    }
    return [registeredDevnetPeerServicesArray copy];
}

// MARK: - Connectivity

- (void)connect
{
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    
    dispatch_async(self.q, ^{
        
        if ([self.chain syncsBlockchain] && ![self.chain canConstructAFilter]) return; // check to make sure the wallet has been created if only are a basic wallet with no dash features
        if (self.connectFailures >= MAX_CONNECT_FAILURES) self.connectFailures = 0; // this attempt is a manual retry
        
        if (self.syncProgress < 1.0) {
            if (self.syncStartHeight == 0) self.syncStartHeight = (uint32_t)[defs integerForKey:SYNC_STARTHEIGHT_KEY];
            
            if (self.syncStartHeight == 0) {
                self.syncStartHeight = self.chain.lastBlockHeight;
                [[NSUserDefaults standardUserDefaults] setInteger:self.syncStartHeight forKey:SYNC_STARTHEIGHT_KEY];
            }
            
            if (self.taskId == UIBackgroundTaskInvalid) { // start a background task for the chain sync
                self.taskId = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
                    dispatch_async(self.q, ^{
                        [self.chain saveBlocks];
                    });
                    
                    [self syncStopped];
                }];
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:DSChainPeerManagerSyncStartedNotification
                                                                    object:self userInfo:@{DSChainPeerManagerNotificationChainKey:self.chain}];
            });
        }
        
        [self.connectedPeers minusSet:[self.connectedPeers objectsPassingTest:^BOOL(id obj, BOOL *stop) {
            return ([obj status] == DSPeerStatus_Disconnected) ? YES : NO;
        }]];
        
        self.fixedPeer = [DSPeer peerWithHost:[defs stringForKey:SETTINGS_FIXED_PEER_KEY] onChain:self.chain];
        self.maxConnectCount = (self.fixedPeer) ? 1 : PEER_MAX_CONNECTIONS;
        if (self.connectedPeers.count >= self.maxConnectCount) return; // already connected to maxConnectCount peers
        
        NSMutableOrderedSet *peers = [NSMutableOrderedSet orderedSetWithOrderedSet:self.peers];
        
        if (peers.count > 100) [peers removeObjectsInRange:NSMakeRange(100, peers.count - 100)];
        
        while (peers.count > 0 && self.connectedPeers.count < self.maxConnectCount) {
            // pick a random peer biased towards peers with more recent timestamps
            DSPeer *p = peers[(NSUInteger)(pow(arc4random_uniform((uint32_t)peers.count), 2)/peers.count)];
            
            if (p && ! [self.connectedPeers containsObject:p]) {
                [p setDelegate:self queue:self.q];
                p.earliestKeyTime = self.chain.earliestWalletCreationTime;
                [self.connectedPeers addObject:p];
                [p connect];
            }
            
            [peers removeObject:p];
        }
        
        if (self.connectedPeers.count == 0) {
            [self syncStopped];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                NSError *error = [NSError errorWithDomain:@"DashWallet" code:1
                                                 userInfo:@{NSLocalizedDescriptionKey:NSLocalizedString(@"no peers found", nil)}];
                
                [[NSNotificationCenter defaultCenter] postNotificationName:DSChainPeerManagerSyncFailedNotification
                                                                    object:nil userInfo:@{@"error":error,DSChainPeerManagerNotificationChainKey:self.chain}];
            });
        }
    });
}

- (void)disconnect
{
    for (DSPeer *peer in self.connectedPeers) {
        self.connectFailures = MAX_CONNECT_FAILURES; // prevent futher automatic reconnect attempts
        [peer disconnect];
    }
}

- (void)syncTimeout
{
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    
    if (now - self.lastRelayTime < PROTOCOL_TIMEOUT) { // the download peer relayed something in time, so restart timer
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(syncTimeout) object:nil];
        [self performSelector:@selector(syncTimeout) withObject:nil
                   afterDelay:PROTOCOL_TIMEOUT - (now - self.lastRelayTime)];
        return;
    }
    
    dispatch_async(self.q, ^{
        if (! self.downloadPeer) return;
        NSLog(@"%@:%d chain sync timed out", self.downloadPeer.host, self.downloadPeer.port);
        [self.peers removeObject:self.downloadPeer];
        [self.downloadPeer disconnect];
    });
}

- (void)syncStopped
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(syncTimeout) object:nil];
        
        if (self.taskId != UIBackgroundTaskInvalid) {
            [[UIApplication sharedApplication] endBackgroundTask:self.taskId];
            self.taskId = UIBackgroundTaskInvalid;
        }
    });
}


// MARK: - Blockchain Sync

// rescans blocks and transactions after earliestKeyTime, a new random download peer is also selected due to the
// possibility that a malicious node might lie by omitting transactions that match the bloom filter
- (void)rescan
{
    if (! self.connected) return;
    
    dispatch_async(self.q, ^{
        [self.chain setLastBlockHeightForRescan];
        
        if (self.downloadPeer) { // disconnect the current download peer so a new random one will be selected
            [self.peers removeObject:self.downloadPeer];
            [self.downloadPeer disconnect];
        }
        
        self.syncStartHeight = self.chain.lastBlockHeight;
        [[NSUserDefaults standardUserDefaults] setInteger:self.syncStartHeight forKey:SYNC_STARTHEIGHT_KEY];
        [self connect];
    });
}

// MARK: - Blockchain Transactions

// adds transaction to list of tx to be published, along with any unconfirmed inputs
- (void)addTransactionToPublishList:(DSTransaction *)transaction
{
    if (transaction.blockHeight == TX_UNCONFIRMED) {
        NSLog(@"[DSChainPeerManager] add transaction to publish list %@", transaction);
        self.publishedTx[uint256_obj(transaction.txHash)] = transaction;
        
        for (NSValue *hash in transaction.inputHashes) {
            UInt256 h = UINT256_ZERO;
            
            [hash getValue:&h];
            [self addTransactionToPublishList:[self.chain transactionForHash:h]];
        }
    }
}

- (void)publishTransaction:(DSTransaction *)transaction completion:(void (^)(NSError *error))completion
{
    NSLog(@"[DSChainPeerManager] publish transaction %@", transaction);
    if (! transaction.isSigned) {
        if (completion) {
            [[DSEventManager sharedEventManager] saveEvent:@"peer_manager:not_signed"];
            completion([NSError errorWithDomain:@"DashWallet" code:401 userInfo:@{NSLocalizedDescriptionKey:
                                                                                      NSLocalizedString(@"dash transaction not signed", nil)}]);
        }
        
        return;
    }
    else if (! self.connected && self.connectFailures >= MAX_CONNECT_FAILURES) {
        if (completion) {
            [[DSEventManager sharedEventManager] saveEvent:@"peer_manager:not_connected"];
            completion([NSError errorWithDomain:@"DashWallet" code:-1009 userInfo:@{NSLocalizedDescriptionKey:
                                                                                        NSLocalizedString(@"not connected to the dash network", nil)}]);
        }
        
        return;
    }
    
    NSMutableSet *peers = [NSMutableSet setWithSet:self.connectedPeers];
    NSValue *hash = uint256_obj(transaction.txHash);
    
    [self addTransactionToPublishList:transaction];
    if (completion) self.publishedCallback[hash] = completion;
    
    NSArray *txHashes = self.publishedTx.allKeys;
    
    // instead of publishing to all peers, leave out the download peer to see if the tx propogates and gets relayed back
    // TODO: XXX connect to a random peer with an empty or fake bloom filter just for publishing
    if (self.peerCount > 1 && self.downloadPeer) [peers removeObject:self.downloadPeer];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self performSelector:@selector(txTimeout:) withObject:hash afterDelay:PROTOCOL_TIMEOUT];
        
        for (DSPeer *p in peers) {
            if (p.status != DSPeerStatus_Connected) continue;
            [p sendInvMessageWithTxHashes:txHashes];
            [p sendPingMessageWithPongHandler:^(BOOL success) {
                if (! success) return;
                
                for (NSValue *h in txHashes) {
                    if ([self.txRelays[h] containsObject:p] || [self.txRequests[h] containsObject:p]) continue;
                    if (! self.txRequests[h]) self.txRequests[h] = [NSMutableSet set];
                    [self.txRequests[h] addObject:p];
                    [p sendGetdataMessageWithTxHashes:@[h] andBlockHashes:nil];
                }
            }];
        }
    });
}


// unconfirmed transactions that aren't in the mempools of any of connected peers have likely dropped off the network
- (void)removeUnrelayedTransactions
{
    BOOL rescan = NO, notify = NO;
    NSValue *hash;
    UInt256 h;
    
    // don't remove transactions until we're connected to maxConnectCount peers
    if (self.peerCount < self.maxConnectCount) return;
    
    for (DSPeer *p in self.connectedPeers) { // don't remove tx until all peers have finished relaying their mempools
        if (! p.synced) return;
    }
    
    for (DSWallet * wallet in self.chain.wallets) {
        for (DSAccount * account in wallet.accounts) {
            for (DSTransaction *transaction in account.allTransactions) {
                if (transaction.blockHeight != TX_UNCONFIRMED) break;
                hash = uint256_obj(transaction.txHash);
                if (self.publishedCallback[hash] != NULL) continue;
                
                if ([self.txRelays[hash] count] == 0 && [self.txRequests[hash] count] == 0) {
                    // if this is for a transaction we sent, and it wasn't already known to be invalid, notify user of failure
                    if (! rescan && [account amountSentByTransaction:transaction] > 0 && [account transactionIsValid:transaction]) {
                        NSLog(@"failed transaction %@", transaction);
                        rescan = notify = YES;
                        
                        for (NSValue *hash in transaction.inputHashes) { // only recommend a rescan if all inputs are confirmed
                            [hash getValue:&h];
                            if ([wallet transactionForHash:h].blockHeight != TX_UNCONFIRMED) continue;
                            rescan = NO;
                            break;
                        }
                    }
                    
                    [account removeTransaction:transaction.txHash];
                }
                else if ([self.txRelays[hash] count] < self.maxConnectCount) {
                    // set timestamp 0 to mark as unverified
                    [self.chain setBlockHeight:TX_UNCONFIRMED andTimestamp:0 forTxHashes:@[hash]];
                }
            }
        }
    }
    
    if (notify) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (rescan) {
                [[DSEventManager sharedEventManager] saveEvent:@"peer_manager:tx_rejected_rescan"];
                UIAlertController * alert = [UIAlertController
                                             alertControllerWithTitle:NSLocalizedString(@"transaction rejected", nil)
                                             message:NSLocalizedString(@"Your wallet may be out of sync.\n"
                                                                       "This can often be fixed by rescanning the blockchain.", nil)
                                             preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction* cancelButton = [UIAlertAction
                                               actionWithTitle:NSLocalizedString(@"cancel", nil)
                                               style:UIAlertActionStyleCancel
                                               handler:^(UIAlertAction * action) {
                                               }];
                UIAlertAction* rescanButton = [UIAlertAction
                                               actionWithTitle:NSLocalizedString(@"rescan", nil)
                                               style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction * action) {
                                                   [self rescan];
                                               }];
                [alert addAction:cancelButton];
                [alert addAction:rescanButton];
                [[[[UIApplication sharedApplication] keyWindow] rootViewController] presentViewController:alert animated:YES completion:nil];
                
            }
            else {
                [[DSEventManager sharedEventManager] saveEvent:@"peer_manager_tx_rejected"];
                UIAlertController * alert = [UIAlertController
                                             alertControllerWithTitle:NSLocalizedString(@"transaction rejected", nil)
                                             message:@""
                                             preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction* okButton = [UIAlertAction
                                           actionWithTitle:NSLocalizedString(@"ok", nil)
                                           style:UIAlertActionStyleCancel
                                           handler:^(UIAlertAction * action) {
                                           }];
                [alert addAction:okButton];
                [[[[UIApplication sharedApplication] keyWindow] rootViewController] presentViewController:alert animated:YES completion:nil];
            }
        });
    }
}

// number of connected peers that have relayed the transaction
- (NSUInteger)relayCountForTransaction:(UInt256)txHash
{
    return [self.txRelays[uint256_obj(txHash)] count];
}

- (void)txTimeout:(NSValue *)txHash
{
    void (^callback)(NSError *error) = self.publishedCallback[txHash];
    
    [self.publishedTx removeObjectForKey:txHash];
    [self.publishedCallback removeObjectForKey:txHash];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(txTimeout:) object:txHash];
    
    if (callback) {
        [[DSEventManager sharedEventManager] saveEvent:@"peer_manager:tx_canceled_timeout"];
        callback([NSError errorWithDomain:@"DashWallet" code:BITCOIN_TIMEOUT_CODE userInfo:@{NSLocalizedDescriptionKey:
                                                                                                 NSLocalizedString(@"transaction canceled, network timeout", nil)}]);
    }
}

// MARK: - Mempools Sync

- (void)loadMempools
{
    if (!([[DSOptionsManager sharedInstance] syncType] & DSSyncType_Mempools)) return; // make sure we care about sporks
    for (DSPeer *p in self.connectedPeers) { // after syncing, load filters and get mempools from other peers
        if (p.status != DSPeerStatus_Connected) continue;
        
        if ([self.chain canConstructAFilter] && (p != self.downloadPeer || self.fpRate > BLOOM_REDUCED_FALSEPOSITIVE_RATE*5.0)) {
            [p sendFilterloadMessage:[self bloomFilterForPeer:p].data];
        }
        
        [p sendInvMessageWithTxHashes:self.publishedCallback.allKeys]; // publish pending tx
        [p sendPingMessageWithPongHandler:^(BOOL success) {
            if (success) {
                [p sendMempoolMessage:self.publishedTx.allKeys completion:^(BOOL success) {
                    if (success) {
                        p.synced = YES;
                        [self removeUnrelayedTransactions];
                        [p sendGetaddrMessage]; // request a list of other bitcoin peers
                        
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [[NSNotificationCenter defaultCenter]
                             postNotificationName:DSChainPeerManagerTxStatusNotification object:self userInfo:@{DSChainPeerManagerNotificationChainKey:self.chain}];
                        });
                    }
                    
                    if (p == self.downloadPeer) {
                        [self syncStopped];
                        
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [[NSNotificationCenter defaultCenter]
                             postNotificationName:DSChainPeerManagerSyncFinishedNotification object:self userInfo:@{DSChainPeerManagerNotificationChainKey:self.chain}];
                        });
                    }
                }];
            }
            else if (p == self.downloadPeer) {
                [self syncStopped];
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[NSNotificationCenter defaultCenter]
                     postNotificationName:DSChainPeerManagerSyncFinishedNotification object:self userInfo:@{DSChainPeerManagerNotificationChainKey:self.chain}];
                });
            }
        }];
    }
}

// MARK: - Spork Sync

-(void)getSporks {
    if (!([[DSOptionsManager sharedInstance] syncType] & DSSyncType_Sporks)) return; // make sure we care about sporks
    for (DSPeer *p in self.connectedPeers) { // after syncing, get sporks from other peers
        if (p.status != DSPeerStatus_Connected) continue;
        
        [p sendPingMessageWithPongHandler:^(BOOL success) {
            if (success) {
                [p sendGetSporks];
            }
        }];
    }
}

// MARK: - Governance Sync

-(void)continueGovernanceSync {
    NSLog(@"--> Continuing Governance Sync");
    NSUInteger last3HoursStandaloneBroadcastHashesCount = [self.governanceSyncManager last3HoursStandaloneGovernanceObjectHashesCount];
    if (last3HoursStandaloneBroadcastHashesCount) {
        DSPeer * downloadPeer = nil;
        
        //find download peer (ie the peer that we will ask for governance objects from
        for (DSPeer * peer in self.connectedPeers) {
            if (peer.status != DSPeerStatus_Connected) continue;
            downloadPeer = peer;
            break;
        }
        
        if (downloadPeer) {
            downloadPeer.governanceRequestState = DSGovernanceRequestState_GovernanceObjects; //force this by bypassing normal route
            
            [self.governanceSyncManager requestGovernanceObjectsFromPeer:downloadPeer];
        }
    } else {
        if (!([[DSOptionsManager sharedInstance] syncType] & DSSyncType_GovernanceVotes)) return; // make sure we care about Governance objects
        DSPeer * downloadPeer = nil;
        //find download peer (ie the peer that we will ask for governance objects from
        for (DSPeer * peer in self.connectedPeers) {
            if (peer.status != DSPeerStatus_Connected) continue;
            downloadPeer = peer;
            break;
        }
        
        if (downloadPeer) {
            downloadPeer.governanceRequestState = DSGovernanceRequestState_GovernanceObjects; //force this by bypassing normal route
            
            //we will request governance objects
            //however since governance objects are all accounted for
            //and we want votes, then votes will be requested instead for each governance object
            [self.governanceSyncManager requestGovernanceObjectsFromPeer:downloadPeer];
        }
    }
}


-(void)startGovernanceSync {
    
    //Do we want to sync?
    if (!([[DSOptionsManager sharedInstance] syncType] & DSSyncType_Governance)) return; // make sure we care about Governance objects
    
    //Do we need to sync?
    if ([[NSUserDefaults standardUserDefaults] objectForKey:[NSString stringWithFormat:@"%@-%@",self.chain.uniqueID,LAST_SYNCED_GOVERANCE_OBJECTS]]) { //no need to do a governance sync if we already completed one recently
        NSTimeInterval lastSyncedGovernance = [[NSUserDefaults standardUserDefaults] integerForKey:[NSString stringWithFormat:@"%@-%@",self.chain.uniqueID,LAST_SYNCED_GOVERANCE_OBJECTS]];
        NSTimeInterval interval = [[DSOptionsManager sharedInstance] syncGovernanceObjectsInterval];
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        if (lastSyncedGovernance + interval > now) {
            [self continueGovernanceSync];
            return;
        };
    }
    
    //We need to sync
    NSLog(@"--> Trying to start governance sync");
    NSArray * sortedPeers = [self.connectedPeers sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"lastRequestedGovernanceSync" ascending:YES]]];
    BOOL startedGovernanceSync = FALSE;
    for (DSPeer * peer in sortedPeers) {
        if (peer.status != DSPeerStatus_Connected) continue;
        if ([[NSDate date] timeIntervalSince1970] - peer.lastRequestedGovernanceSync < 10800) {
            NSLog(@"--> Peer recently used");
            continue; //don't request less than every 3 hours from a peer
        }
        peer.lastRequestedGovernanceSync = [[NSDate date] timeIntervalSince1970]; //we are requesting the list from this peer
        [peer sendGovSync];
        [self savePeer:peer];
        startedGovernanceSync = TRUE;
        break;
    }
    if (!startedGovernanceSync) { //we have requested masternode list from connected peers too recently, let's connect to different peers
        [self continueGovernanceSync];
    }
}

-(void)publishProposal:(DSGovernanceObject*)goveranceProposal {
    if (![goveranceProposal isValid]) return;
    [self.downloadPeer sendGovObject:goveranceProposal];
}

-(void)publishVotes:(NSArray<DSGovernanceVote*>*)votes {
    for (DSGovernanceVote * vote in votes) {
        if (![vote isValid]) continue;
        [self.downloadPeer sendGovObjectVote:vote];
    }
}

// MARK: - Masternode List Sync

-(void)continueGettingMasternodeList {
    NSLog(@"--> Continuing Getting MasternodeList");
    NSUInteger last3HoursStandaloneBroadcastHashesCount = [self.masternodeManager last3HoursStandaloneBroadcastHashesCount];
    if (last3HoursStandaloneBroadcastHashesCount) {
        DSPeer * downloadPeer = nil;
        
        //find download peer (ie the peer that we will ask for governance objects from
        for (DSPeer * peer in self.connectedPeers) {
            if (peer.status != DSPeerStatus_Connected) continue;
            downloadPeer = peer;
            break;
        }
        
        [self.masternodeManager requestMasternodeBroadcastsFromPeer:downloadPeer];
    }
}

-(void)getMasternodeList {
    
    //Do we want to sync masternode list?
    if (!([[DSOptionsManager sharedInstance] syncType] & DSSyncType_MasternodeList)) return; // make sure we care about masternode list
    
    if (self.chain.protocolVersion > 70210) { //change to 70210 later
        [self.downloadPeer sendGetMasternodeListFromPreviousBlockHash:self.masternodeManager.baseBlockHash forBlockHash:self.chain.lastBlock.blockHash];
    } else {
        //Do we need to sync the hashes? (or do we already have them?)
        if ([[NSUserDefaults standardUserDefaults] objectForKey:[NSString stringWithFormat:@"%@-%@",self.chain.uniqueID,LAST_SYNCED_MASTERNODE_LIST]]) { //no need to do a governance sync if we already completed one recently
            NSTimeInterval lastSyncedMasternodeList = [[NSUserDefaults standardUserDefaults] integerForKey:[NSString stringWithFormat:@"%@-%@",self.chain.uniqueID,LAST_SYNCED_MASTERNODE_LIST]];
            NSTimeInterval interval = [[DSOptionsManager sharedInstance] syncMasternodeListInterval];
            NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
            if (lastSyncedMasternodeList + interval > now) {
                [self continueGettingMasternodeList];
                return;
            };
        }
        
        NSArray * sortedPeers = [self.connectedPeers sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"lastRequestedMasternodeList" ascending:YES]]];
        BOOL requestedMasternodeList = FALSE;
        for (DSPeer * peer in sortedPeers) {
            if (peer.status != DSPeerStatus_Connected) continue;
            if ([[NSDate date] timeIntervalSince1970] - peer.lastRequestedMasternodeList < 10800) continue; //don't request less than every 3 hours from a peer
            peer.lastRequestedMasternodeList = [[NSDate date] timeIntervalSince1970]; //we are requesting the list from this peer
            DSUTXO emptyUTXO;
            emptyUTXO.hash = UINT256_ZERO;
            emptyUTXO.n = 0;
            [peer sendDSegMessage:emptyUTXO];
            [self savePeer:peer];
            requestedMasternodeList = TRUE;
            break;
        }
        if (!requestedMasternodeList) { //we have requested masternode list from connected peers too recently, let's connect to different peers
            [self continueGettingMasternodeList];
        }
    }
}

// MARK: - Bloom Filters


- (void)updateFilter
{
    if (self.downloadPeer.needsFilterUpdate) return;
    self.downloadPeer.needsFilterUpdate = YES;
    NSLog(@"filter update needed, waiting for pong");
    
    [self.downloadPeer sendPingMessageWithPongHandler:^(BOOL success) { // wait for pong so we include already sent tx
        if (! success) return;
        NSLog(@"updating filter with newly created wallet addresses");
        self->_bloomFilter = nil;
        
        if (self.chain.lastBlockHeight < self.chain.estimatedBlockHeight) { // if we're syncing, only update download peer
            [self.downloadPeer sendFilterloadMessage:[self bloomFilterForPeer:self.downloadPeer].data];
            [self.downloadPeer sendPingMessageWithPongHandler:^(BOOL success) { // wait for pong so filter is loaded
                if (! success) return;
                self.downloadPeer.needsFilterUpdate = NO;
                [self.downloadPeer rerequestBlocksFrom:self.chain.lastBlock.blockHash];
                [self.downloadPeer sendPingMessageWithPongHandler:^(BOOL success) {
                    if (! success || self.downloadPeer.needsFilterUpdate) return;
                    [self.downloadPeer sendGetblocksMessageWithLocators:[self.chain blockLocatorArray]
                                                            andHashStop:UINT256_ZERO];
                }];
            }];
        }
        else {
            for (DSPeer *p in self.connectedPeers) {
                if (p.status != DSPeerStatus_Connected) continue;
                [p sendFilterloadMessage:[self bloomFilterForPeer:p].data];
                [p sendPingMessageWithPongHandler:^(BOOL success) { // wait for pong so we know filter is loaded
                    if (! success) return;
                    p.needsFilterUpdate = NO;
                    [p sendMempoolMessage:self.publishedTx.allKeys completion:nil];
                }];
            }
        }
    }];
}


- (DSBloomFilter *)bloomFilterForPeer:(DSPeer *)peer
{
    NSMutableSet * allAddresses = [NSMutableSet set];
    NSMutableSet * allUTXOs = [NSMutableSet set];
    for (DSWallet * wallet in self.chain.wallets) {
        // every time a new wallet address is added, the bloom filter has to be rebuilt, and each address is only used for
        // one transaction, so here we generate some spare addresses to avoid rebuilding the filter each time a wallet
        // transaction is encountered during the blockchain download
        [wallet registerAddressesWithGapLimit:SEQUENCE_GAP_LIMIT_EXTERNAL + 100 internal:NO];
        [wallet registerAddressesWithGapLimit:SEQUENCE_GAP_LIMIT_INTERNAL + 100 internal:YES];
        NSSet *addresses = [wallet.allReceiveAddresses setByAddingObjectsFromSet:wallet.allChangeAddresses];
        [allAddresses addObjectsFromArray:[addresses allObjects]];
        [allUTXOs addObjectsFromArray:wallet.unspentOutputs];
    }
    
    for (DSDerivationPath * derivationPath in self.chain.standaloneDerivationPaths) {
        [derivationPath registerAddressesWithGapLimit:SEQUENCE_GAP_LIMIT_EXTERNAL + 100 internal:NO];
        [derivationPath registerAddressesWithGapLimit:SEQUENCE_GAP_LIMIT_INTERNAL + 100 internal:YES];
        NSArray *addresses = [derivationPath.allReceiveAddresses arrayByAddingObjectsFromArray:derivationPath.allChangeAddresses];
        [allAddresses addObjectsFromArray:addresses];
    }
    
    
    [self.chain clearOrphans];
    self.filterUpdateHeight = self.chain.lastBlockHeight;
    self.fpRate = BLOOM_REDUCED_FALSEPOSITIVE_RATE;
    
    DSUTXO o;
    NSData *d;
    NSUInteger i, elemCount = allAddresses.count + allUTXOs.count;
    NSMutableArray *inputs = [NSMutableArray new];
    
    for (DSWallet * wallet in self.chain.wallets) {
        for (DSTransaction *tx in wallet.allTransactions) { // find TXOs spent within the last 100 blocks
            [self addTransactionToPublishList:tx]; // also populate the tx publish list
            if (tx.blockHeight != TX_UNCONFIRMED && tx.blockHeight + 100 < self.chain.lastBlockHeight) break;
            i = 0;
            
            for (NSValue *hash in tx.inputHashes) {
                [hash getValue:&o.hash];
                o.n = [tx.inputIndexes[i++] unsignedIntValue];
                
                DSTransaction *t = [wallet transactionForHash:o.hash];
                
                if (o.n < t.outputAddresses.count && [wallet containsAddress:t.outputAddresses[o.n]]) {
                    [inputs addObject:dsutxo_data(o)];
                    elemCount++;
                }
            }
        }
    }
    
    DSBloomFilter *filter = [[DSBloomFilter alloc] initWithFalsePositiveRate:self.fpRate
                                                             forElementCount:(elemCount < 200 ? 300 : elemCount + 100) tweak:(uint32_t)peer.hash
                                                                       flags:BLOOM_UPDATE_ALL];
    
    for (NSString *addr in allAddresses) {// add addresses to watch for tx receiveing money to the wallet
        NSData *hash = addr.addressToHash160;
        
        if (hash && ! [filter containsData:hash]) [filter insertData:hash];
    }
    
    for (NSValue *utxo in allUTXOs) { // add UTXOs to watch for tx sending money from the wallet
        [utxo getValue:&o];
        d = dsutxo_data(o);
        if (! [filter containsData:d]) [filter insertData:d];
    }
    
    for (d in inputs) { // also add TXOs spent within the last 100 blocks
        if (! [filter containsData:d]) [filter insertData:d];
    }
    
    // TODO: XXXX if already synced, recursively add inputs of unconfirmed receives
    _bloomFilter = filter;
    return _bloomFilter;
}

// MARK: - Count Info

-(void)setCount:(uint32_t)count forSyncCountInfo:(DSSyncCountInfo)syncCountInfo {
    //    if (syncCountInfo ==  DSSyncCountInfo_List || syncCountInfo == DSSyncCountInfo_GovernanceObject) {
    //        NSString * storageKey = [NSString stringWithFormat:@"%@_%@_%d",self.chain.uniqueID,SYNC_COUNT_INFO,syncCountInfo];
    //        [[NSUserDefaults standardUserDefaults] setInteger:count forKey:storageKey];
    //        [self.syncCountInfo setObject:@(count) forKey:@(syncCountInfo)];
    //    }
    switch (syncCountInfo) {
        case DSSyncCountInfo_List:
            self.chain.totalMasternodeCount = count;
            [self.chain save];
            break;
        case DSSyncCountInfo_GovernanceObject:
            self.chain.totalGovernanceObjectsCount = count;
            [self.chain save];
            break;
        case DSSyncCountInfo_GovernanceObjectVote:
            self.governanceSyncManager.currentGovernanceSyncObject.totalGovernanceVoteCount = count;
            [self.governanceSyncManager.currentGovernanceSyncObject save];
            break;
        default:
            break;
    }
}

// MARK: - DSPeerDelegate

- (void)peerConnected:(DSPeer *)peer
{
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    
    if (peer.timestamp > now + 2*60*60 || peer.timestamp < now - 2*60*60) peer.timestamp = now; //timestamp sanity check
    self.connectFailures = 0;
    NSLog(@"%@:%d connected with lastblock %d", peer.host, peer.port, peer.lastblock);
    
    // drop peers that don't carry full blocks, or aren't synced yet
    // TODO: XXXX does this work with 0.11 pruned nodes?
    if (! (peer.services & SERVICES_NODE_NETWORK) || peer.lastblock + 10 < self.chain.lastBlockHeight) {
        [peer disconnect];
        return;
    }
    
    // drop peers that don't support SPV filtering
    if (peer.version >= 70206 && ! (peer.services & SERVICES_NODE_BLOOM)) {
        [peer disconnect];
        return;
    }
    
    
    if (self.connected) {
        if (![self.chain syncsBlockchain]) return;
        if (self.chain.estimatedBlockHeight >= peer.lastblock || self.chain.lastBlockHeight >= peer.lastblock) {
            if (self.chain.lastBlockHeight < self.chain.estimatedBlockHeight) {
                NSLog(@"self.chain.lastBlockHeight %u, self.chain.estimatedBlockHeight %u",self.chain.lastBlockHeight,self.chain.estimatedBlockHeight);
                return; // don't load bloom filter yet if we're syncing
            }
            if ([self.chain canConstructAFilter]) {
                [peer sendFilterloadMessage:[self bloomFilterForPeer:peer].data];
                [peer sendInvMessageWithTxHashes:self.publishedCallback.allKeys]; // publish pending tx
            } else {
                [peer sendFilterloadMessage:[DSBloomFilter emptyBloomFilterData]];
            }
            [peer sendPingMessageWithPongHandler:^(BOOL success) {
                if (! success) return;
                [peer sendMempoolMessage:self.publishedTx.allKeys completion:^(BOOL success) {
                    if (! success) return;
                    peer.synced = YES;
                    [self removeUnrelayedTransactions];
                    [peer sendGetaddrMessage]; // request a list of other dash peers
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [[NSNotificationCenter defaultCenter] postNotificationName:DSChainPeerManagerTxStatusNotification
                                                                            object:nil userInfo:@{DSChainPeerManagerNotificationChainKey:self.chain}];
                    });
                }];
            }];
            NSLog(@"a");
            return; // we're already connected to a download peer
        }
    }
    
    
    // select the peer with the lowest ping time to download the chain from if we're behind
    // BUG: XXX a malicious peer can report a higher lastblock to make us select them as the download peer, if two
    // peers agree on lastblock, use one of them instead
    for (DSPeer *p in self.connectedPeers) {
        if (p.status != DSPeerStatus_Connected) continue;
        if ((p.pingTime < peer.pingTime && p.lastblock >= peer.lastblock) || p.lastblock > peer.lastblock) peer = p;
    }
    
    [self.downloadPeer disconnect];
    self.downloadPeer = peer;
    _connected = YES;
    [self.chain setEstimatedBlockHeight:peer.lastblock fromPeer:peer];
    if ([self.chain syncsBlockchain] && [self.chain canConstructAFilter]) {
        [peer sendFilterloadMessage:[self bloomFilterForPeer:peer].data];
    }
    peer.currentBlockHeight = self.chain.lastBlockHeight;
    
    if ([self.chain syncsBlockchain] && (self.chain.lastBlockHeight < peer.lastblock)) { // start blockchain sync
        self.lastRelayTime = 0;
        NSLog(@"b");
        dispatch_async(dispatch_get_main_queue(), ^{ // setup a timer to detect if the sync stalls
            [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(syncTimeout) object:nil];
            [self performSelector:@selector(syncTimeout) withObject:nil afterDelay:PROTOCOL_TIMEOUT];
            
            [[NSNotificationCenter defaultCenter] postNotificationName:DSChainPeerManagerTxStatusNotification object:self userInfo:@{DSChainPeerManagerNotificationChainKey:self.chain}];
            
            dispatch_async(self.q, ^{
                // request just block headers up to a week before earliestKeyTime, and then merkleblocks after that
                // BUG: XXX headers can timeout on slow connections (each message is over 160k)
                BOOL startingDevnetSync = [self.chain isDevnetAny] && self.chain.lastBlock.height < 5;
                if (startingDevnetSync || self.chain.lastBlock.timestamp + 7*24*60*60 >= self.chain.earliestWalletCreationTime + NSTimeIntervalSince1970) {
                    [peer sendGetblocksMessageWithLocators:[self.chain blockLocatorArray] andHashStop:UINT256_ZERO];
                }
                else [peer sendGetheadersMessageWithLocators:[self.chain blockLocatorArray] andHashStop:UINT256_ZERO];
            });
        });
    }
    else { // we're already synced
        NSLog(@"c");
        self.syncStartHeight = 0;
        [[NSUserDefaults standardUserDefaults] setInteger:0 forKey:SYNC_STARTHEIGHT_KEY];
        [self loadMempools];
        [self getSporks];
        [self startGovernanceSync];
        [self getMasternodeList];
    }
}

- (void)peer:(DSPeer *)peer disconnectedWithError:(NSError *)error
{
    NSLog(@"%@:%d disconnected%@%@", peer.host, peer.port, (error ? @", " : @""), (error ? error : @""));
    
    if ([error.domain isEqual:@"DashWallet"] && error.code != BITCOIN_TIMEOUT_CODE) {
        [self peerMisbehavin:peer]; // if it's protocol error other than timeout, the peer isn't following the rules
    }
    else if (error) { // timeout or some non-protocol related network error
        [self.peers removeObject:peer];
        self.connectFailures++;
    }
    
    for (NSValue *txHash in self.txRelays.allKeys) {
        [self.txRelays[txHash] removeObject:peer];
    }
    
    if ([self.downloadPeer isEqual:peer]) { // download peer disconnected
        _connected = NO;
        self.downloadPeer = nil;
        if (self.connectFailures > MAX_CONNECT_FAILURES) self.connectFailures = MAX_CONNECT_FAILURES;
    }
    
    if (! self.connected && self.connectFailures == MAX_CONNECT_FAILURES) {
        [self syncStopped];
        
        // clear out stored peers so we get a fresh list from DNS on next connect attempt
        [self.misbehavinPeers removeAllObjects];
        [DSPeerEntity deleteAllObjects];
        _peers = nil;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:DSChainPeerManagerSyncFailedNotification
                                                                object:nil userInfo:(error) ? @{@"error":error,DSChainPeerManagerNotificationChainKey:self.chain} : @{DSChainPeerManagerNotificationChainKey:self.chain}];
        });
    }
    else if (self.connectFailures < MAX_CONNECT_FAILURES) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.taskId != UIBackgroundTaskInvalid ||
                [UIApplication sharedApplication].applicationState != UIApplicationStateBackground) {
                [self connect]; // try connecting to another peer
            }
        });
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:DSChainPeerManagerTxStatusNotification object:self userInfo:@{DSChainPeerManagerNotificationChainKey:self.chain}];
    });
}

- (void)peer:(DSPeer *)peer relayedPeers:(NSArray *)peers
{
    NSLog(@"%@:%d relayed %d peer(s)", peer.host, peer.port, (int)peers.count);
    [self.peers addObjectsFromArray:peers];
    [self.peers minusSet:self.misbehavinPeers];
    [self sortPeers];
    
    // limit total to 2500 peers
    if (self.peers.count > 2500) [self.peers removeObjectsInRange:NSMakeRange(2500, self.peers.count - 2500)];
    
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    
    // remove peers more than 3 hours old, or until there are only 1000 left
    while (self.peers.count > 1000 && ((DSPeer *)self.peers.lastObject).timestamp + 3*60*60 < now) {
        [self.peers removeObject:self.peers.lastObject];
    }
    
    if (peers.count > 1 && peers.count < 1000) [self savePeers]; // peer relaying is complete when we receive <1000
}

- (void)peer:(DSPeer *)peer relayedTransaction:(DSTransaction *)transaction
{
    NSValue *hash = uint256_obj(transaction.txHash);
    BOOL syncing = (self.chain.lastBlockHeight < self.chain.estimatedBlockHeight);
    void (^callback)(NSError *error) = self.publishedCallback[hash];
    
    NSLog(@"%@:%d relayed transaction %@", peer.host, peer.port, hash);
    
    transaction.timestamp = [NSDate timeIntervalSinceReferenceDate];
    DSAccount * account = [self.chain accountContainingTransaction:transaction];
    if (syncing && !account) return;
    if (![account registerTransaction:transaction]) return;
    if (peer == self.downloadPeer) self.lastRelayTime = [NSDate timeIntervalSinceReferenceDate];
    
    if ([account amountSentByTransaction:transaction] > 0 && [account transactionIsValid:transaction]) {
        [self addTransactionToPublishList:transaction]; // add valid send tx to mempool
    }
    
    // keep track of how many peers have or relay a tx, this indicates how likely the tx is to confirm
    if (callback || (! syncing && ! [self.txRelays[hash] containsObject:peer])) {
        if (! self.txRelays[hash]) self.txRelays[hash] = [NSMutableSet set];
        [self.txRelays[hash] addObject:peer];
        if (callback) [self.publishedCallback removeObjectForKey:hash];
        
        if ([self.txRelays[hash] count] >= self.maxConnectCount &&
            [account transactionForHash:transaction.txHash].blockHeight == TX_UNCONFIRMED &&
            [account transactionForHash:transaction.txHash].timestamp == 0) {
            [account setBlockHeight:TX_UNCONFIRMED andTimestamp:[NSDate timeIntervalSinceReferenceDate]
                        forTxHashes:@[hash]]; // set timestamp when tx is verified
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            
            [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(txTimeout:) object:hash];
            [[NSNotificationCenter defaultCenter] postNotificationName:DSChainPeerManagerTxStatusNotification object:self userInfo:@{DSChainPeerManagerNotificationChainKey:self.chain}];
            [[NSNotificationCenter defaultCenter] postNotificationName:DSWalletBalanceChangedNotification object:self userInfo:@{DSChainPeerManagerNotificationChainKey:self.chain}];
            if (callback) callback(nil);
            
        });
    }
    
    [self.nonFpTx addObject:hash];
    [self.txRequests[hash] removeObject:peer];
    if (! _bloomFilter) return; // bloom filter is aready being updated
    
    // the transaction likely consumed one or more wallet addresses, so check that at least the next <gap limit>
    // unused addresses are still matched by the bloom filter
    NSArray *external = [account registerAddressesWithGapLimit:SEQUENCE_GAP_LIMIT_EXTERNAL internal:NO],
    *internal = [account registerAddressesWithGapLimit:SEQUENCE_GAP_LIMIT_INTERNAL internal:YES];
    
    for (NSString *address in [external arrayByAddingObjectsFromArray:internal]) {
        NSData *hash = address.addressToHash160;
        
        if (! hash || [_bloomFilter containsData:hash]) continue;
        _bloomFilter = nil; // reset bloom filter so it's recreated with new wallet addresses
        [self updateFilter];
        break;
    }
}

- (void)peer:(DSPeer *)peer hasTransaction:(UInt256)txHash
{
    NSValue *hash = uint256_obj(txHash);
    BOOL syncing = (self.chain.lastBlockHeight < self.chain.estimatedBlockHeight);
    DSTransaction *transaction = self.publishedTx[hash];
    void (^callback)(NSError *error) = self.publishedCallback[hash];
    
    NSLog(@"%@:%d has transaction %@", peer.host, peer.port, hash);
    if (!transaction) transaction = [self.chain transactionForHash:txHash];
    if (!transaction) return;
    DSAccount * account = nil;
    if (syncing) {
        account = [self.chain accountContainingTransaction:transaction];
        if (!account) return;
    }
    if (![account registerTransaction:transaction]) return;
    if (peer == self.downloadPeer) self.lastRelayTime = [NSDate timeIntervalSinceReferenceDate];
    
    // keep track of how many peers have or relay a tx, this indicates how likely the tx is to confirm
    if (callback || (! syncing && ! [self.txRelays[hash] containsObject:peer])) {
        if (! self.txRelays[hash]) self.txRelays[hash] = [NSMutableSet set];
        [self.txRelays[hash] addObject:peer];
        if (callback) [self.publishedCallback removeObjectForKey:hash];
        
        if ([self.txRelays[hash] count] >= self.maxConnectCount &&
            [self.chain transactionForHash:txHash].blockHeight == TX_UNCONFIRMED &&
            [self.chain transactionForHash:txHash].timestamp == 0) {
            [self.chain setBlockHeight:TX_UNCONFIRMED andTimestamp:[NSDate timeIntervalSinceReferenceDate]
                           forTxHashes:@[hash]]; // set timestamp when tx is verified
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            
            [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(txTimeout:) object:hash];
            [[NSNotificationCenter defaultCenter] postNotificationName:DSChainPeerManagerTxStatusNotification object:self userInfo:@{DSChainPeerManagerNotificationChainKey:self.chain}];
            if (callback) callback(nil);
            
        });
    }
    
    [self.nonFpTx addObject:hash];
    [self.txRequests[hash] removeObject:peer];
}

- (void)peer:(DSPeer *)peer rejectedTransaction:(UInt256)txHash withCode:(uint8_t)code
{
    DSTransaction *transaction = nil;
    DSAccount * account = [self.chain accountForTransactionHash:txHash transaction:&transaction wallet:nil];
    NSValue *hash = uint256_obj(txHash);
    
    if ([self.txRelays[hash] containsObject:peer]) {
        [self.txRelays[hash] removeObject:peer];
        
        if (transaction.blockHeight == TX_UNCONFIRMED) { // set timestamp 0 for unverified
            [self.chain setBlockHeight:TX_UNCONFIRMED andTimestamp:0 forTxHashes:@[hash]];
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:DSChainPeerManagerTxStatusNotification object:self userInfo:@{DSChainPeerManagerNotificationChainKey:self.chain}];
            [[NSNotificationCenter defaultCenter] postNotificationName:DSWalletBalanceChangedNotification object:self userInfo:@{DSChainPeerManagerNotificationChainKey:self.chain}];
#if DEBUG
            UIAlertController * alert = [UIAlertController
                                         alertControllerWithTitle:@"transaction rejected"
                                         message:[NSString stringWithFormat:@"rejected by %@:%d with code 0x%x", peer.host, peer.port, code]
                                         preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction* okButton = [UIAlertAction
                                       actionWithTitle:@"ok"
                                       style:UIAlertActionStyleCancel
                                       handler:^(UIAlertAction * action) {
                                       }];
            [alert addAction:okButton];
            [[[[UIApplication sharedApplication] keyWindow] rootViewController] presentViewController:alert animated:YES completion:nil];
#endif
        });
    }
    
    [self.txRequests[hash] removeObject:peer];
    
    // if we get rejected for any reason other than double-spend, the peer is likely misconfigured
    if (code != REJECT_SPENT && [account amountSentByTransaction:transaction] > 0) {
        for (hash in transaction.inputHashes) { // check that all inputs are confirmed before dropping peer
            UInt256 h = UINT256_ZERO;
            
            [hash getValue:&h];
            if ([self.chain transactionForHash:h].blockHeight == TX_UNCONFIRMED) return;
        }
        
        [self peerMisbehavin:peer];
    }
}

- (void)peer:(DSPeer *)peer relayedBlock:(DSMerkleBlock *)block
{
    // ignore block headers that are newer than one week before earliestKeyTime (headers have 0 totalTransactions)
    if (block.totalTransactions == 0 &&
        block.timestamp + WEEK_TIME_INTERVAL/4 > self.chain.earliestWalletCreationTime + NSTimeIntervalSince1970 + HOUR_TIME_INTERVAL/2) {
        return;
    }
    
    NSArray *txHashes = block.txHashes;
    
    // track the observed bloom filter false positive rate using a low pass filter to smooth out variance
    if (peer == self.downloadPeer && block.totalTransactions > 0) {
        NSMutableSet *fp = [NSMutableSet setWithArray:txHashes];
        
        // 1% low pass filter, also weights each block by total transactions, using 1400 tx per block as typical
        [fp minusSet:self.nonFpTx]; // wallet tx are not false-positives
        [self.nonFpTx removeAllObjects];
        self.fpRate = self.fpRate*(1.0 - 0.01*block.totalTransactions/1400) + 0.01*fp.count/1400;
        
        // false positive rate sanity check
        if (self.downloadPeer.status == DSPeerStatus_Connected && self.fpRate > BLOOM_DEFAULT_FALSEPOSITIVE_RATE*10.0) {
            NSLog(@"%@:%d bloom filter false positive rate %f too high after %d blocks, disconnecting...", peer.host,
                  peer.port, self.fpRate, self.chain.lastBlockHeight + 1 - self.filterUpdateHeight);
            [self.downloadPeer disconnect];
        }
        else if (self.chain.lastBlockHeight + 500 < peer.lastblock && self.fpRate > BLOOM_REDUCED_FALSEPOSITIVE_RATE*10.0) {
            [self updateFilter]; // rebuild bloom filter when it starts to degrade
        }
    }
    
    if (! _bloomFilter) { // ignore potentially incomplete blocks when a filter update is pending
        if (peer == self.downloadPeer) self.lastRelayTime = [NSDate timeIntervalSinceReferenceDate];
        return;
    }
    
    [self.chain addBlock:block fromPeer:peer];
}

- (void)peer:(DSPeer *)peer notfoundTxHashes:(NSArray *)txHashes andBlockHashes:(NSArray *)blockhashes
{
    for (NSValue *hash in txHashes) {
        [self.txRelays[hash] removeObject:peer];
        [self.txRequests[hash] removeObject:peer];
    }
}

- (void)peer:(DSPeer *)peer setFeePerKb:(uint64_t)feePerKb
{
    uint64_t maxFeePerKb = 0, secondFeePerKb = 0;
    
    for (DSPeer *p in self.connectedPeers) { // find second highest fee rate
        if (p.status != DSPeerStatus_Connected) continue;
        if (p.feePerKb > maxFeePerKb) secondFeePerKb = maxFeePerKb, maxFeePerKb = p.feePerKb;
    }
    
    if (secondFeePerKb*2 > MIN_FEE_PER_KB && secondFeePerKb*2 <= MAX_FEE_PER_KB &&
        secondFeePerKb*2 > self.chain.feePerKb) {
        NSLog(@"increasing feePerKb to %llu based on feefilter messages from peers", secondFeePerKb*2);
        self.chain.feePerKb = secondFeePerKb*2;
    }
}

- (DSTransaction *)peer:(DSPeer *)peer requestedTransaction:(UInt256)txHash
{
    NSValue *hash = uint256_obj(txHash);
    DSTransaction *transaction = self.publishedTx[hash];
    DSAccount * account = [self.chain accountContainingTransaction:transaction];
    void (^callback)(NSError *error) = self.publishedCallback[hash];
    NSError *error = nil;
    
    if (! self.txRelays[hash]) self.txRelays[hash] = [NSMutableSet set];
    [self.txRelays[hash] addObject:peer];
    [self.nonFpTx addObject:hash];
    [self.publishedCallback removeObjectForKey:hash];
    
    if (callback && ! [account transactionIsValid:transaction]) {
        [self.publishedTx removeObjectForKey:hash];
        error = [NSError errorWithDomain:@"DashWallet" code:401
                                userInfo:@{NSLocalizedDescriptionKey:NSLocalizedString(@"double spend", nil)}];
    }
    else if (transaction && ! [account transactionForHash:txHash] && [account registerTransaction:transaction]) {
        [[DSTransactionEntity context] performBlock:^{
            [DSTransactionEntity saveContext]; // persist transactions to core data
        }];
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(txTimeout:) object:hash];
        if (callback) callback(error);
    });
    
    //    [peer sendPingMessageWithPongHandler:^(BOOL success) { // check if peer will relay the transaction back
    //        if (! success) return;
    //
    //        if (! [self.txRequests[hash] containsObject:peer]) {
    //            if (! self.txRequests[hash]) self.txRequests[hash] = [NSMutableSet set];
    //            [self.txRequests[hash] addObject:peer];
    //            [peer sendGetdataMessageWithTxHashes:@[hash] andBlockHashes:nil];
    //        }
    //    }];
    
    return transaction;
}

// MARK: Dash Specific

- (void)peer:(DSPeer *)peer relayedSpork:(DSSpork *)spork {
    if (spork.isValid) {
        [self.sporkManager peer:(DSPeer*)peer relayedSpork:spork];
    } else {
        [self peerMisbehavin:peer];
    }
}

- (void)peer:(DSPeer *)peer relayedSyncInfo:(DSSyncCountInfo)syncCountInfo count:(uint32_t)count {
    [self setCount:count forSyncCountInfo:syncCountInfo];
    switch (syncCountInfo) {
        case DSSyncCountInfo_List:
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:DSMasternodeListCountUpdateNotification object:self userInfo:@{@(syncCountInfo):@(count),DSChainPeerManagerNotificationChainKey:self.chain}];
            });
            break;
        }
        case DSSyncCountInfo_GovernanceObject:
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:DSGovernanceObjectCountUpdateNotification object:self userInfo:@{@(syncCountInfo):@(count),DSChainPeerManagerNotificationChainKey:self.chain}];
            });
            break;
        }
        case DSSyncCountInfo_GovernanceObjectVote:
        {
            if (peer.governanceRequestState == DSGovernanceRequestState_GovernanceObjectVoteHashesReceived) {
                if (count == 0) {
                    //there were no votes
                    NSLog(@"no votes on object, going to next object");
                    peer.governanceRequestState = DSGovernanceRequestState_GovernanceObjectVotes;
                    [self.governanceSyncManager finishedGovernanceVoteSyncWithPeer:peer];
                } else {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [[NSNotificationCenter defaultCenter] postNotificationName:DSGovernanceVoteCountUpdateNotification object:self userInfo:@{@(syncCountInfo):@(count),DSChainPeerManagerNotificationChainKey:self.chain}];
                    });
                }
            }
            
            break;
        }
        default:
            break;
    }
}

- (void)peer:(DSPeer *)peer hasMasternodeBroadcastHashes:(NSSet*)masternodeBroadcastHashes {
    [self.masternodeManager peer:peer hasMasternodeBroadcastHashes:masternodeBroadcastHashes];
}

- (void)peer:(DSPeer *)peer relayedMasternodeDiffMessage:(NSData*)masternodeDiffMessage {
    [self.masternodeManager peer:peer relayedMasternodeDiffMessage:masternodeDiffMessage];
}

- (void)peer:(DSPeer *)peer relayedGovernanceObject:(DSGovernanceObject *)governanceObject {
    [self.governanceSyncManager peer:peer relayedGovernanceObject:governanceObject];
}

- (void)peer:(DSPeer *)peer relayedGovernanceVote:(DSGovernanceVote *)governanceVote {
    [self.governanceSyncManager peer:peer relayedGovernanceVote:governanceVote];
}

- (void)peer:(DSPeer *)peer hasGovernanceObjectHashes:(NSSet*)governanceObjectHashes {
    [self.governanceSyncManager peer:peer hasGovernanceObjectHashes:governanceObjectHashes];
}

- (void)peer:(DSPeer *)peer hasGovernanceVoteHashes:(NSSet*)governanceVoteHashes {
    [self.governanceSyncManager.currentGovernanceSyncObject peer:peer hasGovernanceVoteHashes:governanceVoteHashes];
}

- (void)peer:(DSPeer *)peer hasSporkHashes:(NSSet*)sporkHashes {
    [self.sporkManager peer:peer hasSporkHashes:sporkHashes];
}

- (void)peer:(DSPeer *)peer relayedMasternodeBroadcast:(DSMasternodeBroadcast*)masternodeBroadcast {
    [self.masternodeManager peer:peer relayedMasternodeBroadcast:masternodeBroadcast];
}

- (void)peer:(DSPeer *)peer relayedMasternodePing:(DSMasternodePing*)masternodePing {
    [self.masternodeManager peer:peer relayedMasternodePing:masternodePing];
}

- (void)peer:(DSPeer *)peer ignoredGovernanceSync:(DSGovernanceRequestState)governanceRequestState {
    [self peerMisbehavin:peer];
    [self connect];
}

// MARK: - DSChainDelegate

-(void)chain:(DSChain*)chain didSetBlockHeight:(int32_t)height andTimestamp:(NSTimeInterval)timestamp forTxHashes:(NSArray *)txHashes updatedTx:(NSArray *)updatedTx {
    if (height != TX_UNCONFIRMED) { // remove confirmed tx from publish list and relay counts
        [self.publishedTx removeObjectsForKeys:txHashes];
        [self.publishedCallback removeObjectsForKeys:txHashes];
        [self.txRelays removeObjectsForKeys:txHashes];
    }
}

-(void)chainWasWiped:(DSChain*)chain {
    [self.txRelays removeAllObjects];
    [self.publishedTx removeAllObjects];
    [self.publishedCallback removeAllObjects];
    _bloomFilter = nil;
}

-(void)chainFinishedSyncing:(DSChain*)chain fromPeer:(DSPeer*)peer onMainChain:(BOOL)onMainChain {
    if (onMainChain && (peer == self.downloadPeer)) self.lastRelayTime = [NSDate timeIntervalSinceReferenceDate];
    NSLog(@"chain finished syncing");
    self.syncStartHeight = 0;
    [self loadMempools];
    [self getSporks];
    [self startGovernanceSync];
    [self getMasternodeList];
}

-(void)chain:(DSChain*)chain badBlockReceivedFromPeer:(DSPeer*)peer {
    NSLog(@"peer at address %@ is misbehaving",peer.host);
    [self peerMisbehavin:peer];
}

-(void)chain:(DSChain*)chain receivedOrphanBlock:(DSMerkleBlock*)block fromPeer:(DSPeer*)peer {
    // ignore orphans older than one week ago
    if (block.timestamp < [NSDate timeIntervalSinceReferenceDate] + NSTimeIntervalSince1970 - 7*24*60*60) return;
    
    // call getblocks, unless we already did with the previous block, or we're still downloading the chain
    if (self.chain.lastBlockHeight >= peer.lastblock && ! uint256_eq(self.chain.lastOrphan.blockHash, block.prevBlock)) {
        NSLog(@"%@:%d calling getblocks", peer.host, peer.port);
        [peer sendGetblocksMessageWithLocators:[self.chain blockLocatorArray] andHashStop:UINT256_ZERO];
    }
}

@end
