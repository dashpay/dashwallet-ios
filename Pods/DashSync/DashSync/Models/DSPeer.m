//
//  DSPeer.m
//  DashSync
//
//  Created by Aaron Voisine on 10/9/13.
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

#import "DSPeer.h"
#import "DSTransaction.h"
#import "DSChain.h"
#import "DSSpork.h"
#import "DSMerkleBlock.h"
#import "NSMutableData+Dash.h"
#import "NSData+Bitcoin.h"
#import "NSData+Dash.h"
#import "Reachability.h"
#import "DSMasternodeBroadcast.h"
#import "DSGovernanceObject.h"
#import <arpa/inet.h>
#import "DSMasternodePing.h"
#import "DSBloomFilter.h"
#import "DSGovernanceVote.h"
#import "DSChainPeerManager.h"
#import "DSOptionsManager.h"
#import "DSTransactionFactory.h"

#define PEER_LOGGING 1

#if ! PEER_LOGGING
#define NSLog(...)
#endif

#define MESSAGE_LOGGING 1

#define HEADER_LENGTH      24
#define MAX_MSG_LENGTH     0x02000000
#define MAX_GETDATA_HASHES 50000
#define ENABLED_SERVICES   0     // we don't provide full blocks to remote nodes
#define LOCAL_HOST         0x7f000001
#define CONNECT_TIMEOUT    3.0
#define MEMPOOL_TIMEOUT    5.0

typedef NS_ENUM(uint32_t,DSInvType) {
    DSInvType_Error = 0,
    DSInvType_Tx = 1,
    DSInvType_Block = 2,
    DSInvType_Merkleblock = 3,
    DSInvType_TxLockRequest = 4,
    DSInvType_TxLockVote = 5,
    DSInvType_Spork = 6,
    DSInvType_MasternodePaymentVote = 7,
    DSInvType_MasternodePaymentBlock = 8,
    DSInvType_MasternodeBroadcast = 14,
    DSInvType_MasternodePing = 15,
    DSInvType_DSTx = 16,
    DSInvType_GovernanceObject = 17,
    DSInvType_GovernanceObjectVote = 18,
    DSInvType_MasternodeVerify = 19,
};

@interface DSPeer ()

@property (nonatomic, assign) id<DSPeerDelegate> delegate;
@property (nonatomic, strong) dispatch_queue_t delegateQueue;
@property (nonatomic, strong) NSInputStream *inputStream;
@property (nonatomic, strong) NSOutputStream *outputStream;
@property (nonatomic, strong) NSMutableData *msgHeader, *msgPayload, *outputBuffer;
@property (nonatomic, assign) BOOL sentVerack, gotVerack;
@property (nonatomic, assign) BOOL sentGetaddr, sentFilter, sentGetdataTxBlocks, sentGetdataMasternode,sentGetdataGovernance, sentMempool, sentGetblocks, sentGetdataGovernanceVotes, sentGovSync;
@property (nonatomic, assign) BOOL receivedGovSync;
@property (nonatomic, strong) Reachability *reachability;
@property (nonatomic, strong) id reachabilityObserver;
@property (nonatomic, assign) uint64_t localNonce;
@property (nonatomic, assign) NSTimeInterval pingStartTime, relayStartTime;
@property (nonatomic, strong) DSMerkleBlock *currentBlock;
@property (nonatomic, strong) NSMutableOrderedSet *knownBlockHashes, *knownTxHashes, *currentBlockTxHashes;
@property (nonatomic, strong) NSMutableOrderedSet *knownGovernanceObjectHashes, *knownGovernanceObjectVoteHashes;
@property (nonatomic, strong) NSData *lastBlockHash;
@property (nonatomic, strong) NSMutableArray *pongHandlers;
@property (nonatomic, strong) void (^mempoolCompletion)(BOOL);
@property (nonatomic, strong) NSRunLoop *runLoop;
@property (nonatomic, strong) DSChain * chain;

@end

@implementation DSPeer

@dynamic host;

+ (instancetype)peerWithAddress:(UInt128)address andPort:(uint16_t)port onChain:(DSChain*)chain
{
    return [[self alloc] initWithAddress:address andPort:port onChain:chain];
}

+ (instancetype)peerWithHost:(NSString *)host onChain:(DSChain*)chain
{
    return [[self alloc] initWithHost:host onChain:chain];
}

- (instancetype)initWithAddress:(UInt128)address andPort:(uint16_t)port onChain:(DSChain*)chain
{
    if (! (self = [super init])) return nil;
    
    _address = address;
    _port = (port == 0) ? [chain standardPort] : port;
    self.chain = chain;
    return self;
}

- (instancetype)initWithHost:(NSString *)host onChain:(DSChain*)chain
{
    if (!chain) return nil;
    if (!host) return nil;
    if (!(self = [super init])) return nil;
    
    NSArray *pair = [host componentsSeparatedByString:@":"];
    struct in_addr addr;
    
    if (pair.count > 1) {
        host = [[pair subarrayWithRange:NSMakeRange(0, pair.count - 1)] componentsJoinedByString:@":"];
        _port = [pair.lastObject intValue];
    }
    
    if (inet_pton(AF_INET, host.UTF8String, &addr) != 1) return nil;
    _address = (UInt128){ .u32 = { 0, 0, CFSwapInt32HostToBig(0xffff), addr.s_addr } };
    if (_port == 0) _port = chain.standardPort;
    self.chain = chain;
    return self;
}

- (instancetype)initWithAddress:(UInt128)address port:(uint16_t)port onChain:(DSChain*)chain timestamp:(NSTimeInterval)timestamp
                       services:(uint64_t)services
{
    if (! (self = [self initWithAddress:address andPort:port onChain:chain])) return nil;
    
    _timestamp = timestamp;
    _services = services;
    return self;
}

- (void)dealloc
{
    [self.reachability stopNotifier];
    if (self.reachabilityObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.reachabilityObserver];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

- (void)setDelegate:(id<DSPeerDelegate>)delegate queue:(dispatch_queue_t)delegateQueue
{
    _delegate = delegate;
    _delegateQueue = (delegateQueue) ? delegateQueue : dispatch_get_main_queue();
}

- (NSString *)host
{
    char s[INET6_ADDRSTRLEN];
    
    if (_address.u64[0] == 0 && _address.u32[2] == CFSwapInt32HostToBig(0xffff)) {
        return @(inet_ntop(AF_INET, &_address.u32[3], s, sizeof(s)));
    }
    else return @(inet_ntop(AF_INET6, &_address, s, sizeof(s)));
}

- (void)connect
{
    if (self.status != DSPeerStatus_Disconnected) return;
    _status = DSPeerStatus_Connecting;
    _pingTime = DBL_MAX;
    if (! self.reachability) self.reachability = [Reachability reachabilityForInternetConnection];
    
    if (self.reachability.currentReachabilityStatus == NotReachable) { // delay connect until network is reachable
        NSLog(@"%@:%u not reachable, waiting...", self.host, self.port);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (! self.reachabilityObserver) {
                self.reachabilityObserver =
                [[NSNotificationCenter defaultCenter] addObserverForName:kReachabilityChangedNotification object:nil
                                                                   queue:nil usingBlock:^(NSNotification *note) {
                                                                       if (self.reachabilityObserver && self.reachability.currentReachabilityStatus != NotReachable) {
                                                                           _status = DSPeerStatus_Disconnected;
                                                                           [self connect];
                                                                       }
                                                                   }];
                
                [self.reachability startNotifier];
            }
        });
        
        return;
    }
    else if (self.reachabilityObserver) {
        [self.reachability stopNotifier];
        self.reachability = nil;
        [[NSNotificationCenter defaultCenter] removeObserver:self.reachabilityObserver];
        self.reachabilityObserver = nil;
    }
    
    self.msgHeader = [NSMutableData data];
    self.msgPayload = [NSMutableData data];
    self.outputBuffer = [NSMutableData data];
    self.gotVerack = self.sentVerack = NO;
    self.sentFilter = self.sentGetaddr = self.sentGetdataTxBlocks = self.sentGetdataMasternode = self.sentMempool = self.sentGetblocks = self.sentGetdataGovernance = self.sentGetdataGovernanceVotes = NO ;
    self.needsFilterUpdate = NO;
    self.knownTxHashes = [NSMutableOrderedSet orderedSet];
    self.knownBlockHashes = [NSMutableOrderedSet orderedSet];
    self.knownGovernanceObjectHashes = [NSMutableOrderedSet orderedSet];
    self.knownGovernanceObjectVoteHashes = [NSMutableOrderedSet orderedSet];
    self.currentBlock = nil;
    self.currentBlockTxHashes = nil;
    
    NSString *label = [NSString stringWithFormat:@"peer.%@:%u", self.host, self.port];
    
    // use a private serial queue for processing socket io
    dispatch_async(dispatch_queue_create(label.UTF8String, NULL), ^{
        CFReadStreamRef readStream = NULL;
        CFWriteStreamRef writeStream = NULL;
        
        NSLog(@"%@:%u connecting", self.host, self.port);
        CFStreamCreatePairWithSocketToHost(NULL, (__bridge CFStringRef)self.host, self.port, &readStream, &writeStream);
        self.inputStream = CFBridgingRelease(readStream);
        self.outputStream = CFBridgingRelease(writeStream);
        self.inputStream.delegate = self.outputStream.delegate = self;
        self.runLoop = [NSRunLoop currentRunLoop];
        [self.inputStream scheduleInRunLoop:self.runLoop forMode:NSRunLoopCommonModes];
        [self.outputStream scheduleInRunLoop:self.runLoop forMode:NSRunLoopCommonModes];
        
        // after the reachablity check, the radios should be warmed up and we can set a short socket connect timeout
        [self performSelector:@selector(disconnectWithError:)
                   withObject:[NSError errorWithDomain:@"DashWallet" code:BITCOIN_TIMEOUT_CODE
                                              userInfo:@{NSLocalizedDescriptionKey:NSLocalizedString(@"connect timeout", nil)}]
                   afterDelay:CONNECT_TIMEOUT];
        
        [self.inputStream open];
        [self.outputStream open];
        [self sendVersionMessage];
        [self.runLoop run]; // this doesn't return until the runloop is stopped
    });
}

- (void)disconnect
{
    [self disconnectWithError:nil];
}

- (void)disconnectWithError:(NSError *)error
{
    NSLog(@"Disconnected with error %@",error);
    [NSObject cancelPreviousPerformRequestsWithTarget:self]; // cancel connect timeout
    
    if (_status == DSPeerStatus_Disconnected) return;
    _status = DSPeerStatus_Disconnected;
    
    if (self.reachabilityObserver) {
        [self.reachability stopNotifier];
        self.reachability = nil;
        [[NSNotificationCenter defaultCenter] removeObserver:self.reachabilityObserver];
        self.reachabilityObserver = nil;
    }
    
    if (! self.runLoop) return;
    [self.inputStream close];
    [self.outputStream close];
    [self.inputStream removeFromRunLoop:self.runLoop forMode:NSRunLoopCommonModes];
    [self.outputStream removeFromRunLoop:self.runLoop forMode:NSRunLoopCommonModes];
    CFRunLoopStop([self.runLoop getCFRunLoop]);
    
    _status = DSPeerStatus_Disconnected;
    dispatch_async(self.delegateQueue, ^{
        [NSObject cancelPreviousPerformRequestsWithTarget:self];
        
        while (self.pongHandlers.count) {
            ((void (^)(BOOL))self.pongHandlers[0])(NO);
            [self.pongHandlers removeObjectAtIndex:0];
        }
        
        if (self.mempoolCompletion) self.mempoolCompletion(NO);
        self.mempoolCompletion = nil;
        [self.delegate peer:self disconnectedWithError:error];
    });
}

- (void)error:(NSString *)message, ... NS_FORMAT_FUNCTION(1,2)
{
    va_list args;
    
    va_start(args, message);
    [self disconnectWithError:[NSError errorWithDomain:@"DashWallet" code:500
                                              userInfo:@{NSLocalizedDescriptionKey:[[NSString alloc] initWithFormat:message arguments:args]}]];
    va_end(args);
}

- (void)didConnect
{
    if (self.status != DSPeerStatus_Connecting || ! self.sentVerack || ! self.gotVerack) return;
    
    NSLog(@"%@:%u handshake completed", self.host, self.port);
    [NSObject cancelPreviousPerformRequestsWithTarget:self]; // cancel pending handshake timeout
    _status = DSPeerStatus_Connected;
    
    dispatch_async(self.delegateQueue, ^{
        if (_status == DSPeerStatus_Connected) [self.delegate peerConnected:self];
    });
}

// MARK: - send

- (void)sendMessage:(NSData *)message type:(NSString *)type
{
    if (message.length > MAX_MSG_LENGTH) {
        NSLog(@"%@:%u failed to send %@, length %u is too long", self.host, self.port, type, (int)message.length);
#if DEBUG
        abort();
#endif
        return;
    }
    
    if (! self.runLoop) return;
    
    CFRunLoopPerformBlock([self.runLoop getCFRunLoop], kCFRunLoopCommonModes, ^{
#if MESSAGE_LOGGING
        NSLog(@"%@:%u sending %@", self.host, self.port, type);
#endif
        
        [self.outputBuffer appendMessage:message type:type forChain:self.chain];
        
        while (self.outputBuffer.length > 0 && self.outputStream.hasSpaceAvailable) {
            NSInteger l = [self.outputStream write:self.outputBuffer.bytes maxLength:self.outputBuffer.length];
            
            if (l > 0) [self.outputBuffer replaceBytesInRange:NSMakeRange(0, l) withBytes:NULL length:0];
            //if (self.outputBuffer.length == 0) NSLog(@"%@:%u output buffer cleared", self.host, self.port);
        }
    });
    CFRunLoopWakeUp([self.runLoop getCFRunLoop]);
}

- (void)sendVersionMessage
{
    NSMutableData *msg = [NSMutableData data];
    uint16_t port = CFSwapInt16HostToBig(self.port);
    
    [msg appendUInt32:self.chain.protocolVersion]; // version
    [msg appendUInt64:ENABLED_SERVICES]; // services
    [msg appendUInt64:[NSDate timeIntervalSinceReferenceDate] + NSTimeIntervalSince1970]; // timestamp
    [msg appendUInt64:self.services]; // services of remote peer
    [msg appendBytes:&_address length:sizeof(_address)]; // IPv6 address of remote peer
    [msg appendBytes:&port length:sizeof(port)]; // port of remote peer
    [msg appendNetAddress:LOCAL_HOST port:self.chain.standardPort services:ENABLED_SERVICES]; // net address of local peer
    self.localNonce = ((uint64_t)arc4random() << 32) | (uint64_t)arc4random(); // random nonce
    [msg appendUInt64:self.localNonce];
    if (self.chain.isMainnet) {
        [msg appendString:USER_AGENT]; // user agent
    } else if (self.chain.isTestnet) {
        [msg appendString:[USER_AGENT stringByAppendingString:@"(testnet)"]];
    } else {
        [msg appendString:[USER_AGENT stringByAppendingString:[NSString stringWithFormat:@"(devnet=%@)",self.chain.devnetIdentifier]]];
    }
    [msg appendUInt32:0]; // last block received
    [msg appendUInt8:0]; // relay transactions (no for SPV bloom filter mode)
    self.pingStartTime = [NSDate timeIntervalSinceReferenceDate];
    [self sendMessage:msg type:MSG_VERSION];
}

- (void)sendVerackMessage
{
    [self sendMessage:[NSData data] type:MSG_VERACK];
    self.sentVerack = YES;
    [self didConnect];
}

- (void)sendFilterloadMessage:(NSData *)filter
{
    self.sentFilter = YES;
    [self sendMessage:filter type:MSG_FILTERLOAD];
}

- (void)mempoolTimeout
{
    dispatch_async(self.delegateQueue, ^{
        [NSObject cancelPreviousPerformRequestsWithTarget:self];
    });
    
    [self sendPingMessageWithPongHandler:self.mempoolCompletion];
    self.mempoolCompletion = nil;
}

- (void)sendMempoolMessage:(NSArray *)publishedTxHashes completion:(void (^)(BOOL))completion
{
    [self.knownTxHashes addObjectsFromArray:publishedTxHashes];
    self.sentMempool = YES;
    
    if (completion) {
        if (self.mempoolCompletion) {
            dispatch_async(self.delegateQueue, ^{
                if (_status == DSPeerStatus_Connected) completion(NO);
            });
        }
        else {
            self.mempoolCompletion = completion;
            dispatch_async(self.delegateQueue, ^{
                [self performSelector:@selector(mempoolTimeout) withObject:nil afterDelay:MEMPOOL_TIMEOUT];
            });
        }
    }
    
    [self sendMessage:[NSData data] type:MSG_MEMPOOL];
}

- (void)sendAddrMessage
{
    NSMutableData *msg = [NSMutableData data];
    
    //TODO: send peer addresses we know about
    [msg appendVarInt:0];
    [self sendMessage:msg type:MSG_ADDR];
}

// the standard blockchain download protocol works as follows (for SPV mode):
// - local peer sends getblocks
// - remote peer reponds with inv containing up to 500 block hashes
// - local peer sends getdata with the block hashes
// - remote peer responds with multiple merkleblock and tx messages
// - remote peer sends inv containg 1 hash, of the most recent block
// - local peer sends getdata with the most recent block hash
// - remote peer responds with merkleblock
// - if local peer can't connect the most recent block to the chain (because it started more than 500 blocks behind), go
//   back to first step and repeat until entire chain is downloaded
//
// we modify this sequence to improve sync performance and handle adding bip32 addresses to the bloom filter as needed:
// - local peer sends getheaders
// - remote peer responds with up to 2000 headers
// - local peer immediately sends getheaders again and then processes the headers
// - previous two steps repeat until a header within a week of earliestKeyTime is reached (further headers are ignored)
// - local peer sends getblocks
// - remote peer responds with inv containing up to 500 block hashes
// - local peer sends getdata with the block hashes
// - if there were 500 hashes, local peer sends getblocks again without waiting for remote peer
// - remote peer responds with multiple merkleblock and tx messages, followed by inv containing up to 500 block hashes
// - previous two steps repeat until an inv with fewer than 500 block hashes is received
// - local peer sends just getdata for the final set of fewer than 500 block hashes
// - remote peer responds with multiple merkleblock and tx messages
// - if at any point tx messages consume enough wallet addresses to drop below the bip32 chain gap limit, more addresses
//   are generated and local peer sends filterload with an updated bloom filter
// - after filterload is sent, getdata is sent to re-request recent blocks that may contain new tx matching the filter

- (void)sendGetheadersMessageWithLocators:(NSArray *)locators andHashStop:(UInt256)hashStop
{
    NSMutableData *msg = [NSMutableData data];
    UInt256 h;
    
    [msg appendUInt32:self.chain.protocolVersion];
    [msg appendVarInt:locators.count];
    
    for (NSValue *hash in locators) {
        [hash getValue:&h];
        [msg appendBytes:&h length:sizeof(h)];
    }
    
    [msg appendBytes:&hashStop length:sizeof(hashStop)];
    if (self.relayStartTime == 0) self.relayStartTime = [NSDate timeIntervalSinceReferenceDate];
    [self sendMessage:msg type:MSG_GETHEADERS];
}

- (void)sendGetblocksMessageWithLocators:(NSArray *)locators andHashStop:(UInt256)hashStop
{
    NSMutableData *msg = [NSMutableData data];
    UInt256 h;
    
    [msg appendUInt32:self.chain.protocolVersion];
    [msg appendVarInt:locators.count];
    
    for (NSValue *hash in locators) {
        [hash getValue:&h];
        [msg appendBytes:&h length:sizeof(h)];
    }
    
    [msg appendBytes:&hashStop length:sizeof(hashStop)];
    self.sentGetblocks = YES;
    [self sendMessage:msg type:MSG_GETBLOCKS];
}

- (void)sendInvMessageWithTxHashes:(NSArray *)txHashes
{
    NSMutableOrderedSet *hashes = [NSMutableOrderedSet orderedSetWithArray:txHashes];
    NSMutableData *msg = [NSMutableData data];
    UInt256 h;
    
    [hashes minusOrderedSet:self.knownTxHashes];
    if (hashes.count == 0) return;
    [msg appendVarInt:hashes.count];
    
    for (NSValue *hash in hashes) {
        [msg appendUInt32:DSInvType_Tx];
        [hash getValue:&h];
        [msg appendBytes:&h length:sizeof(h)];
    }
    
    [self sendMessage:msg type:MSG_INV];
    [self.knownTxHashes unionOrderedSet:hashes];
}

- (void)sendGetdataMessageWithTxHashes:(NSArray *)txHashes andBlockHashes:(NSArray *)blockHashes
{
    if (!([[DSOptionsManager sharedInstance] syncType] & DSSyncType_GetsNewBlocks)) return;
    if (txHashes.count + blockHashes.count > MAX_GETDATA_HASHES) { // limit total hash count to MAX_GETDATA_HASHES
        NSLog(@"%@:%u couldn't send getdata, %u is too many items, max is %u", self.host, self.port,
              (int)txHashes.count + (int)blockHashes.count, MAX_GETDATA_HASHES);
        return;
    }
    else if (txHashes.count + blockHashes.count == 0) return;
    
    NSMutableData *msg = [NSMutableData data];
    UInt256 h;
    
    [msg appendVarInt:txHashes.count + blockHashes.count];
    
    for (NSValue *hash in txHashes) {
        [msg appendUInt32:DSInvType_Tx];
        [hash getValue:&h];
        [msg appendBytes:&h length:sizeof(h)];
    }
    
    for (NSValue *hash in blockHashes) {
        [msg appendUInt32:DSInvType_Merkleblock];
        [hash getValue:&h];
        [msg appendBytes:&h length:sizeof(h)];
    }
    
    self.sentGetdataTxBlocks = YES;
    [self sendMessage:msg type:MSG_GETDATA];
}

- (void)sendGetdataMessageWithMasternodeBroadcastHashes:(NSArray<NSData*> *)masternodeBroadcastHashes
{
    if (masternodeBroadcastHashes.count > MAX_GETDATA_HASHES) { // limit total hash count to MAX_GETDATA_HASHES
        NSLog(@"%@:%u couldn't send masternode getdata, %u is too many items, max is %u", self.host, self.port,
              (int)masternodeBroadcastHashes.count, MAX_GETDATA_HASHES);
        return;
    }
    else if (masternodeBroadcastHashes.count == 0) return;
    
    NSMutableData *msg = [NSMutableData data];
    
    [msg appendVarInt:masternodeBroadcastHashes.count];
    
    for (NSData *dataHash in masternodeBroadcastHashes) {
        [msg appendUInt32:DSInvType_MasternodeBroadcast];
        
        [msg appendBytes:dataHash.bytes length:sizeof(UInt256)];
    }
    
    self.sentGetdataMasternode = YES;
    [self sendMessage:msg type:MSG_GETDATA];
}

-(void)sendGetMasternodeListFromPreviousBlockHash:(UInt256)previousBlockHash forBlockHash:(UInt256)blockHash {
    NSMutableData *msg = [NSMutableData data];
    [msg appendUInt256:previousBlockHash];
    [msg appendUInt256:blockHash];
    NSLog(@"%@",msg);
    [self sendMessage:msg type:MSG_GETMNLISTDIFF];
}

- (void)sendGetdataMessageWithGovernanceObjectHashes:(NSArray<NSData*> *)governanceObjectHashes
{
    if (governanceObjectHashes.count > MAX_GETDATA_HASHES) { // limit total hash count to MAX_GETDATA_HASHES
        NSLog(@"%@:%u couldn't send governance getdata, %u is too many items, max is %u", self.host, self.port,
              (int)governanceObjectHashes.count, MAX_GETDATA_HASHES);
        return;
    }
    else if (governanceObjectHashes.count == 0) return;
    
    NSMutableData *msg = [NSMutableData data];
    
    [msg appendVarInt:governanceObjectHashes.count];
    
    for (NSData *dataHash in governanceObjectHashes) {
        [msg appendUInt32:DSInvType_GovernanceObject];
        
        [msg appendBytes:dataHash.bytes length:sizeof(UInt256)];
    }
    
    self.sentGetdataGovernance = YES;
    [self sendMessage:msg type:MSG_GETDATA];
}

- (void)sendGetdataMessageWithGovernanceVoteHashes:(NSArray<NSData*> *)governanceVoteHashes {
    if (governanceVoteHashes.count > MAX_GETDATA_HASHES) { // limit total hash count to MAX_GETDATA_HASHES
        NSLog(@"%@:%u couldn't send governance votes getdata, %u is too many items, max is %u", self.host, self.port,
              (int)governanceVoteHashes.count, MAX_GETDATA_HASHES);
        return;
    }
    else if (governanceVoteHashes.count == 0) return;
    
    NSMutableData *msg = [NSMutableData data];
    
    [msg appendVarInt:governanceVoteHashes.count];
    
    for (NSData *dataHash in governanceVoteHashes) {
        [msg appendUInt32:DSInvType_GovernanceObjectVote];
        
        [msg appendBytes:dataHash.bytes length:sizeof(UInt256)];
    }
    
    self.sentGetdataGovernanceVotes = YES;
    [self sendMessage:msg type:MSG_GETDATA];
}


- (void)sendGetaddrMessage
{
    self.sentGetaddr = YES;
    [self sendMessage:[NSData data] type:MSG_GETADDR];
}

- (void)sendPingMessageWithPongHandler:(void (^)(BOOL success))pongHandler;
{
    NSMutableData *msg = [NSMutableData data];
    
    dispatch_async(self.delegateQueue, ^{
        if (! self.pongHandlers) self.pongHandlers = [NSMutableArray array];
        [self.pongHandlers addObject:(pongHandler) ? [pongHandler copy] : [^(BOOL success) {} copy]];
        [msg appendUInt64:self.localNonce];
        self.pingStartTime = [NSDate timeIntervalSinceReferenceDate];
        [self sendMessage:msg type:MSG_PING];
    });
}

// re-request blocks starting from blockHash, useful for getting any additional transactions after a bloom filter update
- (void)rerequestBlocksFrom:(UInt256)blockHash
{
    NSUInteger i = [self.knownBlockHashes indexOfObject:uint256_obj(blockHash)];
    
    if (i != NSNotFound) {
        [self.knownBlockHashes removeObjectsInRange:NSMakeRange(0, i)];
        NSLog(@"%@:%u re-requesting %u blocks", self.host, self.port, (int)self.knownBlockHashes.count);
        [self sendGetdataMessageWithTxHashes:nil andBlockHashes:self.knownBlockHashes.array];
    }
}

// MARK: - send Dash Sporks

-(void)sendGetSporks {
    [self sendMessage:[NSData data] type:MSG_GETSPORKS];
}

// MARK: - send Dash Masternode list

-(void)sendDSegMessage:(DSUTXO)utxo {
    NSMutableData *msg = [NSMutableData data];
    [msg appendUInt256:utxo.hash];
    if (uint256_is_zero(utxo.hash)) {
        NSLog(@"%@:%u Requesting Masternode List",self.host, self.port);
        [msg appendUInt32:UINT32_MAX];
    } else {
        NSLog(@"%@:%u Requesting Masternode Entry",self.host, self.port);
        [msg appendUInt32:(uint32_t)utxo.n];
    }
    
    [msg appendUInt8:0];
    [msg appendUInt32:UINT32_MAX];
    [self sendMessage:msg type:MSG_DSEG];
}

// MARK: - send Dash Governance

- (void)sendGovSync:(UInt256)parentHash { //for votes
    if (self.governanceRequestState != DSGovernanceRequestState_None) {  //Make sure we aren't in a governance sync process
        NSLog(@"%@:%u Requesting Governance Vote Hashes out of resting state",self.host, self.port);
        return;
    }
    self.sentGovSync = TRUE;
    NSLog(@"%@:%u Requesting Governance Object Vote Hashes",self.host, self.port);
    NSMutableData *msg = [NSMutableData data];
    //UInt256 reversed = *(UInt256*)[NSData dataWithUInt256:parentHash].reverse.bytes;
    [msg appendBytes:&parentHash length:sizeof(parentHash)];
    [msg appendData:[[[DSBloomFilter alloc] initWithFalsePositiveRate:0.01 forElementCount:20000 tweak:arc4random_uniform(10000) flags:1] toData]];
    self.governanceRequestState = DSGovernanceRequestState_GovernanceObjectVoteHashes;
    [self sendMessage:msg type:MSG_GOVOBJSYNC];
}

- (void)sendGovSync { //for governance objects
    if (self.governanceRequestState != DSGovernanceRequestState_None) {//Make sure we aren't in a governance sync process
        NSLog(@"%@:%u Requesting Governance Object Hashes out of resting state",self.host, self.port);
        return;
    }
    NSLog(@"%@:%u Requesting Governance Object Hashes",self.host, self.port);
    UInt256 h = UINT256_ZERO;
    NSMutableData *msg = [NSMutableData data];
    
    [msg appendBytes:&h length:sizeof(h)];
    [msg appendData:[DSBloomFilter emptyBloomFilterData]];
    self.governanceRequestState = DSGovernanceRequestState_GovernanceObjectHashes;
    [self sendMessage:msg type:MSG_GOVOBJSYNC];
    
    //we aren't afraid of coming back here within 5 seconds because a peer can only sendGovSync once every 3 hours
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.governanceRequestState == DSGovernanceRequestState_GovernanceObjectHashes) {
            NSLog(@"%@:%u Peer ignored request for governance object hashes",self.host, self.port);
            [self.delegate peer:self ignoredGovernanceSync:DSGovernanceRequestState_GovernanceObjectHashes];
        }
    });
}

-(void)sendGovObjectVote:(DSGovernanceVote*)governanceVote {
    [self sendMessage:[governanceVote dataMessage] type:MSG_GOVOBJVOTE];
}

-(void)sendGovObject:(DSGovernanceObject*)governanceObject {
    [self sendMessage:[governanceObject dataMessage] type:MSG_GOVOBJ];
}


// MARK: - accept

- (void)acceptMessage:(NSData *)message type:(NSString *)type
{
#if MESSAGE_LOGGING
    if (![type isEqualToString:MSG_INV] && ![type isEqualToString:MSG_GOVOBJVOTE]) {
        NSLog(@"%@:%u accept message %@", self.host, self.port, type);
    }
#endif
    if (self.currentBlock && (! ([MSG_TX isEqual:type] || [MSG_IX isEqual:type] ))) { // if we receive a non-tx message, merkleblock is done
        UInt256 hash = self.currentBlock.blockHash;
        
        self.currentBlock = nil;
        self.currentBlockTxHashes = nil;
        [self error:@"incomplete merkleblock %@, expected %u more tx, got %@",
         uint256_obj(hash), (int)self.currentBlockTxHashes.count, type];
    }
    else if ([MSG_VERSION isEqual:type]) [self acceptVersionMessage:message];
    else if ([MSG_VERACK isEqual:type]) [self acceptVerackMessage:message];
    else if ([MSG_ADDR isEqual:type]) [self acceptAddrMessage:message];
    else if ([MSG_INV isEqual:type]) [self acceptInvMessage:message];
    else if ([MSG_TX isEqual:type]) [self acceptTxMessage:message];
    else if ([MSG_IX isEqual:type]) [self acceptTxMessage:message];
    else if ([MSG_HEADERS isEqual:type]) [self acceptHeadersMessage:message];
    else if ([MSG_GETADDR isEqual:type]) [self acceptGetaddrMessage:message];
    else if ([MSG_GETDATA isEqual:type]) [self acceptGetdataMessage:message];
    else if ([MSG_NOTFOUND isEqual:type]) [self acceptNotfoundMessage:message];
    else if ([MSG_PING isEqual:type]) [self acceptPingMessage:message];
    else if ([MSG_PONG isEqual:type]) [self acceptPongMessage:message];
    else if ([MSG_MERKLEBLOCK isEqual:type]) [self acceptMerkleblockMessage:message];
    else if ([MSG_REJECT isEqual:type]) [self acceptRejectMessage:message];
    else if ([MSG_FEEFILTER isEqual:type]) [self acceptFeeFilterMessage:message];
    //control
    else if ([MSG_SPORK isEqual:type]) [self acceptSporkMessage:message];
    //masternode
    else if ([MSG_SSC isEqual:type]) [self acceptSSCMessage:message];
    else if ([MSG_MNB isEqual:type]) [self acceptMNBMessage:message];
    else if ([MSG_MNLISTDIFF isEqual:type]) [self acceptMNLISTDIFFMessage:message];
    //governance
    else if ([MSG_GOVOBJVOTE isEqual:type]) [self acceptGovObjectVoteMessage:message];
    else if ([MSG_GOVOBJ isEqual:type]) [self acceptGovObjectMessage:message];
    //else if ([MSG_GOVOBJSYNC isEqual:type]) [self acceptGovObjectSyncMessage:message];
    
    //private send
    else if ([MSG_DARKSENDANNOUNCE isEqual:type]) [self acceptDarksendAnnounceMessage:message];
    else if ([MSG_DARKSENDCONTROL isEqual:type]) [self acceptDarksendControlMessage:message];
    else if ([MSG_DARKSENDFINISH isEqual:type]) [self acceptDarksendFinishMessage:message];
    else if ([MSG_DARKSENDINITIATE isEqual:type]) [self acceptDarksendInitiateMessage:message];
    else if ([MSG_DARKSENDQUORUM isEqual:type]) [self acceptDarksendQuorumMessage:message];
    else if ([MSG_DARKSENDSESSION isEqual:type]) [self acceptDarksendSessionMessage:message];
    else if ([MSG_DARKSENDSESSIONUPDATE isEqual:type]) [self acceptDarksendSessionUpdateMessage:message];
    else if ([MSG_DARKSENDTX isEqual:type]) [self acceptDarksendTransactionMessage:message];
    else {
#if DROP_MESSAGE_LOGGING
        NSLog(@"%@:%u dropping %@, len:%u, not implemented", self.host, self.port, type, (int)message.length);
#endif
    }
}

- (void)acceptVersionMessage:(NSData *)message
{
    NSNumber * l = nil;
    
    if (message.length < 85) {
        [self error:@"malformed version message, length is %u, should be > 84", (int)message.length];
        return;
    }
    
    _version = [message UInt32AtOffset:0];
    _services = [message UInt64AtOffset:4];
    _timestamp = [message UInt64AtOffset:12] - NSTimeIntervalSince1970;
    _useragent = [message stringAtOffset:80 length:&l];
    
    if (message.length < 80 + l.unsignedIntegerValue + sizeof(uint32_t)) {
        [self error:@"malformed version message, length is %u, should be %u", (int)message.length, (int)(80 + l.unsignedIntegerValue + 4)];
        return;
    }
    
    _lastblock = [message UInt32AtOffset:80 + l.unsignedIntegerValue];
#if MESSAGE_LOGGING
    NSLog(@"%@:%u got version %u, useragent:\"%@\"", self.host, self.port, self.version, self.useragent);
#endif
    if (self.version < self.chain.minProtocolVersion) {
        [self error:@"protocol version %u not supported", self.version];
        return;
    }
    
    [self sendVerackMessage];
}

- (void)acceptVerackMessage:(NSData *)message
{
    if (self.gotVerack) {
        NSLog(@"%@:%u got unexpected verack", self.host, self.port);
        return;
    }
    
    _pingTime = [NSDate timeIntervalSinceReferenceDate] - self.pingStartTime; // use verack time as initial ping time
    self.pingStartTime = 0;
#if MESSAGE_LOGGING
    NSLog(@"%@:%u got verack in %fs", self.host, self.port, self.pingTime);
#endif
    self.gotVerack = YES;
    [self didConnect];
}

// TODO: relay addresses
- (void)acceptAddrMessage:(NSData *)message
{
    if (message.length > 0 && [message UInt8AtOffset:0] == 0) {
        NSLog(@"%@:%u got addr with 0 addresses", self.host, self.port);
        return;
    }
    else if (message.length < 5) {
        [self error:@"malformed addr message, length %u is too short", (int)message.length];
        return;
    }
    else if (! self.sentGetaddr) return; // simple anti-tarpitting tactic, don't accept unsolicited addresses
    
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSNumber * l = nil;
    NSUInteger count = (NSUInteger)[message varIntAtOffset:0 length:&l];
    NSMutableArray *peers = [NSMutableArray array];
    
    if (count > 1000) {
        NSLog(@"%@:%u dropping addr message, %u is too many addresses (max 1000)", self.host, self.port, (int)count);
        return;
    }
    else if (message.length < l.unsignedIntegerValue + count*30) {
        [self error:@"malformed addr message, length is %u, should be %u for %u addresses", (int)message.length,
         (int)(l.unsignedIntegerValue + count*30), (int)count];
        return;
    }
    else NSLog(@"%@:%u got addr with %u addresses", self.host, self.port, (int)count);
    
    for (NSUInteger off = l.unsignedIntegerValue; off < l.unsignedIntegerValue + 30*count; off += 30) {
        NSTimeInterval timestamp = [message UInt32AtOffset:off] - NSTimeIntervalSince1970;
        uint64_t services = [message UInt64AtOffset:off + sizeof(uint32_t)];
        UInt128 address = *(UInt128 *)((const uint8_t *)message.bytes + off + sizeof(uint32_t) + sizeof(uint64_t));
        uint16_t port = CFSwapInt16BigToHost(*(const uint16_t *)((const uint8_t *)message.bytes + off +
                                                                 sizeof(uint32_t) + sizeof(uint64_t) +
                                                                 sizeof(UInt128)));
        
        if (! (services & SERVICES_NODE_NETWORK)) continue; // skip peers that don't carry full blocks
        if (address.u64[0] != 0 || address.u32[2] != CFSwapInt32HostToBig(0xffff)) continue; // ignore IPv6 for now
        
        // if address time is more than 10 min in the future or older than reference date, set to 5 days old
        if (timestamp > now + 10*60 || timestamp < 0) timestamp = now - 5*24*60*60;
        
        // subtract two hours and add it to the list
        [peers addObject:[[DSPeer alloc] initWithAddress:address port:port onChain:self.chain timestamp:timestamp - 2*60*60
                                                services:services]];
    }
    
    dispatch_async(self.delegateQueue, ^{
        if (_status == DSPeerStatus_Connected) [self.delegate peer:self relayedPeers:peers];
    });
}

- (void)acceptInvMessage:(NSData *)message
{
    NSNumber * l = nil;
    NSUInteger count = (NSUInteger)[message varIntAtOffset:0 length:&l];
    NSMutableOrderedSet *txHashes = [NSMutableOrderedSet orderedSet];
    NSMutableOrderedSet *blockHashes = [NSMutableOrderedSet orderedSet];
    NSMutableSet *sporkHashes = [NSMutableSet set];
    NSMutableSet *governanceObjectHashes = [NSMutableSet set];
    NSMutableSet *governanceObjectVoteHashes = [NSMutableSet set];
    //NSMutableSet *masternodePingHashes = [NSMutableSet set]; //we don't care about ping messages
    NSMutableSet *masternodeVerifications = [NSMutableSet set]; //mnv messages
    NSMutableSet *masternodeBroadcastHashes = [NSMutableSet set]; //mnb messages
    
    if (l.unsignedIntegerValue == 0 || message.length < l.unsignedIntegerValue + count*36) {
        [self error:@"malformed inv message, length is %u, should be %u for %u items", (int)message.length,
         (int)(((l.unsignedIntegerValue == 0) ? 1 : l.unsignedIntegerValue) + count*36), (int)count];
        return;
    }
    else if (count > MAX_GETDATA_HASHES) {
        NSLog(@"%@:%u dropping inv message, %u is too many items, max is %u", self.host, self.port, (int)count,
              MAX_GETDATA_HASHES);
        return;
    }
    
    if (count > 0 && ([message UInt32AtOffset:l.unsignedIntegerValue] != DSInvType_MasternodePing) && ([message UInt32AtOffset:l.unsignedIntegerValue] != DSInvType_MasternodePaymentVote) && ([message UInt32AtOffset:l.unsignedIntegerValue] != DSInvType_MasternodeVerify)) {
        NSLog(@"%@:%u got inv with %u items (first item %u)", self.host, self.port, (int)count,[message UInt32AtOffset:l.unsignedIntegerValue]);
    }
    
    for (NSUInteger off = l.unsignedIntegerValue; off < l.unsignedIntegerValue + 36*count; off += 36) {
        DSInvType type = [message UInt32AtOffset:off];
        UInt256 hash = [message hashAtOffset:off + sizeof(uint32_t)];
        
        if (uint256_is_zero(hash)) continue;
        
        switch (type) {
            case DSInvType_Tx:
            case DSInvType_DSTx:
            case DSInvType_TxLockRequest:
                [txHashes addObject:uint256_obj(hash)]; break;
            case DSInvType_TxLockVote: break;
            case DSInvType_Block: [blockHashes addObject:uint256_obj(hash)]; break;
            case DSInvType_Merkleblock: [blockHashes addObject:uint256_obj(hash)]; break;
            case DSInvType_Spork: [sporkHashes addObject:[NSData dataWithUInt256:hash]]; break;
            case DSInvType_GovernanceObject: [governanceObjectHashes addObject:[NSData dataWithUInt256:hash]]; break;
            case DSInvType_GovernanceObjectVote: [governanceObjectVoteHashes addObject:[NSData dataWithUInt256:hash]]; break;
            case DSInvType_MasternodePing: break;//[masternodePingHashes addObject:uint256_obj(hash)]; break;
            case DSInvType_MasternodePaymentVote: break;
            case DSInvType_MasternodeVerify: [masternodeVerifications addObject:[NSData dataWithUInt256:hash]]; break;
            case DSInvType_MasternodeBroadcast: [masternodeBroadcastHashes addObject:[NSData dataWithUInt256:hash]]; break;
            default:
            {
                NSAssert(FALSE, @"inventory type not dealt with");
                break;
            }
        }
    }
    
    if ([self.chain syncsBlockchain] && !self.sentFilter && ! self.sentMempool && ! self.sentGetblocks) {
        if (txHashes.count > 0) [self error:@"got inv message before loading a filter"];
        return;
    }
    else if (txHashes.count > 10000) { // this was happening on testnet, some sort of DOS/spam attack?
        NSLog(@"%@:%u too many transactions, disconnecting", self.host, self.port);
        [self disconnect]; // disconnecting seems to be the easiest way to mitigate it
        return;
    }
    else if (self.currentBlockHeight > 0 && blockHashes.count > 2 && blockHashes.count < 500 &&
             self.currentBlockHeight + self.knownBlockHashes.count + blockHashes.count < self.lastblock) {
        [self error:@"non-standard inv, %u is fewer block hashes than expected", (int)blockHashes.count];
        return;
    }
    
    if (blockHashes.count == 1 && [self.lastBlockHash isEqual:blockHashes[0]]) [blockHashes removeAllObjects];
    if (blockHashes.count == 1) self.lastBlockHash = blockHashes[0];
    
    if (blockHashes.count > 0) { // remember blockHashes in case we need to re-request them with an updated bloom filter
        dispatch_async(self.delegateQueue, ^{
            [self.knownBlockHashes unionOrderedSet:blockHashes];
            
            while (self.knownBlockHashes.count > MAX_GETDATA_HASHES) {
                [self.knownBlockHashes removeObjectsInRange:NSMakeRange(0, self.knownBlockHashes.count/3)];
            }
        });
    }
    
    if ([txHashes intersectsOrderedSet:self.knownTxHashes]) { // remove transactions we already have
        for (NSValue *hash in txHashes) {
            UInt256 h;
            
            if (! [self.knownTxHashes containsObject:hash]) continue;
            [hash getValue:&h];
            
            dispatch_async(self.delegateQueue, ^{
                if (_status == DSPeerStatus_Connected) [self.delegate peer:self hasTransaction:h];
            });
        }
        
        [txHashes minusOrderedSet:self.knownTxHashes];
    }
    
    [self.knownTxHashes unionOrderedSet:txHashes];
    
    if (txHashes.count > 0 || (! self.needsFilterUpdate && blockHashes.count > 0)) {
        [self sendGetdataMessageWithTxHashes:txHashes.array
                              andBlockHashes:(self.needsFilterUpdate) ? nil : blockHashes.array];
    }
    
    // to improve chain download performance, if we received 500 block hashes, we request the next 500 block hashes
    if (blockHashes.count >= 500 && ! self.needsFilterUpdate) {
        [self sendGetblocksMessageWithLocators:@[blockHashes.lastObject, blockHashes.firstObject]
                                   andHashStop:UINT256_ZERO];
    }
    
    if (self.mempoolCompletion && (txHashes.count > 0 || blockHashes.count == 0)) {
        dispatch_async(self.delegateQueue, ^{
            [NSObject cancelPreviousPerformRequestsWithTarget:self];
        });
        
        [self sendPingMessageWithPongHandler:self.mempoolCompletion];
        self.mempoolCompletion = nil;
    }
    
    if (governanceObjectHashes.count > 0) {
        [self.delegate peer:self hasGovernanceObjectHashes:governanceObjectHashes];
    }
    if (governanceObjectVoteHashes.count > 0) {
        [self.delegate peer:self hasGovernanceVoteHashes:governanceObjectVoteHashes];
    }
    if (masternodeBroadcastHashes.count > 0) {
        NSLog(@"requesting data on %lu broadcasts",(unsigned long)masternodeBroadcastHashes.count);
        [self.delegate peer:self hasMasternodeBroadcastHashes:masternodeBroadcastHashes];
    }
    if (sporkHashes.count > 0) {
        [self.delegate peer:self hasSporkHashes:sporkHashes];
    }
}

- (void)acceptTxMessage:(NSData *)message
{
    DSTransaction *tx = [DSTransaction transactionWithMessage:message onChain:self.chain];
    
    if (! tx) {
        [self error:@"malformed tx message: %@", message];
        return;
    }
    else if (! self.sentFilter && ! self.sentGetdataTxBlocks) {
        [self error:@"got tx message before loading a filter"];
        return;
    }
    
    NSLog(@"%@:%u got tx %@", self.host, self.port, uint256_obj(tx.txHash));
    
    dispatch_async(self.delegateQueue, ^{
        [self.delegate peer:self relayedTransaction:tx];
    });
    
    if (self.currentBlock) { // we're collecting tx messages for a merkleblock
        [self.currentBlockTxHashes removeObject:uint256_obj(tx.txHash)];
        
        if (self.currentBlockTxHashes.count == 0) { // we received the entire block including all matched tx
            DSMerkleBlock *block = self.currentBlock;
            
            self.currentBlock = nil;
            self.currentBlockTxHashes = nil;
            
            dispatch_sync(self.delegateQueue, ^{ // syncronous dispatch so we don't get too many queued up tx
                [self.delegate peer:self relayedBlock:block];
            });
        }
    }
}

- (void)acceptHeadersMessage:(NSData *)message
{
    NSNumber * lNumber = nil;
    NSUInteger count = (NSUInteger)[message varIntAtOffset:0 length:&lNumber];
    NSUInteger l = lNumber.unsignedIntegerValue;
    NSUInteger off = 0;
    if (count == 0) {
        [self error:@"count cannot be 0"];
        return;
    }
    
    if (message.length < l + 81*count) {
        [self error:@"malformed headers message, length is %u, should be %u for %u items", (int)message.length,
         (int)(((l == 0) ? 1 : l) + count*81), (int)count];
        return;
    }
    NSLog(@"%@:%u got %u headers", self.host, self.port, (int)count);
    
    if (_relayStartTime != 0) { // keep track of relay peformance
        NSTimeInterval speed = count/([NSDate timeIntervalSinceReferenceDate] - self.relayStartTime);
        
        if (_relaySpeed == 0) _relaySpeed = speed;
        _relaySpeed = _relaySpeed*0.9 + speed*0.1;
        _relayStartTime = 0;
    }
    for (int i = 0; i < count; i++) {
        UInt256 locator = [message subdataWithRange:NSMakeRange(l + 81*i, 80)].x11;
        NSLog(@"%@:%u header: %@", self.host, self.port, uint256_obj(locator));
    }
    // To improve chain download performance, if this message contains 2000 headers then request the next 2000 headers
    // immediately, and switch to requesting blocks when we receive a header newer than earliestKeyTime
    // Devnets can run slower than usual
    NSTimeInterval t = [message UInt32AtOffset:l + 81*(count - 1) + 68] - NSTimeIntervalSince1970;
    if (count >= 2000 || t >= self.earliestKeyTime - (2*HOUR_TIME_INTERVAL + WEEK_TIME_INTERVAL)/4 || [self.chain isDevnetAny]) {
        UInt256 firstX11 = [message subdataWithRange:NSMakeRange(l, 80)].x11;
        UInt256 lastX11 = [message subdataWithRange:NSMakeRange(l + 81*(count - 1), 80)].x11;
        NSValue *firstHash = uint256_obj(firstX11);
        NSValue *lastHash = uint256_obj(lastX11);
        
        if (t >= self.earliestKeyTime - (2*HOUR_TIME_INTERVAL + WEEK_TIME_INTERVAL)/4) { // request blocks for the remainder of the chain
            t = [message UInt32AtOffset:l + 81 + 68] - NSTimeIntervalSince1970;
            
            for (off = l; t > 0 && t < self.earliestKeyTime - (2*HOUR_TIME_INTERVAL + WEEK_TIME_INTERVAL)/4;) {
                off += 81;
                t = [message UInt32AtOffset:off + 81 + 68] - NSTimeIntervalSince1970;
            }
            
            lastHash = uint256_obj([message subdataWithRange:NSMakeRange(off, 80)].x11);
            NSLog(@"%@:%u calling getblocks with locators: %@", self.host, self.port, @[lastHash, firstHash]);
            [self sendGetblocksMessageWithLocators:@[lastHash, firstHash] andHashStop:UINT256_ZERO];
        }
        else {
            NSLog(@"%@:%u calling getheaders with locators: %@", self.host, self.port,
                  @[lastHash, firstHash]);
            [self sendGetheadersMessageWithLocators:@[lastHash, firstHash] andHashStop:UINT256_ZERO];
        }
    }
    else {
        [self error:@"non-standard headers message, %u is fewer headers than expected, last header time is %@, peer version %d", (int)count,[NSDate dateWithTimeIntervalSince1970:t],self.version];
        return;
    }
    for (NSUInteger off = l; off < l + 81*count; off += 81) {
        DSMerkleBlock *block = [DSMerkleBlock blockWithMessage:[message subdataWithRange:NSMakeRange(off, 81)] onChain:self.chain];
        if (! block.valid) {
            [self error:@"invalid block header %@", uint256_obj(block.blockHash)];
            return;
        }
        
        dispatch_async(self.delegateQueue, ^{
            [self.delegate peer:self relayedBlock:block];
        });
    }
}

- (void)acceptGetaddrMessage:(NSData *)message
{
    NSLog(@"%@:%u got getaddr", self.host, self.port);
    [self sendAddrMessage];
}

- (void)acceptGetdataMessage:(NSData *)message
{
    NSNumber * lNumber = nil;
    NSUInteger l, count = (NSUInteger)[message varIntAtOffset:0 length:&lNumber];
    l = lNumber.unsignedIntegerValue;
    
    if (l == 0 || message.length < l + count*36) {
        [self error:@"malformed getdata message, length is %u, should be %u for %u items", (int)message.length,
         (int)(((l == 0) ? 1 : l) + count*36), (int)count];
        return;
    }
    else if (count > MAX_GETDATA_HASHES) {
        NSLog(@"%@:%u dropping getdata message, %u is too many items, max is %u", self.host, self.port, (int)count,
              MAX_GETDATA_HASHES);
        return;
    }
    
    NSLog(@"%@:%u got getdata with %u items", self.host, self.port, (int)count);
    
    dispatch_async(self.delegateQueue, ^{
        NSMutableData *notfound = [NSMutableData data];
        
        for (NSUInteger off = l; off < l + count*36; off += 36) {
            DSInvType type = [message UInt32AtOffset:off];
            UInt256 hash = [message hashAtOffset:off + sizeof(uint32_t)];
            DSTransaction *transaction = nil;
            
            if (uint256_is_zero(hash)) continue;
            
            switch (type) {
                case DSInvType_Tx:
                case DSInvType_TxLockRequest:
                    transaction = [self.delegate peer:self requestedTransaction:hash];
                    
                    if (transaction) {
                        [self sendMessage:transaction.data type:transaction.isInstant?MSG_IX:MSG_TX];
                        break;
                    }
                    
                    // fall through
                default:
                    [notfound appendUInt32:type];
                    [notfound appendBytes:&hash length:sizeof(hash)];
                    break;
            }
        }
        
        if (notfound.length > 0) {
            NSMutableData *msg = [NSMutableData data];
            
            [msg appendVarInt:notfound.length/36];
            [msg appendData:notfound];
            [self sendMessage:msg type:MSG_NOTFOUND];
        }
    });
}

- (void)acceptNotfoundMessage:(NSData *)message
{
    NSNumber * lNumber = nil;
    NSMutableArray *txHashes = [NSMutableArray array], *blockHashes = [NSMutableArray array];
    NSUInteger l, count = (NSUInteger)[message varIntAtOffset:0 length:&lNumber];
    l = lNumber.unsignedIntegerValue;
    
    if (l == 0 || message.length < l + count*36) {
        [self error:@"malformed notfound message, length is %u, should be %u for %u items", (int)message.length,
         (int)(((l == 0) ? 1 : l) + count*36), (int)count];
        return;
    }
    
    NSLog(@"%@:%u got notfound with %u items", self.host, self.port, (int)count);
    
    for (NSUInteger off = l; off < l + 36*count; off += 36) {
        if ([message UInt32AtOffset:off] == DSInvType_Tx) {
            [txHashes addObject:uint256_obj([message hashAtOffset:off + sizeof(uint32_t)])];
        }
        else if ([message UInt32AtOffset:off] == DSInvType_Merkleblock) {
            [blockHashes addObject:uint256_obj([message hashAtOffset:off + sizeof(uint32_t)])];
        }
    }
    
    dispatch_async(self.delegateQueue, ^{
        [self.delegate peer:self notfoundTxHashes:txHashes andBlockHashes:blockHashes];
    });
}

- (void)acceptPingMessage:(NSData *)message
{
    if (message.length < sizeof(uint64_t)) {
        [self error:@"malformed ping message, length is %u, should be 4", (int)message.length];
        return;
    }
#if MESSAGE_LOGGING
    NSLog(@"%@:%u got ping", self.host, self.port);
#endif
    [self sendMessage:message type:MSG_PONG];
}

- (void)acceptPongMessage:(NSData *)message
{
    if (message.length < sizeof(uint64_t)) {
        [self error:@"malformed pong message, length is %u, should be 4", (int)message.length];
        return;
    }
    else if ([message UInt64AtOffset:0] != self.localNonce) {
        [self error:@"pong message contained wrong nonce: %llu, expected: %llu", [message UInt64AtOffset:0],
         self.localNonce];
        return;
    }
    else if (! self.pongHandlers.count) {
        NSLog(@"%@:%u got unexpected pong", self.host, self.port);
        return;
    }
    
    if (self.pingStartTime > 1) {
        NSTimeInterval pingTime = [NSDate timeIntervalSinceReferenceDate] - self.pingStartTime;
        
        // 50% low pass filter on current ping time
        _pingTime = self.pingTime*0.5 + pingTime*0.5;
        self.pingStartTime = 0;
    }
    
#if MESSAGE_LOGGING
    NSLog(@"%@:%u got pong in %fs", self.host, self.port, self.pingTime);
#endif
    
    dispatch_async(self.delegateQueue, ^{
        if (_status == DSPeerStatus_Connected && self.pongHandlers.count) {
            ((void (^)(BOOL))self.pongHandlers[0])(YES);
            [self.pongHandlers removeObjectAtIndex:0];
        }
    });
}

- (void)acceptMerkleblockMessage:(NSData *)message
{
    // Bitcoin nodes don't support querying arbitrary transactions, only transactions not yet accepted in a block. After
    // a merkleblock message, the remote node is expected to send tx messages for the tx referenced in the block. When a
    // non-tx message is received we should have all the tx in the merkleblock.
    DSMerkleBlock *block = [DSMerkleBlock blockWithMessage:message onChain:self.chain];
    
    if (! block.valid) {
        [self error:@"invalid merkleblock: %@", uint256_obj(block.blockHash)];
        return;
    }
    else if (! self.sentFilter && ! self.sentGetdataTxBlocks) {
        [self error:@"got merkleblock message before loading a filter"];
        return;
    }
    //else NSLog(@"%@:%u got merkleblock %@", self.host, self.port, block.blockHash);
    
    NSMutableOrderedSet *txHashes = [NSMutableOrderedSet orderedSetWithArray:block.txHashes];
    
    [txHashes minusOrderedSet:self.knownTxHashes];
    
    if (txHashes.count > 0) { // wait til we get all the tx messages before processing the block
        self.currentBlock = block;
        self.currentBlockTxHashes = txHashes;
    }
    else {
        dispatch_async(self.delegateQueue, ^{
            [self.delegate peer:self relayedBlock:block];
        });
    }
}

// BIP61: https://github.com/bitcoin/bips/blob/master/bip-0061.mediawiki
- (void)acceptRejectMessage:(NSData *)message
{
    NSNumber * offNumber = nil, *lNumber = nil;
    NSUInteger off = 0, l = 0;
    NSString *type = [message stringAtOffset:0 length:&offNumber];
    off = offNumber.unsignedIntegerValue;
    uint8_t code = [message UInt8AtOffset:off++];
    NSString *reason = [message stringAtOffset:off length:&lNumber];
    l = lNumber.unsignedIntegerValue;
    UInt256 txHash = ([MSG_TX isEqual:type] || [MSG_IX isEqual:type]) ? [message hashAtOffset:off + l] : UINT256_ZERO;
    
    NSLog(@"%@:%u rejected %@ code: 0x%x reason: \"%@\"%@%@", self.host, self.port, type, code, reason,
          (uint256_is_zero(txHash) ? @"" : @" txid: "), (uint256_is_zero(txHash) ? @"" : uint256_obj(txHash)));
    reason = nil; // fixes an unused variable warning for non-debug builds
    
    if (! uint256_is_zero(txHash)) {
        dispatch_async(self.delegateQueue, ^{
            [self.delegate peer:self rejectedTransaction:txHash withCode:code];
        });
    }
}

// BIP133: https://github.com/bitcoin/bips/blob/master/bip-0133.mediawiki
- (void)acceptFeeFilterMessage:(NSData *)message
{
    if (message.length < sizeof(uint64_t)) {
        [self error:@"malformed freerate message, length is %u, should be 4", (int)message.length];
        return;
    }
    
    _feePerKb = [message UInt64AtOffset:0];
    NSLog(@"%@:%u got feefilter with rate %llu", self.host, self.port, self.feePerKb);
    
    dispatch_async(self.delegateQueue, ^{
        [self.delegate peer:self setFeePerKb:self.feePerKb];
    });
}

// MARK: - accept Control

- (void)acceptSporkMessage:(NSData *)message
{
    DSSpork * spork = [DSSpork sporkWithMessage:message onChain:self.chain];
    [self.delegate peer:self relayedSpork:spork];
}

// MARK: - accept Masternode

- (void)acceptSSCMessage:(NSData *)message
{
    
    DSSyncCountInfo syncCountInfo = [message UInt32AtOffset:0];
    uint32_t count = [message UInt32AtOffset:4];
    NSLog(@"received ssc message %d %d",syncCountInfo,count);
    switch (syncCountInfo) {
        case DSSyncCountInfo_GovernanceObject:
            if (self.governanceRequestState == DSGovernanceRequestState_GovernanceObjectHashes) {
                self.governanceRequestState = DSGovernanceRequestState_GovernanceObjectHashesCountReceived;
                [self.delegate peer:self relayedSyncInfo:syncCountInfo count:count];
            } else if (self.governanceRequestState == DSGovernanceRequestState_GovernanceObjectHashesReceived) {
                self.governanceRequestState = DSGovernanceRequestState_GovernanceObjects;
                [self.delegate peer:self relayedSyncInfo:syncCountInfo count:count];
            }
            break;
        case DSSyncCountInfo_GovernanceObjectVote:
            if (self.governanceRequestState == DSGovernanceRequestState_GovernanceObjectVoteHashes) {
                self.governanceRequestState = DSGovernanceRequestState_GovernanceObjectVoteHashesCountReceived;
                [self.delegate peer:self relayedSyncInfo:syncCountInfo count:count];
            } else if (self.governanceRequestState == DSGovernanceRequestState_GovernanceObjectVoteHashesReceived) {
                self.governanceRequestState = DSGovernanceRequestState_GovernanceObjectVotes;
                [self.delegate peer:self relayedSyncInfo:syncCountInfo count:count];
            }
            break;
        default:
            [self.delegate peer:self relayedSyncInfo:syncCountInfo count:count];
            break;
    }
    //ignore when count = 0; (for votes)
    
}

-(void)acceptMNBMessage:(NSData *)message
{
    if (self.chain.protocolVersion < 70211) {
        BOOL syncsMasternodeList = !!([[DSOptionsManager sharedInstance] syncType] & DSSyncType_MasternodeList);
        if (syncsMasternodeList) {
            DSMasternodeBroadcast * broadcast = [DSMasternodeBroadcast masternodeBroadcastFromMessage:message onChain:self.chain];
            if (broadcast) {
                [self.delegate peer:self relayedMasternodeBroadcast:broadcast];
            }
        }
    }
}

-(void)acceptMNLISTDIFFMessage:(NSData*)message
{
    [self.delegate peer:self relayedMasternodeDiffMessage:message];
}


// MARK: - accept Governance

// https://dash-docs.github.io/en/developer-reference#govobj

- (void)acceptGovObjectMessage:(NSData *)message
{
    DSGovernanceObject * governanceObject = [DSGovernanceObject governanceObjectFromMessage:message onChain:self.chain];
    if (governanceObject) {
        [self.delegate peer:self relayedGovernanceObject:governanceObject];
    }
}

- (void)acceptGovObjectVoteMessage:(NSData *)message
{
    DSGovernanceVote * governanceVote = [DSGovernanceVote governanceVoteFromMessage:message onChain:self.chain];
    if (governanceVote) {
        [self.delegate peer:self relayedGovernanceVote:governanceVote];
    }
}

- (void)acceptGovObjectSyncMessage:(NSData *)message
{
    
}

// MARK: - Accept Dark send

- (void)acceptDarksendAnnounceMessage:(NSData *)message
{
    
}

- (void)acceptDarksendControlMessage:(NSData *)message
{
    
}

- (void)acceptDarksendFinishMessage:(NSData *)message
{
    
}

- (void)acceptDarksendInitiateMessage:(NSData *)message
{
    
}

- (void)acceptDarksendQuorumMessage:(NSData *)message
{
    
}

- (void)acceptDarksendSessionMessage:(NSData *)message
{
    
}

- (void)acceptDarksendSessionUpdateMessage:(NSData *)message
{
    
}

- (void)acceptDarksendTransactionMessage:(NSData *)message
{
    //    BRTransaction *tx = [BRTransaction transactionWithMessage:message];
    //
    //    if (! tx) {
    //        [self error:@"malformed tx message: %@", message];
    //        return;
    //    }
    //    else if (! self.sentFilter && ! self.sentTxAndBlockGetdata) {
    //        [self error:@"got tx message before loading a filter"];
    //        return;
    //    }
    //
    //    NSLog(@"%@:%u got tx %@", self.host, self.port, uint256_obj(tx.txHash));
    //
    //    dispatch_async(self.delegateQueue, ^{
    //        [self.delegate peer:self relayedTransaction:tx];
    //    });
    //
    //    if (self.currentBlock) { // we're collecting tx messages for a merkleblock
    //        [self.currentBlockTxHashes removeObject:uint256_obj(tx.txHash)];
    //
    //        if (self.currentBlockTxHashes.count == 0) { // we received the entire block including all matched tx
    //            BRMerkleBlock *block = self.currentBlock;
    //
    //            self.currentBlock = nil;
    //            self.currentBlockTxHashes = nil;
    //
    //            dispatch_sync(self.delegateQueue, ^{ // syncronous dispatch so we don't get too many queued up tx
    //                [self.delegate peer:self relayedBlock:block];
    //            });
    //        }
    //    }
}

// MARK: - hash

#define FNV32_PRIME  0x01000193u
#define FNV32_OFFSET 0x811C9dc5u

// FNV32-1a hash of the ip address and port number: http://www.isthe.com/chongo/tech/comp/fnv/index.html#FNV-1a
- (NSUInteger)hash
{
    uint32_t hash = FNV32_OFFSET;
    
    for (int i = 0; i < sizeof(_address); i++) {
        hash = (hash ^ _address.u8[i])*FNV32_PRIME;
    }
    
    hash = (hash ^ ((_port >> 8) & 0xff))*FNV32_PRIME;
    hash = (hash ^ (_port & 0xff))*FNV32_PRIME;
    return hash;
}

// two peer objects are equal if they share an ip address and port number
- (BOOL)isEqual:(id)object
{
    return (self == object || ([object isKindOfClass:[DSPeer class]] && _port == ((DSPeer *)object).port &&
                               uint128_eq(_address, [(DSPeer *)object address]))) ? YES : NO;
}

// MARK: - Info

-(NSString*)chainTip {
    return [NSData dataWithUInt256:self.currentBlock.blockHash].shortHexString;
}

// MARK: - NSStreamDelegate

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode
{
    switch (eventCode) {
        case NSStreamEventOpenCompleted:
            NSLog(@"%@:%u %@ stream connected in %fs", self.host, self.port,
                  (aStream == self.inputStream) ? @"input" : (aStream == self.outputStream ? @"output" : @"unknown"),
                  [NSDate timeIntervalSinceReferenceDate] - self.pingStartTime);
            
            if (aStream == self.outputStream) {
                self.pingStartTime = [NSDate timeIntervalSinceReferenceDate]; // don't count connect time in ping time
                [NSObject cancelPreviousPerformRequestsWithTarget:self]; // cancel pending socket connect timeout
                [self performSelector:@selector(disconnectWithError:)
                           withObject:[NSError errorWithDomain:@"DashWallet" code:BITCOIN_TIMEOUT_CODE
                                                      userInfo:@{NSLocalizedDescriptionKey:NSLocalizedString(@"connect timeout", nil)}]
                           afterDelay:CONNECT_TIMEOUT];
            }
            
            // fall through to send any queued output
        case NSStreamEventHasSpaceAvailable:
            if (aStream != self.outputStream) return;
            
            while (self.outputBuffer.length > 0 && self.outputStream.hasSpaceAvailable) {
                NSInteger l = [self.outputStream write:self.outputBuffer.bytes maxLength:self.outputBuffer.length];
                
                if (l > 0) [self.outputBuffer replaceBytesInRange:NSMakeRange(0, l) withBytes:NULL length:0];
            }
            
            break;
            
        case NSStreamEventHasBytesAvailable:
            if (aStream != self.inputStream) return;
            
            while (self.inputStream.hasBytesAvailable) {
                @autoreleasepool {
                    NSData *message = nil;
                    NSString *type = nil;
                    NSInteger headerLen = self.msgHeader.length, payloadLen = self.msgPayload.length, l = 0;
                    uint32_t length = 0, checksum = 0;
                    
                    if (headerLen < HEADER_LENGTH) { // read message header
                        self.msgHeader.length = HEADER_LENGTH;
                        l = [self.inputStream read:(uint8_t *)self.msgHeader.mutableBytes + headerLen
                                         maxLength:self.msgHeader.length - headerLen];
                        
                        if (l < 0) {
                            NSLog(@"%@:%u error reading message", self.host, self.port);
                            goto reset;
                        }
                        
                        self.msgHeader.length = headerLen + l;
                        
                        // consume one byte at a time, up to the magic number that starts a new message header
                        while (self.msgHeader.length >= sizeof(uint32_t) &&
                               [self.msgHeader UInt32AtOffset:0] != self.chain.magicNumber) {
#if DEBUG
                            printf("%c", *(const char *)self.msgHeader.bytes);
#endif
                            [self.msgHeader replaceBytesInRange:NSMakeRange(0, 1) withBytes:NULL length:0];
                        }
                        
                        if (self.msgHeader.length < HEADER_LENGTH) continue; // wait for more stream input
                    }
                    
                    if ([self.msgHeader UInt8AtOffset:15] != 0) { // verify msg type field is null terminated
                        [self error:@"malformed message header: %@", self.msgHeader];
                        goto reset;
                    }
                    
                    type = @((const char *)self.msgHeader.bytes + 4);
                    length = [self.msgHeader UInt32AtOffset:16];
                    checksum = [self.msgHeader UInt32AtOffset:20];
                    
                    if (length > MAX_MSG_LENGTH) { // check message length
                        [self error:@"error reading %@, message length %u is too long", type, length];
                        goto reset;
                    }
                    
                    if (payloadLen < length) { // read message payload
                        self.msgPayload.length = length;
                        l = [self.inputStream read:(uint8_t *)self.msgPayload.mutableBytes + payloadLen
                                         maxLength:self.msgPayload.length - payloadLen];
                        
                        if (l < 0) {
                            NSLog(@"%@:%u error reading %@", self.host, self.port, type);
                            goto reset;
                        }
                        
                        self.msgPayload.length = payloadLen + l;
                        if (self.msgPayload.length < length) continue; // wait for more stream input
                    }
                    
                    if (CFSwapInt32LittleToHost(self.msgPayload.SHA256_2.u32[0]) != checksum) { // verify checksum
                        [self error:@"error reading %@, invalid checksum %x, expected %x, payload length:%u, expected "
                         "length:%u, SHA256_2:%@", type, self.msgPayload.SHA256_2.u32[0], checksum,
                         (int)self.msgPayload.length, length, uint256_obj(self.msgPayload.SHA256_2)];
                        goto reset;
                    }
                    
                    message = self.msgPayload;
                    self.msgPayload = [NSMutableData data];
                    [self acceptMessage:message type:type]; // process message
                    
                reset:              // reset for next message
                    self.msgHeader.length = self.msgPayload.length = 0;
                }
            }
            
            break;
            
        case NSStreamEventErrorOccurred:
            NSLog(@"%@:%u error connecting, %@", self.host, self.port, aStream.streamError);
            [self disconnectWithError:aStream.streamError];
            break;
            
        case NSStreamEventEndEncountered:
            NSLog(@"%@:%u connection closed", self.host, self.port);
            [self disconnectWithError:nil];
            break;
            
        default:
            NSLog(@"%@:%u unknown network stream eventCode:%u", self.host, self.port, (int)eventCode);
    }
}

@end
